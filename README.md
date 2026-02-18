# Demiurge GitOps

Private cloud infrastructure for cognitive support and self-hosted services.

## Architecture
- 3-node k3s HA cluster (k3s-c1, k3s-c2, k3s-c3)
- Each node is a VM on its own Proxmox host (pve1, pve2, pve3)
- ArgoCD for GitOps deployments
- Longhorn for distributed storage with NFS backups to USB HDD
- SOPS (age) for secrets encryption

## Nodes
| Node | Proxmox | Local IP | Tailscale |
|------|---------|----------|-----------|
| k3s-c1 | pve1 (ProDesk 600 G3) | 192.168.0.231 | 100.116.36.54 |
| k3s-c2 | pve2 (ProDesk 600 G3) | 192.168.0.232 | - |
| k3s-c3 | pve3 (Dell T5810) | 192.168.0.233 | - |

## Services
| Service | URL | Namespace |
|---------|-----|-----------|
| Vaultwarden | vaultwarden.massivehog.win | vaultwarden |
| Vikunja | vikunja.massivehog.win | vikunja |
| OpenWebUI | chat.massivehog.win | ollama |
| Perplexica | search.massivehog.win | perplexica |
| Syncthing | sync.massivehog.win | syncthing |
| ArgoCD | argocd.massivehog.win | argocd |
| Longhorn | longhorn.massivehog.win | longhorn-system |

## Infrastructure
- MetalLB: 192.168.0.240-245
- Nginx Ingress, Cert-manager (letsencrypt-prod)
- Squid caching proxy: 192.168.0.242
- Rancher for monitoring

## Secrets
Encrypted with SOPS (age) in `secrets/` directory. Applied via cron every 5 min.
- Key: `~/.config/sops/age/keys.txt` (backed up in Vaultwarden)
- Config: `.sops.yaml`

## Automation
- Renovate: auto-merges minor/patch image updates on weekends
- Longhorn: daily backups at 2am, snapshot cleanup at 3am
- Unattended-upgrades: security patches auto-installed, reboot at 4am if needed
- Longhorn cleanup: systemd service clears stale mounts before k3s starts
