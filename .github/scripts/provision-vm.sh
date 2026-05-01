#!/usr/bin/env bash
# Create the ephemeral runner VM, walking a region × zone × priority matrix
# until one combination accepts the allocation.
#
# Usage:
#   RG_PREFIX=<prefix> REGIONS="westus2 eastus2 …" SIZE=<sku> \
#   PRIORITY=Spot|Regular CLOUD_INIT=<path> \
#     provision-vm.sh
#
# REGIONS is a space-separated ordered list; the first one with capacity wins.
# The resource group is named "$RG_PREFIX-$region" and created on demand. The
# script prints the chosen region+zone+RG to stdout in `key=value` form so the
# caller (a GitHub Actions step) can append it to $GITHUB_OUTPUT and reuse the
# values for cleanup.
set -euo pipefail

: "${RG_PREFIX:?RG_PREFIX required}"
: "${REGIONS:?REGIONS required}"
: "${SIZE:?SIZE required}"
: "${PRIORITY:?PRIORITY required}"
: "${CLOUD_INIT:?CLOUD_INIT path required}"
ZONES=${ZONES:-"2 1 3"}

base_args=(
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

ensure_rg() {
  local region="$1" rg="$2"
  if ! az group show -n "$rg" -o none 2>/dev/null; then
    az group create -n "$rg" -l "$region" -o none
  fi
}

try_create() {
  local label="$1"; shift
  echo "::group::az vm create attempt: $label"
  if az vm create "$@"; then
    echo "::endgroup::"
    return 0
  fi
  echo "::endgroup::"
  return 1
}

emit_outcome() {
  local region="$1" zone="$2" priority="$3" rg="$4"
  echo "region=$region"
  echo "zone=$zone"
  echo "priority=$priority"
  echo "rg=$rg"
}

attempt_priority() {
  # $1 = Spot|Regular ; iterates regions × zones, returns 0 on first success.
  local priority="$1"
  for region in $REGIONS; do
    local rg="${RG_PREFIX}-${region}"
    ensure_rg "$region" "$rg"
    local extra=()
    if [[ "$priority" == "Spot" ]]; then
      extra=(--priority Spot --eviction-policy Delete --max-price -1)
    fi
    for zone in $ZONES; do
      if try_create "$priority $region zone=$zone" \
          --resource-group "$rg" --zone "$zone" \
          "${extra[@]}" "${base_args[@]}"; then
        emit_outcome "$region" "$zone" "$priority" "$rg"
        return 0
      fi
    done
    # Region didn't yield this priority; tear the empty RG down so we don't
    # leave a litter of empty RGs behind.
    az group delete -n "$rg" --yes --no-wait >/dev/null 2>&1 || true
  done
  return 1
}

if [[ "$PRIORITY" == "Spot" ]]; then
  if attempt_priority Spot; then exit 0; fi
  echo "Spot exhausted across REGIONS={$REGIONS}; falling back to Regular." >&2
fi
if attempt_priority Regular; then exit 0; fi

echo "::error::Could not allocate $SIZE across regions {$REGIONS} × zones {$ZONES} × {Spot,Regular}."
exit 1
