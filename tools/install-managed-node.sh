#!/usr/bin/env bash
# Restore the kkk2 Node installation without depending on a mounted PATH entry.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo 'usage: install-managed-node.sh /absolute/source-toolchain /absolute/prefix' >&2
    exit 2
fi
source_dir=${1%/}
prefix=${2%/}
expected=34bc6627675906f8431892630b5e91fc4cc9f1e03ce15e9716025aa551e5c823
name=node-v20.19.0-linux-x64
[[ -n $prefix && $prefix != / ]] || { echo 'prefix must not be /' >&2; exit 2; }
# Verify the original managed binary, never promote a lane-specific Node version.
printf '%s  %s\n' "$expected" "$source_dir/bin/node" | sha256sum --check --status
[[ $("$source_dir/bin/node" --version) == v20.19.0 ]]
for cli in npm npx; do
    [[ -f $source_dir/lib/node_modules/npm/bin/$cli-cli.js ]]
done
mkdir -p "$prefix/lib" "$prefix/bin"
work=$(mktemp -d "$prefix/lib/.node-install.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# Dereference upstream package links: the installed tree is entirely physical.
cp -RL -- "$source_dir" "$work/$name"
dest=$prefix/lib/$name
if [[ -e $dest || -L $dest ]]; then
    # Idempotent reuse only of a complete, identical physical installation.
    [[ ! -L $dest && -d $dest ]]
    [[ -z $(find "$dest" -type l -print -quit) ]]
    diff -qr -- "$work/$name" "$dest"
else
    mv -- "$work/$name" "$dest"
fi
# Stage each entry in bin, then rename over old links without following them.
entry=$(mktemp "$prefix/bin/.node-entry.XXXXXX")
trap 'rm -rf -- "$work"; rm -f -- "$entry"' EXIT
cp -- "$dest/bin/node" "$entry"
chmod 755 "$entry"
mv -fT -- "$entry" "$prefix/bin/node"
for cli in npm npx; do
    entry=$(mktemp "$prefix/bin/.node-entry.XXXXXX")
    # %q preserves spaces and shell metacharacters in an explicitly supplied prefix.
    printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' \
        "$prefix/bin/node" "$dest/lib/node_modules/npm/bin/$cli-cli.js" > "$entry"
    chmod 755 "$entry"
    mv -fT -- "$entry" "$prefix/bin/$cli"
done
printf 'MANAGED_NODE_INSTALLED prefix=%s version=%s sha256=%s\n' "$prefix" "$("$prefix/bin/node" --version)" "$expected"
