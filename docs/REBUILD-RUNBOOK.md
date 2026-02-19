# Demiurge Rebuild Runbook

**Start here if everything is dead.**

This document walks you through rebuilding the entire cluster from scratch.
Total time: ~2-3 hours across multiple sessions.

---

## What You Need Before Starting

1. **This git repo** cloned to the-throne: `~/demiurge-gitops`
2. **SOPS age key**: `~/.config/sops/age/keys.txt` (backed up in Vaultwarden — if Vaultwarden is dead, check your phone's Bitwarden app which should have offline cache)
3. **Cloudflare API token** for DNS challenges (also in Vaultwarden)
4. **Cloudflared tunnel token** (also in Vaultwarden)
5. **Tailscale account access** — you'll need to authenticate each node. Generate a reusable auth key beforehand at https://login.tailscale.com/admin/settings/keys to save time
6. Physical access to Proxmox hosts (monitor + keyboard, or existing Proxmox web UI)

---

## Phase 1: Proxmox VMs (30 min per node)

### If Proxmox itself needs reinstalling
1. Download Proxmox VE ISO from proxmox.com
2. Flash to USB with Ventoy or Rufus
3. Boot from USB, install Proxmox
4. Set static IP for the Proxmox host (not the VM — these are different)
5. Access Proxmox web UI at `https://<host-ip>:8006`

### Create the k3s VM on each Proxmox host

These are the specs for each k3s VM:

| Setting | pve1 (ProDesk) | pve2 (ProDesk) | pve3 (T5810) |
|---------|---------------|---------------|--------------|
| OS | Ubuntu 24.04 Server | Ubuntu 24.04 Server | Ubuntu 24.04 Server |
| CPU | 6 cores | 6 cores | 14 cores |
| RAM | 14 GB | 14 GB | 56 GB |
| Disk | 200 GB (boot) | 200 GB (boot) | 200 GB (boot) |
| Network | Bridge to host NIC | Bridge to host NIC | Bridge to host NIC |
| Static IP | 192.168.0.231/24 | 192.168.0.232/24 | 192.168.0.233/24 |
| Gateway | 192.168.0.1 | 192.168.0.1 | 192.168.0.1 |
| DNS | 192.168.0.250 | 192.168.0.250 | 192.168.0.250 |
| Hostname | k3s-c1 | k3s-c2 | k3s-c3 |
| Username | alex | alex | alex |

Use cloud-init or manual install. After VM is up, ensure:
```bash
# SSH works from the-throne
ssh alex@192.168.0.231

# Internet works
ping -c 2 8.8.8.8

# Set hostname if not done via cloud-init
sudo hostnamectl set-hostname k3s-c1
```

### pve1 also has:
- **Home Assistant VM** (separate VM, not in k3s)
- **dns1 LXC** container (Pi-hole + Unbound + Tailscale)
- **2TB USB HDD** mounted for Longhorn backups

---

## Phase 2: k3s Cluster (20 min)

The bootstrap script installs Tailscale first (for remote access), then k3s.

### First node (k3s-c1)
```bash
# On k3s-c1:
cd ~/demiurge-gitops
bash scripts/bootstrap-node.sh init
```

This will:
1. Install Tailscale and prompt you to authenticate (browser link)
2. Install k3s in cluster-init mode
3. Install the Longhorn stale mount cleanup service

Save the join token it prints.

### Additional nodes (k3s-c2, k3s-c3)
```bash
# On k3s-c2 and k3s-c3:
bash scripts/bootstrap-node.sh join 192.168.0.231 <TOKEN>
```

Each node will prompt for Tailscale auth — approve each in the Tailscale admin console or use a pre-auth key.

**Tip:** Generate a reusable auth key at https://login.tailscale.com/admin/settings/keys to skip the browser auth on each node.

### Verify cluster
```bash
# From any node or the-throne (after copying kubeconfig):
kubectl get nodes
# Should show all 3 nodes as Ready
```

### Copy kubeconfig to the-throne
```bash
# On k3s-c1:
sudo cat /etc/rancher/k3s/k3s.yaml

# On the-throne, paste into ~/.kube/config
# Change server: line to https://192.168.0.231:6443
```

---

## Phase 3: Platform Components (15 min)

```bash
# From the-throne (needs kubectl working):
cd ~/demiurge-gitops
bash scripts/bootstrap-node.sh platform
```

This installs MetalLB, Ingress-Nginx, Cert-Manager, Longhorn, and ArgoCD.

### Manual steps after platform install:

1. **Cloudflare API token** (for Let's Encrypt DNS challenges):
```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN_FROM_VAULTWARDEN
```

2. **ClusterIssuer**:
```bash
kubectl apply -f infrastructure/core/cert-manager/clusterissuer.yaml
```

3. **Connect ArgoCD to git repo** via the UI at localhost:8080 (port-forward first):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Login: admin / <password from bootstrap output>
# Add repo: git@github.com:PresidentOfTheBigTime/demiurge-gitops.git
```

---

## Phase 4: Deploy Apps (10 min)

1. **Apply ArgoCD Application definitions**:
```bash
kubectl apply -f clusters/k3s-c1/apps.yaml
```

2. **Apply SOPS secrets**:
```bash
bash scripts/apply-secrets.sh
```

3. **Apply Cloudflared token** (not in SOPS yet):
```bash
kubectl create secret generic cloudflared-token \
  --namespace cloudflared \
  --from-literal=token=YOUR_TUNNEL_TOKEN_FROM_VAULTWARDEN
```

4. **Verify in ArgoCD UI**:
   - All apps should show Synced + Healthy
   - Check vaultwarden.massivehog.win loads

---

## Phase 5: Post-Recovery Checks

```bash
# All nodes ready
kubectl get nodes

# All pods running
kubectl get pods -A | grep -v Running | grep -v Completed

# Longhorn healthy
kubectl get volumes.longhorn.io -n longhorn-system

# Services accessible
curl -s -o /dev/null -w "%{http_code}" https://vaultwarden.massivehog.win
curl -s -o /dev/null -w "%{http_code}" https://vikunja.massivehog.win

# ArgoCD apps synced
kubectl get applications -n argocd
```

---

## Restoring Data

If you have Longhorn backups on the USB HDD:
1. Open Longhorn UI (port-forward or ingress)
2. Go to Backup tab
3. Restore volumes from the most recent backup
4. Reattach to the correct PVCs

If no backups exist, services start fresh with empty databases.

---

## Known Issues and Fixes

### Longhorn stale mounts after reboot
The `longhorn-cleanup.service` (installed by bootstrap) handles this automatically.
If pods are stuck after reboot:
```bash
sudo dmsetup ls | grep longhorn | awk '{print $1}' | while read dm; do sudo dmsetup remove "$dm" 2>/dev/null; done
sudo systemctl restart k3s
```

### Node won't rejoin cluster
Check token is correct and k3s-c1 is reachable:
```bash
curl -k https://192.168.0.231:6443
sudo journalctl -u k3s -f
```

### Vaultwarden locked out
If you've lost access to Vaultwarden AND your phone's Bitwarden offline cache:
- SOPS age key is needed to decrypt secrets
- If age key is also lost, you'll need to generate new secrets and re-create accounts
