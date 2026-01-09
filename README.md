# Demiurge GitOps - v2 (Clean Rebuild)

**New infrastructure started: January 2026**

## Architecture
- Single k3s node (k3s-c1): 100.116.36.54
- ArgoCD for GitOps deployments  
- Rancher for monitoring/troubleshooting
- Longhorn for persistent storage

## Structure
- `apps/` - Application deployments (Vikunja, etc.)
- `infrastructure/` - Core services (already installed via Helm)
- `clusters/k3s-c1/` - Cluster-specific configs

## Access
- Rancher: https://rancher.home.arpa
- ArgoCD: https://argocd.home.arpa

## Old Infrastructure
Archived locally: ~/demiurge-gitops-OLD-ARCHIVE
