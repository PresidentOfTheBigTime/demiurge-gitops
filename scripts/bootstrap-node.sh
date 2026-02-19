#!/bin/bash
# =============================================================================
# Demiurge Bootstrap Script
# =============================================================================
# Run this on a fresh Ubuntu 24.04 VM to bring it into the k3s cluster
# and install all platform components.
#
# Prerequisites:
#   - Fresh Ubuntu 24.04 VM with static IP configured
#   - SSH access from the-throne
#   - Internet access
#   - Tailscale account (will prompt to authenticate)
#
# Usage:
#   For the FIRST node (initializes new cluster):
#     ./bootstrap-node.sh init
#
#   For ADDITIONAL nodes (joins existing cluster):
#     ./bootstrap-node.sh join <server-ip> <token>
#
#   To install platform components (run ONCE after first node is ready):
#     ./bootstrap-node.sh platform
#
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------
install_tailscale() {
    log "Installing Tailscale..."
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | \
        sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | \
        sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y tailscale

    log "Tailscale installed. Authenticate now:"
    sudo tailscale up
    log "Tailscale connected. Verify with: tailscale status"
}

# ---------------------------------------------------------------------------
# k3s Install (init or join)
# ---------------------------------------------------------------------------
install_k3s_init() {
    log "Installing k3s (first server, cluster-init mode)..."

    # Create k3s config
    sudo mkdir -p /etc/rancher/k3s
    sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<EOF
cluster-init: true
disable:
  - traefik
EOF

    curl -sfL https://get.k3s.io | sh -

    log "Waiting for k3s to be ready..."
    sleep 10
    sudo kubectl wait --for=condition=Ready node --all --timeout=120s

    # Show join token for other nodes
    log "k3s initialized. Join token:"
    sudo cat /var/lib/rancher/k3s/server/token
    echo ""
    log "Other nodes join with:"
    echo "  ./bootstrap-node.sh join $(hostname -I | awk '{print $1}') <token-above>"
}

install_k3s_join() {
    local SERVER_IP="$1"
    local TOKEN="$2"

    log "Joining k3s cluster at ${SERVER_IP}..."

    sudo mkdir -p /etc/rancher/k3s
    sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<EOF
server: https://${SERVER_IP}:6443
token: ${TOKEN}
disable:
  - traefik
EOF

    curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="${TOKEN}" sh -s - server

    log "Waiting for node to join..."
    sleep 15
    sudo kubectl get nodes
}

# ---------------------------------------------------------------------------
# Platform Components (run once on first node after init)
# ---------------------------------------------------------------------------
install_platform() {
    log "Installing platform components..."

    # 1. MetalLB
    log "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
    log "Waiting for MetalLB controller..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s

    log "Applying MetalLB config (IP pool 192.168.0.240-245)..."
    kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.240-192.168.0.245
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - local-pool
EOF

    # 2. Ingress-Nginx
    log "Installing Ingress-Nginx..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml
    # Patch to use LoadBalancer instead of NodePort
    kubectl patch svc ingress-nginx-controller -n ingress-nginx \
        -p '{"spec":{"type":"LoadBalancer"}}'
    log "Waiting for Ingress-Nginx..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s

    # 3. Cert-Manager
    log "Installing Cert-Manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
    log "Waiting for Cert-Manager..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=120s

    warn "MANUAL STEP: Create Cloudflare API token secret:"
    echo "  kubectl create secret generic cloudflare-api-token \\"
    echo "    --namespace cert-manager \\"
    echo "    --from-literal=api-token=YOUR_TOKEN"
    echo ""
    warn "Then apply the ClusterIssuer:"
    echo "  kubectl apply -f infrastructure/core/cert-manager/clusterissuer.yaml"
    echo ""

    # 4. Longhorn
    log "Installing Longhorn via Helm..."
    helm repo add longhorn https://charts.longhorn.io
    helm repo update
    helm install longhorn longhorn/longhorn \
        --namespace longhorn-system --create-namespace \
        --set defaultSettings.defaultReplicaCount=1 \
        --set defaultSettings.defaultDataPath=/var/lib/longhorn \
        --set persistence.defaultClassReplicaCount=1 \
        --set csi.kubeletRootDir=/var/lib/kubelet
    log "Waiting for Longhorn..."
    kubectl wait --namespace longhorn-system \
        --for=condition=ready pod \
        --selector=app=longhorn-manager \
        --timeout=300s

    # 5. ArgoCD
    log "Installing ArgoCD..."
    kubectl create namespace argocd || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    log "Waiting for ArgoCD..."
    kubectl wait --namespace argocd \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=argocd-server \
        --timeout=180s

    ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    log "ArgoCD initial admin password: ${ARGOCD_PASS}"
    warn "SAVE THIS PASSWORD IN VAULTWARDEN"
    echo ""

    warn "MANUAL STEPS REMAINING:"
    echo "  1. Create Cloudflare API token secret (see above)"
    echo "  2. Apply ClusterIssuer: kubectl apply -f infrastructure/core/cert-manager/clusterissuer.yaml"
    echo "  3. Connect ArgoCD to your git repo via the UI"
    echo "  4. Apply ArgoCD apps: kubectl apply -f clusters/k3s-c1/apps.yaml"
    echo "  5. Apply SOPS secrets: bash scripts/apply-secrets.sh"
    echo ""
    log "Platform bootstrap complete!"
}

# ---------------------------------------------------------------------------
# Longhorn stale mount cleanup (install as systemd service)
# ---------------------------------------------------------------------------
install_longhorn_cleanup() {
    log "Installing Longhorn stale mount cleanup service..."
    sudo tee /etc/systemd/system/longhorn-cleanup.service > /dev/null <<EOF
[Unit]
Description=Clean stale Longhorn device mapper entries
Before=k3s.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'dmsetup ls | grep longhorn | awk "{print \\$1}" | while read dm; do dmsetup remove "\\$dm" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable longhorn-cleanup.service
    log "Longhorn cleanup service installed (runs before k3s on boot)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "${1:-help}" in
    init)
        install_tailscale
        install_k3s_init
        install_longhorn_cleanup
        ;;
    join)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && err "Usage: $0 join <server-ip> <token>"
        install_tailscale
        install_k3s_join "$2" "$3"
        install_longhorn_cleanup
        ;;
    platform)
        install_platform
        ;;
    cleanup)
        install_longhorn_cleanup
        ;;
    tailscale)
        install_tailscale
        ;;
    *)
        echo "Usage: $0 {init|join <ip> <token>|platform|cleanup|tailscale}"
        echo ""
        echo "  init      - Install Tailscale, initialize first k3s server node"
        echo "  join      - Install Tailscale, join an existing cluster"
        echo "  platform  - Install MetalLB, Ingress, Cert-Manager, Longhorn, ArgoCD"
        echo "  cleanup   - Install Longhorn stale mount cleanup systemd service"
        echo "  tailscale - Install Tailscale only (for existing nodes)"
        ;;
esac
