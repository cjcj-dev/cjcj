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

# Note: `-o` is not a gcloud flag (it was previously used here as `-o none`,
# which made describe exit non-zero with "unrecognized arguments" — the if
# branch then silently skipped the delete and reported "already gone" while
# the VM was still up, leaking SSD_TOTAL_GB quota until manual cleanup).
# Suppress chatter via redirection on describe and `--quiet` on delete.
if gcloud compute instances describe "$instance" --zone="$zone" >/dev/null 2>&1; then
	gcloud compute instances delete "$instance" --zone="$zone" --quiet
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
