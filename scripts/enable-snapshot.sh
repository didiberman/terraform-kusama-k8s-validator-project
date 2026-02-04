#!/bin/bash
set -euo pipefail

# Enable snapshot restore for a validator
# Usage: ./enable-snapshot.sh <validator-name> [chain]

VALIDATOR_NAME=${1:-}
CHAIN=${2:-kusama}

if [ -z "$VALIDATOR_NAME" ]; then
  echo "Usage: $0 <validator-name> [chain]"
  echo ""
  echo "Arguments:"
  echo "  validator-name  Name of the validator (e.g., validator-001)"
  echo "  chain           Network: kusama, polkadot, westend (default: kusama)"
  echo ""
  echo "Example:"
  echo "  $0 validator-001 kusama"
  exit 1
fi

VALIDATORS_DIR="$(dirname "$0")/../validators"
VALIDATOR_FILE="$VALIDATORS_DIR/$VALIDATOR_NAME.yaml"

if [ ! -f "$VALIDATOR_FILE" ]; then
  echo "Error: Validator file not found: $VALIDATOR_FILE"
  exit 1
fi

# Determine snapshot URL based on chain
case "$CHAIN" in
  kusama)
    SNAPSHOT_URL="https://ksm-rocksdb.polkashots.io/snapshot"
    ;;
  polkadot)
    SNAPSHOT_URL="https://dot-rocksdb.polkashots.io/snapshot"
    ;;
  westend)
    SNAPSHOT_URL="https://wnd-rocksdb.polkashots.io/snapshot"
    ;;
  *)
    echo "Error: Unknown chain '$CHAIN'"
    echo "Supported chains: kusama, polkadot, westend"
    exit 1
    ;;
esac

echo "=== Enabling Snapshot Restore ==="
echo "Validator: $VALIDATOR_NAME"
echo "Chain: $CHAIN"
echo "Snapshot URL: $SNAPSHOT_URL"
echo ""

# Check if snapshot config already exists
if grep -q "snapshotEnabled:" "$VALIDATOR_FILE"; then
  echo "Snapshot configuration already exists in $VALIDATOR_FILE"
  echo "Updating snapshot URL..."
  
  # Update existing config
  sed -i.bak \
    -e "s|snapshotEnabled:.*|snapshotEnabled: true|" \
    -e "s|snapshotUrl:.*|snapshotUrl: \"$SNAPSHOT_URL\"|" \
    "$VALIDATOR_FILE"
else
  echo "Adding snapshot configuration to $VALIDATOR_FILE..."
  
  # Add snapshot config
  cat >> "$VALIDATOR_FILE" << EOF

# Snapshot restore (speeds up initial sync)
snapshotEnabled: true
snapshotUrl: "$SNAPSHOT_URL"
snapshotCompression: lz4
EOF
fi

rm -f "$VALIDATOR_FILE.bak"

echo ""
echo "✓ Snapshot restore enabled!"
echo ""
echo "Next steps:"
echo "1. Review the changes: cat $VALIDATOR_FILE"
echo "2. Commit and push:"
echo "   git add $VALIDATOR_FILE"
echo "   git commit -m 'Enable snapshot restore for $VALIDATOR_NAME'"
echo "   git push"
echo ""
echo "Note: Snapshot download will take 10-30 minutes on first deployment"
echo "      Subsequent restarts will skip the download if database exists"

