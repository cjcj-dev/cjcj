#!/usr/bin/env bash
# Create the ephemeral runner VM, walking a region × zone × priority matrix
# until one combination accepts the allocation.
#
# Usage:
#   RG=<rg> REGIONS="westus2 eastus2 …" SIZE=<sku> \
#   PRIORITY=Spot|Regular CLOUD_INIT=<path> \
#     provision-vm.sh
#
# REGIONS is a space-separated ordered list; the first one with capacity wins.
# A single resource group ($RG) is created in the first region of the list and
# holds whichever VM eventually lands — Azure resource groups can host
# resources from any region, so we don't pay for create/delete round-trips on
# capacity misses. The chosen region/zone/priority are echoed in `key=value`
# form on stdout for the caller to reuse.
set -euo pipefail

: "${RG:?RG required}"
: "${REGIONS:?REGIONS required}"
: "${SIZE:?SIZE required}"
: "${PRIORITY:?PRIORITY required}"
: "${CLOUD_INIT:?CLOUD_INIT path required}"
ZONES=${ZONES:-"2 1 3"}

read -ra region_arr <<< "$REGIONS"
home_region="${region_arr[0]}"

# Tag the RG so reap-orphans.sh can find stale ones cheaply via az group list.
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
az group create -n "$RG" -l "$home_region" --tags "createdAt=$created_at" -o none

base_args=(
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
  # Default Ubuntu image is ~30 GB; LLVM build needs >40 GB of intermediates,
  # plus sccache + toolchain cache + workspace. F16als_v6 has no temp volume
  # (MaxResourceVolumeMB=0), so everything lives on the OS disk.
  --os-disk-size-gb 256
  -o none
)

try_create() {
  local label="$1"; shift
  echo "::group::az vm create attempt: $label" >&2
  if az vm create "$@"; then
    echo "::endgroup::" >&2
    return 0
  fi
  echo "::endgroup::" >&2
  return 1
}

attempt_priority() {
  local priority="$1"
  local extra=()
  if [[ "$priority" == "Spot" ]]; then
    extra=(--priority Spot --eviction-policy Delete --max-price -1)
  fi
  for region in "${region_arr[@]}"; do
    for zone in $ZONES; do
      if try_create "$priority $region zone=$zone" \
          --location "$region" --zone "$zone" \
          "${extra[@]}" "${base_args[@]}"; then
        printf 'region=%s\nzone=%s\npriority=%s\n' "$region" "$zone" "$priority"
        return 0
      fi
    done
  done
  return 1
}

# Spot path stays opt-in via PRIORITY=Spot but defaults to Regular: this
# repo's Azure subscription is MSDN/Visual Studio Enterprise (quotaId
# MSDN_2014-09-01), and that offer family isn't on Azure's spot-supported
# list (https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms —
# only EA, PAYG 003P, Sponsored, CSP). 45/45 spot-create probes returned
# SkuNotAvailable across 4 SKUs and many region/zone combos, so the Spot
# loop was just burning ~50s per build before falling back. EA/PAYG users
# can flip vm_priority back to Spot and the loop fires.
if [[ "$PRIORITY" == "Spot" ]]; then
  if attempt_priority Spot; then exit 0; fi
  echo "Spot exhausted across REGIONS={$REGIONS}; falling back to Regular." >&2
fi
if attempt_priority Regular; then exit 0; fi

az group delete -n "$RG" --yes --no-wait >/dev/null 2>&1 || true
# Send GitHub log directives to stderr so they don't end up in
# GITHUB_OUTPUT when the caller pipes stdout via `tee -a "$GITHUB_OUTPUT"`.
echo "::error::Could not allocate $SIZE across regions {$REGIONS} × zones {$ZONES} × {Spot,Regular}." >&2
exit 1
