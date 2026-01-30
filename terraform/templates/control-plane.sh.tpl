#!/bin/bash
set -euo pipefail

# K3s Control Plane Bootstrap Script

echo "=== Installing K3s Control Plane ==="

# Wait for cloud-init
cloud-init status --wait

# Install K3s server
curl -sfL https://get.k3s.io | sh -s - server \
  --token "${k3s_token}" \
  --cluster-init \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --node-name "${cluster_name}-control-plane" \
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
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

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
kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml

echo "=== Bootstrap Complete ==="
