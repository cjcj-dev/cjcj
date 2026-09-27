#!/usr/bin/env python3
"""Run the real bootstrap_target_std assembler and observe its link inputs.

Native objects are fixtures. SDK assembly, runner installation and the pinned std
parser are real; the CMake receiver observes their results without compiling std.
"""
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
std_build = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
assert os.uname().sysname == 'Darwin'
platform = 'darwin_' + ('aarch64' if os.uname().machine == 'arm64' else 'x86_64')
tuple_name = platform + '_cjnative'
seed = out/'seed'
subprocess.run([sys.executable, str(root/'ci/bootstrap/test_native_sdk.py'), str(seed)], check=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def copy(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)

# Make the native objects distinguishable so the consumer cut changes bytes,
# without preventing the enclosing product command from completing.
(seed/'shape.c').write_text('int ti __asm__("Int64.ti");\n')
subprocess.run(['cc', '-c', str(seed/'shape.c'), '-o', str(seed/'section.o')], check=True)
subprocess.run(['cc', '-dynamiclib', str(seed/'shape.c'), '-o', str(seed/'shape.dylib')], check=True)
(seed/'colour-std.c').write_text('extern int g_cjLoadBadMask; int *ref=&g_cjLoadBadMask; int ti __asm__("Int64.ti");\n')
subprocess.run(['cc', '-c', str(seed/'colour-std.c'), '-o', str(seed/'colour-std.o')], check=True)
subprocess.run(['ar', 'rcs', str(seed/'colour-std.a'), str(seed/'colour-std.o')], check=True)
consumer = 'ci/bootstrap/bootstrap.sh'
original = (root/consumer).read_text()
baseline = subprocess.check_output(['git', '-C', str(root), 'show',
    '1c434c1a97d90119539bab2f5a5750b93a77484d:' + consumer], text=True)
producer_line = '    native_files+=(section.o)'
copy_line = '$(printf \'%q\' "$sdk/lib/$HOST_TUPLE/$file") $(printf \'%q\' "$native/$file")'
cuts = {'producer-cut': (producer_line, '    :'),
        'consumer-cut': (copy_line, copy_line.replace('$HOST_TUPLE/$file', '$HOST_TUPLE/${file/section.o/cjstart.o}'))}
arms = ['baseline', 'candidate', *cuts, 'restored']
for arm in arms:
    here = out/arm
    shutil.copytree(root/'ci', here/'ci')
    product = baseline if arm == 'baseline' else original
    if arm in cuts:
        before, after = cuts[arm]
        assert product.count(before) == 1
        product = product.replace(before, after)
        (here/'cut.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True), product.splitlines(True),
            fromfile='a/'+consumer, tofile='b/'+consumer)))
    (here/consumer).write_text(product)
    sdk = here/'work/sdk-stage0'
    shutil.copytree(seed/'base', sdk)
    copy(seed/'tool', sdk/'tools/bin/cjpm')
    for name, source in [('libcangjie-aio.a', 'std.a'), ('cjstart.o', 'std.a.o'), ('section.o', 'section.o')]:
        copy(seed/source, sdk/f'lib/{tuple_name}'/name)
    copy(seed/'libLLVM.dylib', here/'work/sdk-stage0-run/third_party/llvm/lib/libLLVM.dylib')
    for name in ['libcangjie-runtime.dylib', 'libboundscheck.dylib']:
        copy(seed/'colour.dylib', here/'crt'/name)
    (here/'identities').write_text(''.join(f'{platform} {name} {sha(seed/source)}\n' for name, source in
        [('libcangjie-runtime.dylib', 'host.dylib'), ('libboundscheck.dylib', 'host.dylib'), ('libLLVM.dylib', 'libLLVM.dylib')]))
    payload = here/'payload'
    for name, source in [(f'lib/{tuple_name}/libcangjie-std-core.a', 'colour-std.a'),
                         (f'lib/{tuple_name}/libnetFFI.a', 'std.a'),
                         (f'runtime/lib/{tuple_name}/libcangjie-std-core.dylib', 'shape.dylib'),
                         ('lib/libstdFFI.dylib', 'shape.dylib')]:
        copy(seed/source, payload/name)
    ast = here/'ast'
    for name in ['include', 'schema', 'third_party/flatbuffers/bin']:
        (ast/name).mkdir(parents=True, exist_ok=True)
    copy(seed/'tool', ast/'third_party/flatbuffers/bin/flatc')
    copy(seed/'std.a', ast/'libcangjie-ast-support.a')
    (ast/'SHA256SUMS').write_text(''.join(f'{sha(ast/name)}  {name}\n' for name in
        ['libcangjie-ast-support.a', 'third_party/flatbuffers/bin/flatc']))
    copy(std_build, here/'stdsrc/build.py')
    # Installed by the real sdk_build.sh, then executed by the real std parser.
    receiver = sdk/'bin/cmake'
    receiver.write_text('''#!/usr/bin/env python3
import hashlib,json,shutil,sys
from pathlib import Path
root=Path(__file__).resolve().parents[3]
if '--install' not in sys.argv:
    link=Path(next(x.split('=',1)[1] for x in sys.argv if x.startswith('-DCANGJIE_TARGET_LIB=')))
    observed={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in link.rglob('*') if p.is_file()}
    (root/'observed.json').write_text(json.dumps({'files':observed,'args':sys.argv[1:],'link_root':str(link)}))
else:
    shutil.copytree(root/'payload',Path(sys.argv[sys.argv.index('--prefix')+1]),dirs_exist_ok=True)
''')
    receiver.chmod(0o755)
    copy(seed/'tool', sdk/'bin/ninja')

def run(arm):
    here = out/arm
    env = {**os.environ, 'STAGE1_HOST_IDENTITIES':str(here/'identities')}
    script = '''source "$1"; STAGE=std-layout-control; host_tuple_init
SRC="$2"; WORK="$2/work"; STDSRC="$2/stdsrc"; AST_SUPPORT="$2/ast/libcangjie-ast-support.a"
CRT="$2/crt"; HRT="$WORK/sdk-stage0"; COLOUR_TUPLE="$3/tuple"
COLOUR_LLVM_SO="$3/libLLVM.dylib"; COLOUR_LLVM_SHA256=$(sha256 "$COLOUR_LLVM_SO"); HOST_LLVM_SHA256=$COLOUR_LLVM_SHA256
bootstrap_target_std "$3/tool" "$2/result"
'''
    result = subprocess.run(['bash','-c',script,'bash',str(here/consumer),str(here),str(seed)],
                            env=env,capture_output=True,text=True,errors='backslashreplace')
    (here/'command.log').write_text(result.stdout+result.stderr)
    observed = json.loads((here/'observed.json').read_text()) if (here/'observed.json').exists() else {}
    files = observed.get('files',{})
    checks = {'native-section':files.get('section.o') == sha(seed/'section.o'),
              'native-start':files.get('cjstart.o') == sha(seed/'std.a.o'),
              'native-aio':files.get('libcangjie-aio.a') == sha(seed/'std.a'),
              'target-runtime':files.get('libcangjie-runtime.dylib') == sha(seed/'colour.dylib'),
              'native-linker':'-DCANGJIE_TARGET_TOOLCHAIN=' in observed.get('args',[]),
              'complete-command':result.returncode == 0 and (here/'result/std-producer.json').is_file()}
    (here/'checks.json').write_text(json.dumps(checks))
    assertion = subprocess.run([sys.executable,'-c',
        'import json,sys; r=json.load(open(sys.argv[1])); print("ASSERT native-std-layout",r); sys.exit(not all(r.values()))',
        str(here/'checks.json')],capture_output=True,text=True)
    (here/'assertions.log').write_text(assertion.stdout+assertion.stderr)
    record = {'rc':assertion.returncode,'product_rc':result.returncode,'checks':checks,'observed':observed,
              'product_sha256':sha(here/consumer),'parser_sha256':sha(std_build),
              'objects':{name:sha(seed/name) for name in ['tool','std.a','std.a.o','section.o','colour.dylib','host.dylib']}}
    (here/'result.json').write_text(json.dumps(record,indent=2))
    return arm,record

with concurrent.futures.ThreadPoolExecutor(max_workers=len(arms)) as pool:
    results = dict(pool.map(run,arms))
(out/'results.json').write_text(json.dumps(results,indent=2))
for arm,record in results.items():
    failed = [k for k,v in record['checks'].items() if not v]
    expected = ['native-section'] if arm in ['baseline', *cuts] else []
    print(f'ASSERT native-std-layout arm={arm} rc={record["rc"]} product_rc={record["product_rc"]} failed={failed}',flush=True)
    assert failed == expected and record['rc'] == bool(expected) and record['product_rc'] == 0
    assert record['objects'] == results['candidate']['objects']
assert results['candidate']['product_sha256'] == results['restored']['product_sha256']
for arm in arms:
    shutil.rmtree(out/arm/'ci')
