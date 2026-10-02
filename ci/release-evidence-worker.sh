#!/usr/bin/env bash
# Private Linux x64 worker prerequisite; no system or SDK installation.
# Source: https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
# Usage: bash ci/release-evidence-worker.sh PRIVATE_ROOT JQ_ENTITY [node test options/files...]
set -euo pipefail
ulimit -c 0
root=${1:?private worker root required}
entity=${2:?jq-linux-amd64 entity required}
shift 2
[[ "$root" = /* && "$root" != / && "$root" != /tmp && "$root" != /tmp/* ]] || {
  echo 'private worker root must be absolute and outside /tmp' >&2; exit 2;
}
expected=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5
printf '%s  %s\n' "$expected" "$entity" | sha256sum --check --status
mkdir -p "$root/bin" "$root/release-evidence-tests"
cp "$entity" "$root/bin/jq"
chmod 755 "$root/bin/jq"
printf '%s  %s\n' "$expected" "$root/bin/jq" | sha256sum --check
[[ $("$root/bin/jq" --version) = jq-1.7.1 ]]
export PATH="$root/bin:$PATH"
export RELEASE_EVIDENCE_TEST_ROOT="$root/release-evidence-tests"
echo "RELEASE_EVIDENCE_WORKER jq=$root/bin/jq version=$(jq --version) sha256=$expected"
if [[ $# = 0 ]]; then
  mapfile -t tests < <(node ci/test-manifest.mjs list)
  set -- "${tests[@]}"
fi
exec node --test "$@"
