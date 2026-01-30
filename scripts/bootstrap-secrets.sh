#!/bin/bash
set -e

# Bootstrap Secrets for Kusama Validator Platform
# Usage: ./bootstrap-secrets.sh <hcloud-token> <grafana-password>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <hcloud-token> <grafana-password>"
    exit 1
fi

HCLOUD_TOKEN=$1
GRAFANA_PASSWORD=$2

echo "=== Bootstrapping Secrets ==="

# 1. Hetzner Cloud Token (for Autoscaler & CCM)
echo "Creating 'hetzner-cloud' secret in kube-system..."
kubectl create secret generic hetzner-cloud \
  --namespace kube-system \
  --from-literal=token="$HCLOUD_TOKEN" \
  --from-literal=network="kusama-validators-network" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Grafana Admin Password
echo "Creating 'grafana-admin' secret in monitoring..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic grafana-admin \
  --namespace monitoring \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Secrets Created Successfully ==="
echo "Note: For production, consider using Sealed Secrets to manage these in Git."
