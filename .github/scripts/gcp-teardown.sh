#!/usr/bin/env bash
# Tear down one ephemeral GCP runner VM and force-deregister the GitHub runner.
#
# Usage:
#   GH_TOKEN=<pat> gcp-teardown.sh <repo> <runner_name> <instance_name> <zone>
set -euo pipefail

repo=${1:?repo required}
name=${2:?runner name required}
instance=${3:?instance name required}
zone=${4:?zone required}
: "${GH_TOKEN:?GH_TOKEN required}"

if gcloud compute instances describe "$instance" --zone="$zone" -o none 2>/dev/null; then
	gcloud compute instances delete "$instance" --zone="$zone" --quiet -o none
	echo "GCP instance $instance in $zone deleted."
else
	echo "GCP instance $instance in $zone already gone."
fi

id=$(gh api "/repos/${repo}/actions/runners" \
	--jq "[.runners[] | select(.name == \"${name}\")][0].id // empty")
if [[ -n "$id" ]]; then
	echo "Force-deleting runner registration $id"
	gh api -X DELETE "/repos/${repo}/actions/runners/${id}"
else
	echo "Runner $name already deregistered."
fi
