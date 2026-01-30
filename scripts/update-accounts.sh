#!/bin/bash
set -euo pipefail

# Update validator configs from a CSV file
# Usage: ./update-accounts.sh <csv-file>
#
# CSV Format (no header):
#   validator-001,5GrwvaEF...,5FHneW46...
#   validator-002,5DAAnrj7...,5HGjWAeF...
#
# Columns: validator-name, stash-account, controller-account

CSV_FILE=${1:-}

if [ -z "$CSV_FILE" ] || [ ! -f "$CSV_FILE" ]; then
  echo "Usage: $0 <csv-file>"
  echo ""
  echo "CSV format (no header):"
  echo "  validator-name,stash-account,controller-account"
  echo ""
  echo "Example CSV:"
  echo "  validator-001,5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY,5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty"
  echo "  validator-002,5DAAnrj7VUnZRBl8dJRjezmRFmbBEkqRieEHn2Wqsiu3t1hg,5HGjWAeFDfFCWPsjFQdVV2Msvz2XtMktvgocEZcCj68kUMaw"
  exit 1
fi

VALIDATORS_DIR="$(dirname "$0")/../validators"
UPDATED=0
ERRORS=0

echo "=== Updating validators from $CSV_FILE ==="
echo ""

while IFS=',' read -r NAME STASH CONTROLLER; do
  # Skip empty lines
  [ -z "$NAME" ] && continue
  
  OUTPUT_FILE="$VALIDATORS_DIR/$NAME.yaml"
  
  if [ ! -f "$OUTPUT_FILE" ]; then
    echo "ERROR: $NAME - file not found, run batch-generate-validators.sh first"
    ((ERRORS++))
    continue
  fi
  
  # Update the YAML file
  sed -i.bak \
    -e "s|stashAccount:.*|stashAccount: \"$STASH\"|" \
    -e "s|controllerAccount:.*|controllerAccount: \"$CONTROLLER\"|" \
    "$OUTPUT_FILE"
  
  rm -f "$OUTPUT_FILE.bak"
  
  echo "UPDATED: $NAME"
  ((UPDATED++))
  
done < "$CSV_FILE"

echo ""
echo "=== Summary ==="
echo "Updated: $UPDATED"
echo "Errors: $ERRORS"
