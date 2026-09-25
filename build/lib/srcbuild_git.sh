#!/usr/bin/env bash

# Shared mirror and transport policy for source-build shell entry points.

srcbuild_git_resolve_source_mirror() {
    local original=$1 mappings=${CJCJ_SRCBUILD_SOURCE_MIRRORS:-} entry source mirror resolved=$1 matched=0
    local -a seen=()
    local seen_count=0 seen_index=0 duplicate=0 rest=$mappings
    while [[ -n $rest ]]; do
        entry=${rest%%;*}
        if [[ $rest == *";"* ]]; then
            rest=${rest#*;}
        else
            rest=
        fi
        [[ -n $entry ]] || continue
        [[ $entry == *=* && -n ${entry%%=*} && -n ${entry#*=} ]] || {
            echo "invalid CJCJ_SRCBUILD_SOURCE_MIRRORS entry: $entry" >&2
            return 1
        }
        source=${entry%%=*}
        mirror=${entry#*=}
        seen_index=0
        duplicate=0
        while ((seen_index < seen_count)); do
            if [ "x${seen[$seen_index]}" = "x$source" ]; then
                duplicate=1
            fi
            seen_index=$((seen_index + 1))
        done
        [[ $duplicate == 0 ]] || {
            echo "duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source: $source" >&2
            return 1
        }
        seen[$seen_count]=$source
        seen_count=$((seen_count + 1))
        if [[ $source == "$original" ]]; then
            resolved=$mirror
            matched=1
        fi
    done
    if ((matched == 0)); then
        echo "SOURCE-MIRROR none, falling back to $original" >&2
        [[ ${CJCJ_SRCBUILD_REQUIRE_MIRRORS:-0} != 1 ]] || {
            echo "source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1: $original" >&2
            return 1
        }
    fi
    printf '%s\n' "$resolved"
}

srcbuild_git_fetch() {
    local directory=$1 url=$2 revision=$3 depth=${4:-1} fetch_url
    fetch_url=$(srcbuild_git_resolve_source_mirror "$url") || return 1
    git -C "$directory" -c http.version=HTTP/1.1 \
        fetch --depth="$depth" "$fetch_url" "$revision"
}
