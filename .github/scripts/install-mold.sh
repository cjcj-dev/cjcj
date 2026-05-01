#!/usr/bin/env bash
# Install a recent mold linker (much faster than the BFD ld that Ubuntu 22.04
# ships, and substantially newer than mold in the 22.04 apt repos).
#
# Drops the binary at /usr/local/bin/mold + /usr/local/bin/ld.mold so that
# `-fuse-ld=mold` works without further wiring.
#
# Usage: install-mold.sh [version]   (default v2.41.0)
set -euo pipefail

ver="${1:-v2.41.0}"
ver_no_v="${ver#v}"
arch=$(uname -m)
case "$arch" in
  x86_64|aarch64) ;;
  *) echo "unsupported arch $arch" >&2; exit 1 ;;
esac

url="https://github.com/rui314/mold/releases/download/${ver}/mold-${ver_no_v}-${arch}-linux.tar.gz"
echo "Installing mold ${ver} from ${url}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" | tar xz -C "$tmp" --strip-components=1
sudo cp -a "$tmp/bin/." /usr/local/bin/
sudo cp -a "$tmp/lib/." /usr/local/lib/ 2>/dev/null || true
sudo cp -a "$tmp/libexec/." /usr/local/libexec/ 2>/dev/null || true

mold --version
