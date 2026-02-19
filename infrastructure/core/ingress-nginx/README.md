# Ingress-Nginx

Installed via static manifests (not Helm).

## Install Command
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml
```

## Notes
- k3s default Traefik is disabled via `/etc/rancher/k3s/config.yaml`
- IngressClass name: `nginx`
- Gets a LoadBalancer IP from MetalLB (currently 192.168.0.240)
