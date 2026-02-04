#!/bin/bash
set -euo pipefail

# K3s Worker Node Bootstrap Script

echo "=== Installing K3s Agent ==="



# Wait for control plane to be ready
echo "Waiting for control plane at ${control_plane_ip}..."
until curl -sk https://${control_plane_ip}:6443/healthz >/dev/null; do
  sleep 10
  echo "Still waiting for control plane..."
done

# Install K3s agent
# We use the private network interface (enp7s0) for internal cluster traffic
curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://${control_plane_ip}:6443 \
  --token "${k3s_token}" \
  --node-label "${node_labels}" \
  --flannel-iface enp7s0 \
  --node-ip $(ip -4 addr show enp7s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')


echo "=== K3s Agent Installed ==="
