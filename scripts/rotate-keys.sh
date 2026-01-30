#!/bin/bash
set -euo pipefail

# Rotate session keys for a validator
# Usage: ./rotate-keys.sh <validator-name>

VALIDATOR_NAME=${1:-}

if [ -z "$VALIDATOR_NAME" ]; then
  echo "Usage: $0 <validator-name>"
  echo "Example: $0 validator-001"
  exit 1
fi

echo "=== Rotating Session Keys for $VALIDATOR_NAME ==="

# Get pod name
POD_NAME=$(kubectl get pods -n validators -l app.kubernetes.io/instance=$VALIDATOR_NAME -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
  echo "Error: No pod found for validator $VALIDATOR_NAME"
  exit 1
fi

echo "Pod: $POD_NAME"

# Check if synced
echo "Checking sync status..."
SYNC_STATUS=$(kubectl exec -n validators $POD_NAME -- curl -s -H "Content-Type: application/json" \
  -d '{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}' \
  http://localhost:9933/ | jq -r '.result.isSyncing')

if [ "$SYNC_STATUS" == "true" ]; then
  echo "WARNING: Node is still syncing. Wait for sync to complete before rotating keys."
  echo "You can check status with: kubectl exec -n validators $POD_NAME -- curl -s http://localhost:9933/health"
  exit 1
fi

# Rotate keys
echo "Calling author_rotateKeys..."
RESPONSE=$(kubectl exec -n validators $POD_NAME -- curl -s -H "Content-Type: application/json" \
  -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' \
  http://localhost:9933/)

KEYS=$(echo $RESPONSE | jq -r '.result')

if [ "$KEYS" == "null" ] || [ -z "$KEYS" ]; then
  echo "ERROR: Failed to rotate keys"
  echo "Response: $RESPONSE"
  exit 1
fi

echo ""
echo "=========================================="
echo "Session Keys Generated Successfully!"
echo "=========================================="
echo ""
echo "Keys: $KEYS"
echo ""
echo "NEXT STEPS:"
echo "1. Go to https://polkadot.js.org/apps/?rpc=wss://kusama-rpc.polkadot.io"
echo "2. Navigate to Developer > Extrinsics"
echo "3. Select your CONTROLLER account"
echo "4. Call session.setKeys(keys, proof)"
echo "   - keys: $KEYS"
echo "   - proof: 0x"
echo "5. Submit and sign the transaction"
echo ""
echo "=========================================="
