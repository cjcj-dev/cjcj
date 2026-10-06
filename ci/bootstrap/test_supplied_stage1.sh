#!/usr/bin/env bash
# Real-input contract checks; arguments are the same pinned bootstrap inputs used
# by the lane. No fake compiler, build.py or SDK executables are substituted.
set -euo pipefail
product=${BOOTSTRAP_PRODUCT:-$(dirname "$0")/bootstrap.sh}
checks=${BOOTSTRAP_CHECK_LOG_DIR:?set a private evidence directory}
mkdir -p "$checks"
set +e
bash "$product" --stage supplied-stage1 > "$checks/missing.log" 2>&1
missing=$?
env -u CANGJIE_HOME LD_LIBRARY_PATH=/mixed-domain bash "$product" "$@" --check-only > "$checks/mixed.log" 2>&1
mixed=$?
env -u LD_LIBRARY_PATH -u CANGJIE_HOME bash "$product" "$@" --check-only > "$checks/positive.log" 2>&1
positive=$?
set -e
printf 'missing=%s mixed=%s positive=%s\n' "$missing" "$mixed" "$positive" | tee "$checks/check.rc"
[[ "$missing" != 0 ]] && grep -q '缺少参数 WORK' "$checks/missing.log" || { echo 'ASSERT missing-required-parameter FAIL'; exit 1; }
echo 'ASSERT missing-required-parameter PASS'
[[ "$mixed" != 0 ]] && grep -q 'mixed domain: inherited LD_LIBRARY_PATH' "$checks/mixed.log" || { echo 'ASSERT mixed-domain-rejected FAIL'; exit 1; }
echo 'ASSERT mixed-domain-rejected PASS'
[[ "$positive" = 0 ]] && grep -q '^SUPPLIED-STAGE1-INPUTS-OK' "$checks/positive.log" || { echo 'ASSERT pinned-inputs-accepted FAIL'; exit 1; }
echo 'ASSERT pinned-inputs-accepted PASS'
