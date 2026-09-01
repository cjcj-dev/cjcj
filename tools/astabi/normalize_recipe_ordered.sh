#!/usr/bin/env bash
set -euo pipefail

# Emit a recipe manifest without canonicalising the flag stream.  Flag order is
# semantic for repeated -D/-O options and for linker search order, so each item
# is numbered in the order in which it appears in the manifest.
manifest=$1
out=$2

value() {
    local key=$1
    local count
    count=$(/usr/bin/grep -c "^${key}=" "$manifest")
    test "$count" -eq 1
    /usr/bin/grep "^${key}=" "$manifest" | cut -d= -f2-
}

source_path=$(value source)
compiler_path=$(value compiler)
compiler_version=$(value compiler_version)
flags=$(value flags)
archive_path=$(value archive)

{
    printf 'source_sha=%s\n' "$(sha256sum "$source_path" | cut -d' ' -f1)"
    printf 'compiler_sha=%s\n' "$(sha256sum "$compiler_path" | cut -d' ' -f1)"
    printf 'compiler_version=%s\n' "$compiler_version"
    idx=0
    # Deliberately use shell word splitting: the manifest's flags field is a
    # command-line token stream.  No sort/uniq is allowed here.
    read -r -a flag_array <<< "$flags"
    for flag in "${flag_array[@]}"; do
        printf 'flag[%03d]=%s\n' "$idx" "$flag"
        idx=$((idx + 1))
    done
    input_idx=0
    while IFS= read -r input_path; do
        test -f "$input_path"
        printf 'input[%03d]=%s:%s\n' "$input_idx" "$(sha256sum "$input_path" | cut -d' ' -f1)" "$(basename "$input_path")"
        input_idx=$((input_idx + 1))
    done < <(/usr/bin/grep '^input_cj=' "$manifest" | cut -d= -f2-)
    printf 'archive_sha=%s\n' "$(sha256sum "$archive_path" | cut -d' ' -f1)"
} > "$out"
