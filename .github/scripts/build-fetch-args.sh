#!/usr/bin/env bash
# Translate four per-repo "source" inputs into the --repo-url / --repo-tag
# argv that `cangjie-build fetch` expects.
#
# Each source input is a string of the form:
#   https://host/owner/repo.git:branch (full URL — the expected form)
#   https://host/owner/repo.git        (no branch — falls through to the global --tag)
#   host/owner/repo.git[:branch]       (scheme-less — "https://" prepended as fallback)
#   <empty>                            (no override — use the upstream default)
#
# Usage:
#   COMPILER_SOURCE=... RUNTIME_SOURCE=... TOOLS_SOURCE=... STDX_SOURCE=... \
#     build-fetch-args.sh
#
# Prints the argv tokens, one per line, on stdout. The caller is expected to
# read them into a bash array, e.g.
#
#   mapfile -t fetch_args < <(.github/scripts/build-fetch-args.sh)
#   uv run cangjie-build fetch "${fetch_args[@]}"
set -euo pipefail

emit() {
  local name="$1" raw="$2"
  raw="${raw#"${raw%%[![:space:]]*}"}"   # trim leading whitespace
  raw="${raw%"${raw##*[![:space:]]}"}"   # trim trailing whitespace
  [[ -z "$raw" ]] && return 0

  local url_part branch=""
  # Treat the last `:` as the URL/branch separator only when what follows is
  # branch-like (no slashes). Otherwise the colon belongs to the scheme.
  if [[ "$raw" =~ ^(.+):([^/[:space:]]+)$ ]]; then
    url_part="${BASH_REMATCH[1]}"
    branch="${BASH_REMATCH[2]}"
  else
    url_part="$raw"
  fi

  case "$url_part" in
    http://*|https://*|git://*|ssh://*) ;;
    *)  url_part="https://$url_part" ;;
  esac

  printf -- '--repo-url\n%s=%s\n' "$name" "$url_part"
  if [[ -n "$branch" ]]; then
    printf -- '--repo-tag\n%s=%s\n' "$name" "$branch"
  fi
}

emit compiler "${COMPILER_SOURCE:-}"
emit runtime  "${RUNTIME_SOURCE:-}"
emit tools    "${TOOLS_SOURCE:-}"
emit stdx     "${STDX_SOURCE:-}"
