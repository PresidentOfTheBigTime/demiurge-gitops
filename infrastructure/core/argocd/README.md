# ArgoCD

## Install
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Initial Setup
```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Expose via ingress (or port-forward for first access)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Register Git Repo
Via the ArgoCD UI or CLI, add the demiurge-gitops repo:
- Repo URL: git@github.com:PresidentOfTheBigTime/demiurge-gitops.git
- Use SSH key or HTTPS with PAT

## Application Definitions
Each app has an ArgoCD Application resource in `clusters/k3s-c1/`.
After ArgoCD is running, apply them:
```bash
kubectl apply -f clusters/k3s-c1/
```
