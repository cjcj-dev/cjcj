#!/usr/bin/env bash
# Create the ephemeral runner VM with multi-zone Spot-then-Regular fallback.
#
# Usage:
#   RG=<rg> REGION=<loc> SIZE=<sku> PRIORITY=Spot|Regular CLOUD_INIT=<path> \
#     provision-vm.sh
set -euo pipefail

: "${RG:?RG required}"
: "${REGION:?REGION required}"
: "${SIZE:?SIZE required}"
: "${PRIORITY:?PRIORITY required}"
: "${CLOUD_INIT:?CLOUD_INIT path required}"
ZONES=${ZONES:-"2 1 3"}

common=(
  --resource-group "$RG"
  --name runner
  --image Ubuntu2204
  --size "$SIZE"
  --admin-username azureuser
  --generate-ssh-keys
  --public-ip-address ""
  --nsg ""
  --custom-data "$CLOUD_INIT"
  --os-disk-caching ReadOnly
  -o none
)

try_create() {
  local label="$1"; shift
  echo "::group::az vm create attempt: $label"
  if az vm create "${common[@]}" "$@"; then
    echo "::endgroup::"
    return 0
  fi
  echo "::endgroup::"
  return 1
}

if [[ "$PRIORITY" == "Spot" ]]; then
  for zone in $ZONES; do
    if try_create "Spot zone=$zone" \
        --priority Spot --eviction-policy Delete --max-price -1 \
        --zone "$zone"; then
      exit 0
    fi
  done
  echo "Spot exhausted across zones $ZONES; falling back to Regular." >&2
fi

for zone in $ZONES; do
  if try_create "Regular zone=$zone" --zone "$zone"; then
    exit 0
  fi
done

echo "::error::Could not allocate $SIZE in $REGION across zones {$ZONES} on either Spot or Regular."
exit 1
