#!/usr/bin/env bash
# Poll until the named self-hosted runner reports "online", or fail after a
# deadline.
#
# Usage:
#   GH_TOKEN=<pat> wait-for-runner.sh <repo> <runner_name> [timeout_seconds]
set -euo pipefail

repo=${1:?repo required}
name=${2:?runner name required}
timeout=${3:-600}
: "${GH_TOKEN:?GH_TOKEN required}"

deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
  online=$(gh api "/repos/${repo}/actions/runners" \
    --jq "[.runners[] | select(.name == \"${name}\" and .status == \"online\")] | length")
  if [[ "$online" -ge 1 ]]; then
    echo "Runner $name is online."
    exit 0
  fi
  sleep 15
done

echo "::error::Runner $name did not come online within ${timeout}s."
exit 1
