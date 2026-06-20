#!/usr/bin/env bash
# Builds an imported package with Leaf <: Mid <: Exception and verifies that
# catching Mid works with both the reference compiler and the self-host compiler.
set -euo pipefail

TC=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export CANGJIE_HOME=$TC
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF=/root/.cjv/bin/cjc
SELF="$REPO/target/release/bin/cangjie_compiler::cjc"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/lib" "$WORK/src"
cat >"$WORK/lib/lib.cj" <<'CJ'
package mcfixprobe

public open class Mid <: Exception {
    public init(message: String) {
        super(message)
    }
}

public class Leaf <: Mid {
    public init() {
        super("leaf")
    }
}
CJ

cat >"$WORK/src/main.cj" <<'CJ'
import mcfixprobe.*

main() {
    try {
        throw Leaf()
    } catch (e: Mid) {
        println("mid")
    } catch (e: Exception) {
        println("exception")
    }
}
CJ

"$REF" "$WORK/lib/lib.cj" --output-type=staticlib -o "$WORK/lib/libmcfixprobe.a" --set-runtime-rpath

"$REF" "$WORK/src/main.cj" --import-path "$WORK/lib" -L "$WORK/lib" -lmcfixprobe \
    -o "$WORK/src/ref" --set-runtime-rpath
o_ref=$("$WORK/src/ref")
c_ref=$?

"$SELF" "$WORK/src/main.cj" --import-path "$WORK/lib" -L "$WORK/lib" -lmcfixprobe \
    -o "$WORK/src/self" --set-runtime-rpath
o_self=$("$WORK/src/self")
c_self=$?

printf 'ref_output=%s\nref_exit=%s\nself_output=%s\nself_exit=%s\n' "$o_ref" "$c_ref" "$o_self" "$c_self"
test "$o_ref" = "$o_self"
test "$c_ref" = "$c_self"
