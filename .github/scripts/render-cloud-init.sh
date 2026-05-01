#!/usr/bin/env bash
# Render the cloud-init template for the ephemeral runner VM.
#
# Usage:
#   JIT=<encoded_jit_config> RUNNER_VERSION=2.334.0 \
#     render-cloud-init.sh <template> <output>
#
# JIT comes from POST /repos/.../actions/runners/generate-jitconfig and is a
# base64 string (only [A-Za-z0-9+/=]) so it's safe to drop into sed s/// with
# `|` as the separator.
set -euo pipefail

template=${1:?template path required}
output=${2:?output path required}
: "${JIT:?JIT env var required}"
: "${RUNNER_VERSION:?RUNNER_VERSION env var required}"

cp "$template" "$output"
sed -i "s|__JIT__|${JIT}|" "$output"
sed -i "s|__RUNNER_VERSION__|${RUNNER_VERSION}|g" "$output"
