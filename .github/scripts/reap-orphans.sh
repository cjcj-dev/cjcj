#!/usr/bin/env bash
# Delete cangjie-* resource groups older than $MAX_AGE_HOURS (default 6h).
# Tag-free: relies on the RG's createdTime metadata, no extra setup.
#
# Usage:
#   MAX_AGE_HOURS=6 reap-orphans.sh
set -euo pipefail

MAX_AGE_HOURS=${MAX_AGE_HOURS:-6}
cutoff=$(date -u -d "${MAX_AGE_HOURS} hours ago" +%s)

az group list --query "[?starts_with(name, 'cangjie-')].{name:name, t:tags.\"createdAt\"}" -o json \
  | jq -r '.[] | .name' \
  | while read -r rg; do
      created_iso=$(az group show -n "$rg" --query "tags.createdAt // properties.provisioningState" -o tsv 2>/dev/null || echo "")
      # Fallback to deployment timestamp when no createdAt tag is present.
      if [[ -z "$created_iso" || "$created_iso" == "Succeeded" || "$created_iso" == "Failed" ]]; then
        created_iso=$(az deployment group list -g "$rg" --query "[0].properties.timestamp" -o tsv 2>/dev/null || true)
      fi
      if [[ -z "$created_iso" ]]; then
        echo "skip $rg: cannot determine age" >&2
        continue
      fi
      created_ts=$(date -d "$created_iso" +%s 2>/dev/null || echo 0)
      if (( created_ts > 0 && created_ts < cutoff )); then
        echo "deleting $rg (created at $created_iso)"
        az group delete -n "$rg" --yes --no-wait
      else
        echo "keep $rg (created at $created_iso)"
      fi
    done
