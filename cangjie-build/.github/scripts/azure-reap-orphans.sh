#!/usr/bin/env bash
# Delete cangjie-* resource groups older than $MAX_AGE_HOURS (default 6h).
#
# Each cangjie-* RG is tagged at creation time with createdAt=<iso8601> by
# azure-provision-vm.sh, so the entire eligibility check is a single az group list
# call — no per-RG az group show.
#
# Usage:
#   MAX_AGE_HOURS=6 azure-reap-orphans.sh
set -euo pipefail

MAX_AGE_HOURS=${MAX_AGE_HOURS:-6}
cutoff=$(date -u -d "${MAX_AGE_HOURS} hours ago" +%s)

az group list \
	--query "[?starts_with(name, 'cangjie-')].{name:name, createdAt:tags.createdAt}" \
	-o json |
	jq -r '.[] | "\(.name)\t\(.createdAt // "")"' |
	while IFS=$'\t' read -r rg created_iso; do
		if [[ -z "$created_iso" ]]; then
			echo "skip $rg: no createdAt tag" >&2
			continue
		fi
		created_ts=$(date -d "$created_iso" +%s 2>/dev/null || echo 0)
		if ((created_ts > 0 && created_ts < cutoff)); then
			echo "deleting $rg (created at $created_iso)"
			az group delete -n "$rg" --yes --no-wait
		else
			echo "keep $rg (created at $created_iso)"
		fi
	done
