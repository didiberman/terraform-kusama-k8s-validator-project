#!/bin/bash
set -euo pipefail

# K3s Control Plane Bootstrap Script

echo "=== Installing K3s Control Plane ==="



# Install K3s server
# We use the private network interface (enp7s0) for internal cluster traffic
curl -sfL https://get.k3s.io | sh -s - server \
  --token "${k3s_token}" \
  --cluster-init \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --node-name "${cluster_name}-control-plane" \
  --flannel-iface enp7s0 \
  --node-ip $(ip -4 addr show enp7s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}') \
  --tls-san $(curl -4s https://ifconfig.me) \
  %{ if taint_control_plane }--node-taint CriticalAddonsOnly=true:NoExecute%{ endif }




# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 5
done

echo "=== K3s Control Plane Ready ==="

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ArgoCD
echo "=== Installing ArgoCD ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

# Install Sealed Secrets
echo "=== Installing Sealed Secrets ==="
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# Install Hetzner Cloud Controller Manager
echo "=== Installing Hetzner CCM ==="
kubectl create namespace hcloud-system --dry-run=client -o yaml | kubectl apply -f -

# Deploy Hetzner Cloud Controller Manager
# Note: The 'hetzner-cloud' secret must be created manually or via sealed-secrets
kubectl create namespace hcloud-system --dry-run=client -o yaml | kubectl apply -f -

# Deploy Hetzner Cloud Controller Manager
kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml

# Deploy Hetzner CSI Driver for persistent volumes
kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yml

echo "=== Bootstrap Complete ==="
