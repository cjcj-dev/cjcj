#!/usr/bin/env bash
# Fetch the immutable Linux x64 shim produced alongside the fixed llc and
# reject any artifact drift before it reaches the cjcj link.
set -euo pipefail

ARTIFACT_REPOSITORY="${SHIM_ARTIFACT_REPOSITORY:-cjcj-dev/cjcj}"
ARTIFACT_RUN="${SHIM_ARTIFACT_RUN:-29840652402}"
ARTIFACT_NAME="${SHIM_ARTIFACT_NAME:-fixed-llvm-tools-linux_x86_64}"
EXPECTED_SIZE="${SHIM_EXPECTED_SIZE:-207776}"
EXPECTED_SHA256="${SHIM_EXPECTED_SHA256:-bb05dfd1fa584aa8456356064c3dd392c3588a13708327a6f899d9a09ec4fd47}"
DESTINATION="${SHIM_DESTINATION:-runtime_shim/cjselfhost_llvmshim.o}"
SCRATCH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/platform-ci-linux-x64-shim"

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64|Linux/amd64) ;;
    *)
        echo "ERROR: Linux x64 shim injection requested on $(uname -s)/$(uname -m)" >&2
        exit 2
        ;;
esac
command -v gh >/dev/null || { echo 'ERROR: gh is required to download the shim artifact' >&2; exit 3; }
command -v unzip >/dev/null || { echo 'ERROR: unzip is required to unpack the shim artifact' >&2; exit 3; }

mkdir -p "$SCRATCH"
artifact_id="$(gh api \
    "/repos/$ARTIFACT_REPOSITORY/actions/runs/$ARTIFACT_RUN/artifacts" \
    --jq ".artifacts[] | select(.name == \"$ARTIFACT_NAME\" and .expired == false) | .id" \
    | head -n 1)"
if [ -z "$artifact_id" ]; then
    echo "ERROR: active artifact $ARTIFACT_NAME not found on run $ARTIFACT_RUN" >&2
    exit 4
fi

archive="$SCRATCH/artifact.zip"
candidate="$SCRATCH/cjselfhost_llvmshim.o"
gh api "/repos/$ARTIFACT_REPOSITORY/actions/artifacts/$artifact_id/zip" > "$archive"
entry="$(unzip -Z1 "$archive" | grep -E '(^|/)cjselfhost_llvmshim\.o$' | head -n 1)"
if [ -z "$entry" ]; then
    echo "ERROR: cjselfhost_llvmshim.o missing from artifact $artifact_id" >&2
    exit 5
fi
unzip -p "$archive" "$entry" > "$candidate"

actual_size="$(wc -c < "$candidate" | tr -d '[:space:]')"
actual_sha256="$(sha256sum "$candidate" | awk '{print $1}')"
printf 'shim_artifact_id=%s\nshim_size=%s\nshim_sha256=%s\n' \
    "$artifact_id" "$actual_size" "$actual_sha256"
if [ "$actual_size" != "$EXPECTED_SIZE" ] || [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
    echo "ERROR: shim integrity mismatch; expected $EXPECTED_SIZE bytes/$EXPECTED_SHA256" >&2
    exit 6
fi
file "$candidate" | grep -Eq 'ELF 64-bit.*(x86-64|x86_64)' || {
    echo 'ERROR: downloaded shim is not an ELF x86-64 relocatable object' >&2
    exit 7
}
mkdir -p "$(dirname "$DESTINATION")"
cp "$candidate" "$DESTINATION"
echo "injected verified Linux x64 shim: $DESTINATION"
