#!/usr/bin/env python3
"""Observe the real stdlib_build shell environment; not a std compiler test."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
assert os.uname().sysname == 'Darwin'
platform = 'darwin_' + ('aarch64' if os.uname().machine == 'arm64' else 'x86_64') + '_cjnative'
llvm = Path(subprocess.check_output(['brew', '--prefix', 'llvm@16'], text=True).strip())
sdkroot = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
seed = out / 'fixtures'
seed.mkdir()
source = seed / 'shape.c'
source.write_text('int type_info __asm__("Int64.ti");\n')
subprocess.run(['cc', '-c', str(source), '-o', str(seed/'shape.o')], check=True)
subprocess.run(['ar', 'rcs', str(seed/'shape.a'), str(seed/'shape.o')], check=True)
subprocess.run(['cc', '-dynamiclib', str(source), '-o', str(seed/'shape.dylib')], check=True)
source = seed / 'observer.c'
source.write_text('int main(void) { return 0; }\n')
subprocess.run(['cc', str(source), '-o', str(seed/'observer')], check=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
producer = 'ci/bootstrap/host_tools.sh'
consumer = 'ci/bootstrap/bootstrap.sh'
original = {f: (root/f).read_text() for f in (producer, consumer)}
cuts = {
    'archive-producer-cut': (producer, 'printf \'%s:%s\' "$llvm_prefix/bin" "$HOST_SYSTEM_PATH"', 'printf \'%s\' "$HOST_SYSTEM_PATH"'),
    'archive-consumer-cut': (consumer, '$sdk/third_party/llvm/bin:$system_path', '$sdk/third_party/llvm/bin:$HOST_SYSTEM_PATH'),
    'compiler-producer-cut': (consumer, 'native_toolchain=(--target-toolchain=/usr/bin)', 'native_toolchain=(--target-toolchain=/opt/missing)'),
    'compiler-consumer-cut': (consumer, '"${@:5}"', ''),
    'sdk-producer-cut': (producer, "printf 'SDKROOT=%q ' \"$sdk_root\"", "printf 'SDKROOT=%q ' /"),
    'sdk-consumer-cut': (consumer, '${cache_env}${native_env}${HOST_LOADER_VAR}', '${cache_env}${HOST_LOADER_VAR}'),
}
arms = ['candidate', *cuts, 'restored']

def copy(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)

for arm in arms:
    here = out/arm
    shutil.copytree(root/'ci', here/'ci')
    if arm in cuts:
        file, before, after = cuts[arm]
        text = original[file]
        assert text.count(before) == 1, (arm, before)
        text = text.replace(before, after)
        (here/file).write_text(text)
        (here/'cut.diff').write_text(''.join(difflib.unified_diff(original[file].splitlines(True), text.splitlines(True), fromfile='a/'+file, tofile='b/'+file)))
    for name in ('bin/cjc', 'third_party/llvm/bin/llc'):
        copy(seed/'observer', here/'sdk'/name)
    copy(seed/'shape.dylib', here/'rt/libcangjie-runtime.dylib')
    payload = here/'payload'
    for name, source in [(f'lib/{platform}/libcangjie-std-core.a', 'shape.a'),
                         (f'lib/{platform}/libnetFFI.a', 'shape.a'),
                         (f'runtime/lib/{platform}/libcangjie-std-core.dylib', 'shape.dylib'),
                         ('lib/libstdFFI.dylib', 'shape.dylib')]:
        copy(seed/source, payload/name)
    ast = here/'ast'
    for name in ('include', 'schema', 'third_party/flatbuffers/bin'):
        (ast/name).mkdir(parents=True, exist_ok=True)
    copy(seed/'observer', ast/'third_party/flatbuffers/bin/flatc')
    copy(seed/'shape.a', ast/'libcangjie-ast-support.a')
    (ast/'SHA256SUMS').write_text(''.join(f'{sha(ast/name)}  {name}\n' for name in ['third_party/flatbuffers/bin/flatc','libcangjie-ast-support.a']))
    stdsrc = here/'stdsrc'
    stdsrc.mkdir()
    # The receiving executable records the product command's environment. Its
    # output files satisfy the existing shape check without replacing that check.
    (stdsrc/'build.py').write_text('''import json,os,shutil,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
if sys.argv[1]=='build':
    (root/'observed.json').write_text(json.dumps({'sdkroot':os.environ.get('SDKROOT'),'ranlib':shutil.which('llvm-ranlib'),'llc':shutil.which('llc'),'leak':os.environ.get('LEAK_ME'),'args':sys.argv[1:]}))
if sys.argv[1]=='install':
    shutil.copytree(root/'payload',Path(sys.argv[sys.argv.index('--prefix')+1]),dirs_exist_ok=True)
''')

def run(arm):
    here = out/arm
    env = {**os.environ, 'LEAK_ME': 'must-not-cross'}
    env.pop('SDKROOT', None)
    script = 'source "$1"; STAGE=std-env-control; host_tuple_init; SRC="$2"; WORK="$2/work"; STDSRC="$2/stdsrc"; AST_SUPPORT="$2/ast/libcangjie-ast-support.a"; stdlib_build stdlib-stage1 "$2/sdk" "$2/rt" "$2/result"'
    result = subprocess.run(['bash','-c',script,'bash',str(here/consumer),str(here)],env=env,capture_output=True,text=True)
    (here/'command.log').write_text(result.stdout+result.stderr)
    observed = json.loads((here/'observed.json').read_text()) if (here/'observed.json').exists() else {}
    checks = {'archive-tool': observed.get('ranlib') == str(llvm/'bin/llvm-ranlib'),
              'native-compiler': '--target-toolchain=/usr/bin' in observed.get('args',[]),
              'sdk-root': observed.get('sdkroot') == sdkroot,
              'backend-priority': observed.get('llc') == str(here/'sdk/third_party/llvm/bin/llc'),
              'isolation': 'leak' in observed and observed['leak'] is None,
              'complete-command': result.returncode == 0 and (here/'result/std-producer.json').exists()}
    (here/'checks.json').write_text(json.dumps(checks))
    assertion = subprocess.run([sys.executable,'-c','import json,sys; r=json.load(open(sys.argv[1])); print("ASSERT native-std-env-target",r); sys.exit(not all(r.values()))',str(here/'checks.json')],capture_output=True,text=True)
    (here/'assertions.log').write_text(assertion.stdout+assertion.stderr)
    record = {'rc':assertion.returncode,'product_rc':result.returncode,'checks':checks,'observed':observed,
              'product':{f:sha(here/f) for f in original},'objects':{f:sha(seed/f) for f in ['shape.o','shape.a','shape.dylib','observer']}}
    (here/'result.json').write_text(json.dumps(record,indent=2))
    return arm,record

with concurrent.futures.ThreadPoolExecutor(max_workers=len(arms)) as pool:
    results = dict(pool.map(run,arms))
(out/'results.json').write_text(json.dumps(results,indent=2))
for arm,record in results.items():
    failed = [k for k,v in record['checks'].items() if not v]
    expected = ['archive-tool'] if arm.startswith('archive-') else ['sdk-root'] if arm.startswith('sdk-') else ['native-compiler'] if arm.startswith('compiler-') else []
    print(f'ASSERT native-std-env-control arm={arm} rc={record["rc"]} product_rc={record["product_rc"]} failed={failed}',flush=True)
    assert failed == expected and record['rc'] == bool(expected) and record['product_rc'] == 0
    assert record['objects'] == results['candidate']['objects']
assert results['candidate']['product'] == results['restored']['product']
for arm in arms:
    shutil.rmtree(out/arm/'ci')
