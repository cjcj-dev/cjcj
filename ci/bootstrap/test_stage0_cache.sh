#!/usr/bin/env bash
# Stage0 caches the host compiler only; std is produced by stage1.
set -euo pipefail
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# The override selects the real bootstrap product for fault-arm runs.
# shellcheck source=ci/bootstrap/bootstrap.sh
source "${BOOTSTRAP_PRODUCT:-$here/bootstrap.sh}"
set -euo pipefail
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
STAGE0_CACHE_ROOT="$scratch/cache"
cp /bin/true "$scratch/compiler"
mkdir "$scratch/restored"
stage0_cache_publish test-key "$scratch/compiler"
stage0_cache_restore test-key "$scratch/restored/cjcj-stage1"
cmp "$scratch/compiler" "$scratch/restored/cjcj-stage1"
"$scratch/restored/cjcj-stage1"
printf 'PASS cache roundtrip preserves executable bytes\n'
# A v1 cache carries the obsolete host-built main std payload. It must miss.
sed -i 's/stage0-cache-v2/stage0-cache-v1/' "$STAGE0_CACHE_ROOT/test-key/MANIFEST"
if stage0_cache_restore test-key "$scratch/restored/cjcj-stage1"; then
  echo 'FAIL obsolete std payload accepted'; exit 1
fi
printf 'PASS obsolete cache rejected\n'
sed -i 's/stage0-cache-v1/stage0-cache-v2/' "$STAGE0_CACHE_ROOT/test-key/MANIFEST"
printf 'changed\n' >> "$STAGE0_CACHE_ROOT/test-key/cjcj-stage1"
if stage0_cache_restore test-key "$scratch/restored/cjcj-stage1"; then
  echo 'FAIL corrupt compiler accepted'; exit 1
fi
cmp "$scratch/compiler" "$scratch/restored/cjcj-stage1"
printf 'PASS corrupt cache rejected before replacing compiler\n'
