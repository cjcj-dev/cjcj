#!/usr/bin/env bash
# Delete labelled GCP runner VMs older than $MAX_AGE_HOURS (default 6h).
#
# gcp-provision-vm.sh labels every VM with app=cangjie-build and
# managed-by=github-actions, and writes created_at=<iso8601> metadata. This
# script lists matching VMs once, then deletes only stale entries.
#
# Usage:
#   MAX_AGE_HOURS=6 gcp-reap-orphans.sh
set -euo pipefail

MAX_AGE_HOURS=${MAX_AGE_HOURS:-6}
cutoff=$(date -u -d "${MAX_AGE_HOURS} hours ago" +%s)

gcloud compute instances list \
	--filter="labels.app=cangjie-build AND labels.managed-by=github-actions" \
	--format=json |
	jq -r '.[] | [.name, (.zone | split("/")[-1]), ([.metadata.items[]? | select(.key == "created_at") | .value][0] // "")] | @tsv' |
	while IFS=$'\t' read -r instance zone created_iso; do
		if [[ -z "$created_iso" ]]; then
			echo "skip $instance in $zone: no created_at metadata" >&2
			continue
		fi
		created_ts=$(date -d "$created_iso" +%s 2>/dev/null || echo 0)
		if ((created_ts > 0 && created_ts < cutoff)); then
			echo "deleting $instance in $zone (created at $created_iso)"
			gcloud compute instances delete "$instance" --zone="$zone" --quiet
		else
			echo "keep $instance in $zone (created at $created_iso)"
		fi
	done
