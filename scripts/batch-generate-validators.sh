#!/bin/bash
set -euo pipefail

# Generate multiple validator configuration files at once
# Usage: ./batch-generate-validators.sh <count> [start-number] [chain]
#
# Examples:
#   ./batch-generate-validators.sh 20           # Creates validator-001 to validator-020
#   ./batch-generate-validators.sh 10 5         # Creates validator-005 to validator-014
#   ./batch-generate-validators.sh 5 1 kusama   # Creates 5 validators for Kusama mainnet

COUNT=${1:-}
START=${2:-1}
CHAIN=${3:-westend}

if [ -z "$COUNT" ]; then
  echo "Usage: $0 <count> [start-number] [chain]"
  echo ""
  echo "Arguments:"
  echo "  count        Number of validators to create"
  echo "  start-number Starting number (default: 1)"
  echo "  chain        Network: westend, kusama, polkadot (default: westend)"
  echo ""
  echo "Examples:"
  echo "  $0 20              # Create validator-001 to validator-020 (westend)"
  echo "  $0 10 5            # Create validator-005 to validator-014"
  echo "  $0 5 1 kusama      # Create 5 validators for Kusama"
  exit 1
fi

VALIDATORS_DIR="$(dirname "$0")/../validators"
CREATED=0
SKIPPED=0

echo "=== Generating $COUNT validators starting from $(printf '%03d' $START) ==="
echo "Chain: $CHAIN"
echo ""

for i in $(seq $START $((START + COUNT - 1))); do
  VALIDATOR_NAME="validator-$(printf '%03d' $i)"
  OUTPUT_FILE="$VALIDATORS_DIR/$VALIDATOR_NAME.yaml"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "SKIP: $VALIDATOR_NAME (already exists)"
    ((SKIPPED++))
    continue
  fi

  cat > "$OUTPUT_FILE" << EOF
# Validator: $VALIDATOR_NAME
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

name: $VALIDATOR_NAME

# TODO: Replace with your actual accounts
# Generate with: subkey generate --scheme sr25519
stashAccount: "STASH_ACCOUNT_FOR_$VALIDATOR_NAME"
controllerAccount: "CONTROLLER_ACCOUNT_FOR_$VALIDATOR_NAME"

# Network
chain: $CHAIN

# Storage size
storageSize: "$( [ "$CHAIN" == "westend" ] && echo "100Gi" || echo "500Gi" )"
EOF

  echo "CREATED: $VALIDATOR_NAME"
  ((CREATED++))
done

echo ""
echo "=== Summary ==="
echo "Created: $CREATED"
echo "Skipped: $SKIPPED"
echo ""

if [ $CREATED -gt 0 ]; then
  echo "Next steps:"
  echo "1. Edit each validator file with actual stash/controller accounts"
  echo "   Or use: ./update-accounts.sh to batch update from a CSV"
  echo ""
  echo "2. Commit and push:"
  echo "   git add validators/"
  echo "   git commit -m 'Add $CREATED validators'"
  echo "   git push"
  echo ""
  echo "3. ArgoCD will automatically deploy all validators!"
fi
