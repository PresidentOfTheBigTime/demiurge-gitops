# MetalLB

Installed via static manifests (not Helm).

## Install Command
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
```

## Post-Install
Apply the config manifests in this directory:
```bash
kubectl apply -f infrastructure/core/metallb/config.yaml
```
