#!/usr/bin/env bash
# Tear down a single ephemeral runner: delete its Azure resource group and
# force-deregister the runner in case the VM never finished its job.
#
# Usage:
#   GH_TOKEN=<pat> azure-teardown.sh <repo> <runner_name> <resource_group>
set -euo pipefail

repo=${1:?repo required}
name=${2:?runner name required}
rg=${3:?resource group required}
: "${GH_TOKEN:?GH_TOKEN required}"

if az group show -n "$rg" -o none 2>/dev/null; then
	az group delete -n "$rg" --yes --no-wait
	echo "Resource group $rg delete dispatched."
else
	echo "Resource group $rg already gone."
fi

id=$(gh api "/repos/${repo}/actions/runners" \
	--jq "[.runners[] | select(.name == \"${name}\")][0].id // empty")
if [[ -n "$id" ]]; then
	echo "Force-deleting runner registration $id"
	gh api -X DELETE "/repos/${repo}/actions/runners/${id}"
else
	echo "Runner $name already deregistered."
fi
