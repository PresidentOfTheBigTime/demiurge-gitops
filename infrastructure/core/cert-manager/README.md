# Cert-Manager

Installed via static manifests (not Helm).

## Install Command
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
```

## Post-Install
1. Create the Cloudflare API token secret:
```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN
```

2. Apply the ClusterIssuer:
```bash
kubectl apply -f infrastructure/core/cert-manager/clusterissuer.yaml
```
