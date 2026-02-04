#!/bin/bash
set -euo pipefail

# Generate a new validator configuration file
# Usage: ./generate-validator.sh <validator-name>

VALIDATOR_NAME=${1:-}

if [ -z "$VALIDATOR_NAME" ]; then
  echo "Usage: $0 <validator-name>"
  echo "Example: $0 validator-001"
  exit 1
fi

VALIDATORS_DIR="$(dirname "$0")/../validators"
OUTPUT_FILE="$VALIDATORS_DIR/$VALIDATOR_NAME.yaml"

if [ -f "$OUTPUT_FILE" ]; then
  echo "Error: $OUTPUT_FILE already exists"
  exit 1
fi

cat > "$OUTPUT_FILE" << EOF
# Validator: $VALIDATOR_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

name: $VALIDATOR_NAME

# TODO: Replace with your actual Kusama accounts
stashAccount: "YOUR_STASH_ACCOUNT"
controllerAccount: "YOUR_CONTROLLER_ACCOUNT"

# Network (start with westend for testing)
chain: westend

# Storage size
storageSize: "100Gi"

# Snapshot restore (optional - speeds up initial sync)
# Uncomment to enable fast startup:
# snapshotEnabled: true
# snapshotUrl: "https://wnd-rocksdb.polkashots.io/snapshot"
# snapshotCompression: lz4
EOF

echo "Created: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Edit $OUTPUT_FILE with your stash/controller accounts"
echo "2. git add $OUTPUT_FILE"
echo "3. git commit -m 'Add $VALIDATOR_NAME'"
echo "4. git push"
echo ""
echo "ArgoCD will automatically deploy the validator!"
