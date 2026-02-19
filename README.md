# Demiurge GitOps

Private cloud infrastructure for cognitive support and self-hosted services.

## Quick Links
- **Everything is dead?** → [docs/REBUILD-RUNBOOK.md](docs/REBUILD-RUNBOOK.md)
- **How does this work?** → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Adding a new service?** → See [Adding Services](#adding-services) below

## Architecture
- 3-node k3s HA cluster (k3s-c1, k3s-c2, k3s-c3)
- Each node is a VM on its own Proxmox host (pve1, pve2, pve3)
- ArgoCD for GitOps (apps only — platform installed via bootstrap script)
- Longhorn for distributed storage with NFS backups to USB HDD
- SOPS (age) for secrets encryption

## Repo Structure
```
demiurge-gitops/
├── apps/                          ← Service deployments (ArgoCD-managed)
│   ├── vaultwarden/
│   ├── vikunja/
│   ├── ollama/
│   ├── perplexica/
│   ├── syncthing/
│   ├── squid/
│   └── cloudflared/
├── infrastructure/
│   └── core/                      ← Platform component configs (reference + bootstrap)
│       ├── metallb/               ← IP pool config
│       ├── cert-manager/          ← ClusterIssuer
│       ├── ingress-nginx/         ← Install notes
│       ├── longhorn/              ← Helm values
│       └── argocd/                ← Install notes
├── clusters/
│   └── k3s-c1/                    ← ArgoCD Application definitions
├── secrets/                       ← SOPS-encrypted secrets
├── scripts/
│   ├── bootstrap-node.sh          ← From bare metal to working cluster
│   └── apply-secrets.sh           ← Decrypt and apply all secrets
├── docs/
│   ├── REBUILD-RUNBOOK.md         ← Start here if everything is dead
│   └── ARCHITECTURE.md            ← Current topology reference
├── .sops.yaml                     ← SOPS encryption config
└── renovate.json                  ← Automated dependency updates
```

## Nodes
| Node | Proxmox | Local IP | Tailscale |
|------|---------|----------|-----------|
| k3s-c1 | pve1 (ProDesk 600 G3) | 192.168.0.231 | 100.116.36.54 |
| k3s-c2 | pve2 (ProDesk 600 G3) | 192.168.0.232 | — |
| k3s-c3 | pve3 (Dell T5810) | 192.168.0.233 | — |

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

## Adding Services

1. Create a directory under `apps/your-service/` with namespace.yaml, deployment.yaml, service.yaml, ingress.yaml, pvc.yaml
2. Add an ArgoCD Application block to `clusters/k3s-c1/apps.yaml`
3. If the service needs secrets, create a SOPS-encrypted file in `secrets/`
4. Commit and push — ArgoCD syncs automatically

## Secrets
Encrypted with SOPS (age). Applied via cron every 5 min.
- Key: `~/.config/sops/age/keys.txt` (backed up in Vaultwarden)
- Config: `.sops.yaml`
- Apply manually: `bash scripts/apply-secrets.sh`
