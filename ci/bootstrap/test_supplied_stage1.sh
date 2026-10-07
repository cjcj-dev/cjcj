#!/usr/bin/env bash
# Real-input contract checks; arguments are the same pinned bootstrap inputs used
# by the lane. No fake compiler, build.py or SDK executables are substituted.
set -euo pipefail
product=${BOOTSTRAP_PRODUCT:-$(dirname "$0")/bootstrap.sh}
checks=${BOOTSTRAP_CHECK_LOG_DIR:?set a private evidence directory}
mkdir -p "$checks"
args_without_stage1=()
while_args=("$@")
while [ "${#while_args[@]}" -gt 0 ]; do
  if [ "${while_args[0]}" = --stage1-elf ]; then
    while_args=("${while_args[@]:2}")
  else
    args_without_stage1+=("${while_args[0]}")
    while_args=("${while_args[@]:1}")
  fi
done
set +e
env -u LD_LIBRARY_PATH -u CANGJIE_HOME bash "$product" "${args_without_stage1[@]}" --check-only > "$checks/missing-stage1.log" 2>&1
missing_stage1=$?
bash "$product" --stage supplied-stage1 > "$checks/missing.log" 2>&1
missing=$?
env -u CANGJIE_HOME LD_LIBRARY_PATH=/mixed-domain bash "$product" "$@" --check-only > "$checks/mixed.log" 2>&1
mixed=$?
env -u LD_LIBRARY_PATH -u CANGJIE_HOME bash "$product" "$@" --check-only > "$checks/positive.log" 2>&1
positive=$?
set -e
printf 'missing=%s missing_stage1=%s mixed=%s positive=%s\n' "$missing" "$missing_stage1" "$mixed" "$positive" | tee "$checks/check.rc"
if [[ "$missing" = 0 ]] || ! grep -q '缺少参数 WORK' "$checks/missing.log"; then
  echo 'ASSERT missing-required-parameter FAIL'
  exit 1
fi
echo 'ASSERT missing-required-parameter PASS'
if [[ "$missing_stage1" = 0 ]] || ! grep -q '缺少参数 STAGE1_ELF' "$checks/missing-stage1.log"; then
  echo 'ASSERT missing-stage1-pin FAIL'
  exit 1
fi
echo 'ASSERT missing-stage1-pin PASS'
if [[ "$mixed" = 0 ]] || ! grep -q 'mixed domain: inherited LD_LIBRARY_PATH' "$checks/mixed.log"; then
  echo 'ASSERT mixed-domain-rejected FAIL'
  exit 1
fi
echo 'ASSERT mixed-domain-rejected PASS'
if [[ "$positive" != 0 ]] || ! grep -q '^SUPPLIED-STAGE1-INPUTS-OK' "$checks/positive.log"; then
  echo 'ASSERT pinned-inputs-accepted FAIL'
  exit 1
fi
echo 'ASSERT pinned-inputs-accepted PASS'
