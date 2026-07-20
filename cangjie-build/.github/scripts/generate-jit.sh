#!/usr/bin/env bash
# Ask GitHub for a just-in-time runner config (single-use, ~5-min validity).
# Prints the encoded_jit_config string to stdout — capture and feed it into
# the runner VM's cloud-init.
#
# Usage:
#   GH_TOKEN=<pat> generate-jit.sh <repo> <runner_name>
#
# The token must hold "Administration: Write" on the repo. GITHUB_TOKEN does
# NOT qualify — use a fine-grained PAT or GitHub App installation token.
set -euo pipefail

repo=${1:?repo (owner/name) required}
name=${2:?runner name required}
: "${GH_TOKEN:?GH_TOKEN required}"

gh api -X POST "/repos/${repo}/actions/runners/generate-jitconfig" \
	-f "name=${name}" \
	-F "runner_group_id=1" \
	-f "labels[]=self-hosted" \
	-f "labels[]=Linux" \
	-f "labels[]=X64" \
	-f "labels[]=${name}" \
	-f "work_folder=_work" \
	--jq .encoded_jit_config
