#!/bin/bash
# Decrypt and apply all SOPS-encrypted secrets
for f in ~/demiurge-gitops/secrets/*.yaml; do
  sops --decrypt "$f" | kubectl apply -f - 2>&1
done
