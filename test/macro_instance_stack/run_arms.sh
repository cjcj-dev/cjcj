#!/bin/bash
# Runs on kkk2. ROOT is the uploaded source tree (product + test).
set -euo pipefail
ROOT=${1:?repo}
EVID=${2:?evidence}
SDK=/root/.cjv/toolchains/nightly-1.3.0-alpha.20260904010027
PROBE="$(dirname "$EVID")/probe"
export CANGJIE_HOME="$SDK"
export PATH="$SDK/bin:$SDK/tools/bin:$PATH"
export LD_LIBRARY_PATH="$SDK/runtime/lib/linux_x86_64_cjnative:${SDK}/lib:${LD_LIBRARY_PATH:-}"
export CANGJIE_BUILD_JOBS=192
export CMAKE_BUILD_PARALLEL_LEVEL=192
ulimit -c 0
mkdir -p "$EVID"
uptime > "$EVID/uptime-before.txt"
echo "nproc=$(nproc)" > "$EVID/nproc.txt"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
pkgs = [
    "basic", "utils", "flatbuffers", "option", "lex", "ast", "parse",
    "conditional_compilation", "modules", "macro", "mangle",
]
for name in pkgs:
    p = root / "packages" / name / "cjpm.toml"
    text = p.read_text()
    if 'compile-option = "-O0"' in text:
        continue
    text2 = text.replace('compile-option = ""', 'compile-option = "-O0"', 1)
    if text2 == text:
        raise SystemExit(f"no compile-option in {p}")
    p.write_text(text2)
print("o0_packages", len(pkgs))
PY

gcc -shared -fPIC -o "$EVID/probe.so" "$ROOT/test/macro_instance_stack/probe.c"
gcc -fPIC -c -o "$EVID/host_pin.o" "$ROOT/test/macro_instance_stack/host_pin.c"
export CJCJ337_HOST_O="$EVID/host_pin.o"
echo "gcc_rc=$?"

mkdir -p "$PROBE/src"
cp "$ROOT/test/macro_instance_stack/src/main.cj" "$PROBE/src/main.cj"
cat > "$PROBE/cjpm.toml" <<EOF
[package]
  cjc-version = "1.1.0"
  name = "macro_instance_stack"
  organization = "cjcj_test"
  description = "Observes macro InstanceNew and CallRuntime stack sizes"
  version = "0.1.0"
  src-dir = "src"
  output-type = "executable"
  compile-option = "-O0"
  link-option = "--export-dynamic \${CJCJ337_HOST_O}"

[dependencies]
  "cjcj::macro_pkg" = { path = "$ROOT/packages/macro" }
EOF

build_one() {
    local tag="$1"
    local out="$EVID/$tag"
    mkdir -p "$out"
    local rc
    set +e
    (cd "$PROBE" && cjpm build) > "$out/build.log" 2>&1
    rc=$?
    set -e
    echo "$rc" > "$out/build.rc"
    echo "BUILD $tag rc=$rc"
    if [ "$rc" != 0 ]; then
        tail -n 40 "$out/build.log"
        return 0
    fi
    local bin="$PROBE/target/release/bin/main"
    if [ ! -x "$bin" ]; then
        echo "missing $bin" | tee "$out/bin.path"
        return 0
    fi
    echo "$bin" > "$out/bin.path"
    sha256sum "$bin" > "$out/bin.sha256"
    rm -f "$out/obs.txt"
    set +e
    CJCJ337_LIB="$EVID/probe.so" CJCJ337_OUT="$out/obs.txt" "$bin" > "$out/run.txt" 2>&1
    rc=$?
    set -e
    echo "$rc" > "$out/run.rc"
    echo "RUN $tag rc=$rc"
    echo "---- run ----"
    cat "$out/run.txt"
    echo "---- obs ----"
    cat "$out/obs.txt" 2>/dev/null || true
}

cp "$ROOT/packages/macro/src/InvokeUtil.cj" "$EVID/InvokeUtil.cj.green"
build_one green

python3 - "$ROOT/packages/macro/src/InvokeUtil.cj" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
old = "param.value.write(RuntimeConcurrencyParamC(STACK_SIZE, GetStackSizeFromEnv(initArgs), 1u32))"
new = "param.value.write(RuntimeConcurrencyParamC(0, 0, 1u32))"
text = p.read_text()
if old not in text:
    raise SystemExit("consumer anchor missing")
p.write_text(text.replace(old, new, 1))
PY
diff -u "$EVID/InvokeUtil.cj.green" "$ROOT/packages/macro/src/InvokeUtil.cj" > "$EVID/cut-consumer.diff" || true
build_one consumer

cp "$EVID/InvokeUtil.cj.green" "$ROOT/packages/macro/src/InvokeUtil.cj"
python3 - "$ROOT/packages/macro/src/InvokeUtil.cj" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text2 = text.replace("public let STACK_SIZE: UIntNative = 64 * 1024", "public let STACK_SIZE: UIntNative = 0", 1)
text2 = text2.replace("public let CO_STACK_SIZE: UIntNative = 4 * 1024", "public let CO_STACK_SIZE: UIntNative = 0", 1)
if text2 == text:
    raise SystemExit("producer anchor missing")
p.write_text(text2)
PY
diff -u "$EVID/InvokeUtil.cj.green" "$ROOT/packages/macro/src/InvokeUtil.cj" > "$EVID/cut-producer.diff" || true
build_one producer

cp "$EVID/InvokeUtil.cj.green" "$ROOT/packages/macro/src/InvokeUtil.cj"
diff -u "$EVID/InvokeUtil.cj.green" "$ROOT/packages/macro/src/InvokeUtil.cj" > "$EVID/cut-restored.diff" || true
build_one restored

uptime > "$EVID/uptime-after.txt"
echo ARMS_DONE
python3 - "$EVID" <<'PY'
import pathlib, sys
evid = pathlib.Path(sys.argv[1])
for tag in ("green", "consumer", "producer", "restored"):
    br = (evid/tag/"build.rc").read_text().strip()
    rr = (evid/tag/"run.rc").read_text().strip() if (evid/tag/"run.rc").exists() else "NA"
    print(f"SUMMARY {tag} build={br} run={rr}")
PY
