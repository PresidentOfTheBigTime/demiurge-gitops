# Demiurge Architecture

Last verified: February 2026

## Physical Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Home Network (192.168.0.0/24)                │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │   pve1 (ProDesk)  │  │   pve2 (ProDesk)  │  │  pve3 (T5810)   │  │
│  │   i7-7700 16GB    │  │   i7-7700 16GB    │  │  E5-2698v3 64GB │  │
│  │   192.168.0.x     │  │   192.168.0.x     │  │  192.168.0.x    │  │
│  │                    │  │                    │  │                  │  │
│  │  ┌──────────────┐ │  │  ┌──────────────┐ │  │  ┌────────────┐ │  │
│  │  │   k3s-c1     │ │  │  │   k3s-c2     │ │  │  │   k3s-c3   │ │  │
│  │  │ .231 (ctrl)  │ │  │  │ .232 (ctrl)  │ │  │  │ .233 (ctrl)│ │  │
│  │  │ Tailscale    │ │  │  │              │ │  │  │ Ollama here│ │  │
│  │  └──────────────┘ │  │  └──────────────┘ │  │  └────────────┘ │  │
│  │                    │  │                    │  │                  │  │
│  │  [HOAS VM]         │  │                    │  │  [NVIDIA K4000] │  │
│  │  [dns1 LXC]        │  │                    │  │                  │  │
│  │  [2TB USB HDD]     │  │                    │  │                  │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
│  MetalLB Pool: 192.168.0.240-245                                   │
│  Ingress (nginx): 192.168.0.240                                    │
│  Squid Proxy: 192.168.0.242                                        │
└─────────────────────────────────────────────────────────────────────┘
```

## k3s Cluster

All three nodes are **control-plane + etcd + worker** (HA embedded etcd).

| Node | Proxmox Host | IP | Tailscale | Role |
|------|-------------|-----|-----------|------|
| k3s-c1 | pve1 (ProDesk) | 192.168.0.231 | 100.116.36.54 | Control plane, etcd, worker |
| k3s-c2 | pve2 (ProDesk) | 192.168.0.232 | — | Control plane, etcd, worker |
| k3s-c3 | pve3 (T5810) | 192.168.0.233 | — | Control plane, etcd, worker, GPU workloads |

k3s version: v1.34.3+k3s1
OS: Ubuntu 24.04.3 LTS
k3s config (`/etc/rancher/k3s/config.yaml`):
```yaml
cluster-init: true    # first node only; join nodes use server: + token:
disable:
  - traefik           # using nginx ingress instead
```

## Platform Stack (not in ArgoCD)

These are installed via `scripts/bootstrap-node.sh platform` and exist outside GitOps:

| Component | Install Method | Version/Chart | Namespace |
|-----------|---------------|---------------|-----------|
| Tailscale | apt (pkgs.tailscale.com/stable) | 1.94.2 | N/A (host-level) |
| MetalLB | kubectl apply (static manifests) | v0.14.9 | metallb-system |
| Ingress-Nginx | kubectl apply (static manifests) | controller-v1.12.0 | ingress-nginx |
| Cert-Manager | kubectl apply (static manifests) | v1.16.3 | cert-manager |
| Longhorn | Helm (via Rancher marketplace) | 108.2.0+up1.10.1 (v1.10.1) | longhorn-system |
| Rancher | Helm | 2.13.1 | cattle-system |
| ArgoCD | kubectl apply (static manifests) | stable | argocd |

## Application Stack (managed by ArgoCD)

| Service | Namespace | Ingress Host | Storage |
|---------|-----------|-------------|---------|
| Vaultwarden | vaultwarden | vaultwarden.massivehog.win | 1Gi longhorn |
| Vikunja + Postgres | vikunja | vikunja.massivehog.win | 5Gi + 10Gi longhorn |
| Ollama + OpenWebUI | ollama | chat.massivehog.win | 50Gi + 5Gi longhorn |
| Perplexica + SearXNG | perplexica | search.massivehog.win | 5Gi longhorn |
| Syncthing | syncthing | sync.massivehog.win | 1Gi + 50Gi longhorn |
| Squid Proxy | squid | — (LoadBalancer .242) | hostPath on k3s-c3 |
| Cloudflared | cloudflared | — (tunnel) | — |

## DNS and Certificates

- Domain: massivehog.win (Cloudflare)
- Cert issuer: Let's Encrypt (ACME DNS01 via Cloudflare)
- Cloudflared tunnel routes public traffic to ingress
- Internal access via Tailscale to node IPs

## Tailscale

Installed via apt on every k3s VM (host-level, not in-cluster operator).

| Device | Tailscale IP | Notes |
|--------|-------------|-------|
| k3s-c1 | 100.116.36.54 | Primary access point |
| k3s-c2 | 100.70.218.115 | |
| k3s-c3 | 100.119.245.94 | |
| dns1 | 100.64.117.89 | Pi-hole + Unbound LXC on pve1 |
| desktop | 100.79.155.9 | the-throne |
| phone-1 | 100.80.110.26 | Samsung A55 |
| badtop | 100.99.148.126 | CachyOS laptop |

Tailnet: carp-barb.ts.net

- Pi-hole is Tailnet DNS server (set in Tailscale admin console)
- Pi-hole resolves *.massivehog.win → 192.168.0.241 (ingress)


**Note:** `--accept-routes` is currently false on k3s nodes, meaning they ignore subnet routes from dns1. This is a future fix — not currently breaking anything but would allow using Pi-hole DNS over Tailscale when remote.

Each node authenticates individually via `tailscale up` during bootstrap. Auth keys can be pre-generated from the Tailscale admin console for unattended setup.

## Secrets Management

- SOPS with age encryption
- Age key: `~/.config/sops/age/keys.txt` (backed up in Vaultwarden)
- Age recipient: `age1wglfkyp8462uyjv4hm2f98d42w9vylpkcz70hlpy3smdlazteg4qxlsf7f`
- Secrets applied via cron every 5 minutes: `scripts/apply-secrets.sh`

## Storage

- Longhorn distributed block storage (currently **replica count 1** — no redundancy)
- Storage classes: `longhorn` (default), `longhorn-static`, `local-path`
- Longhorn backup target: 2TB USB HDD on pve1 (daily at 2am)
- Longhorn stale mount cleanup: systemd service runs before k3s on boot

## Automation

- Renovate: auto-merges minor/patch image updates on weekends
- Unattended-upgrades: security patches auto-installed, reboot at 4am if needed
