#!/usr/bin/env python3
"""Exercise the SDK assembler with native object fixtures, not a compiler build."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

product = Path(__file__).resolve().parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
arch = {'arm64': 'aarch64'}.get(os.uname().machine, os.uname().machine)
darwin = os.uname().sysname == 'Darwin'
tuple_name = f'{"darwin" if darwin else "linux"}_{arch}_cjnative'
ext = 'dylib' if darwin else 'so'
library = 'libLLVM.dylib' if darwin else 'libLLVM-15.so'
linker = 'ld64.lld' if darwin else 'ld.lld'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
pin = dict(line.split('=', 1) for line in (product.parent / 'runtime_pin.env').read_text().splitlines()
           if '=' in line and not line.startswith('#'))['RUNTIME_REF'].strip('"\'')
llvm_sha = '1' * 40

def build(name, source, kind):
    if len(sys.argv) > 2 and sys.argv[2] != '--prepare':
        return Path(sys.argv[2]) / name
    src = out / (name + '.c')
    src.write_text(source)
    result = out / name
    command = ['cc', str(src), '-o', str(result)]
    if kind == 'library':
        command += ['-dynamiclib'] if darwin else ['-shared', '-fPIC']
    elif kind == 'archive':
        obj = out / (name + '.o')
        subprocess.run(['cc', '-c', str(src), '-o', str(obj)], check=True)
        subprocess.run(['ar', 'rcs', str(result), str(obj)], check=True)
        return result
    subprocess.run(command, check=True)
    return result

runtime = build('colour.' + ext, 'int g_cjLoadBadMask; const char stamp[]="CJRT-COMMIT:' + pin + '";', 'library')
host = build('host.' + ext, 'int common_symbol;', 'library')
std = build('std.a', 'extern int g_cjLoadBadMask; int *ref=&g_cjLoadBadMask;', 'archive')
official_std = build('official.a', 'int common_symbol;', 'archive')
tool = build('tool', 'const char stamp[]="CJLLVM-COMMIT:' + llvm_sha + '"; int main(){return 0;}', 'executable')
llvm = build(library, 'const char stamp[]="CJLLVM-COMMIT:' + llvm_sha + '";', 'library')
if len(sys.argv) > 2 and sys.argv[2] == '--prepare':
    sys.exit(0)
base = out / 'base'
prefix = out / 'std-prefix'
tuple_root = out / 'tuple'

def copy(source, relative, root):
    dest = root / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    dest.chmod(source.stat().st_mode)

copy(tool, 'bin/cjc', base)
(base / 'envsetup.sh').write_text(':\n')
for root in (base, prefix):
    copy(official_std if root == base else std, f'lib/{tuple_name}/libcangjie-std-core.a', root)
    copy(host, f'runtime/lib/{tuple_name}/libcangjie-std-core.{ext}', root)
    copy(host, f'lib/libstdFFI.{ext}', root)
    (root / 'modules' / tuple_name).mkdir(parents=True)
    (root / 'modules' / tuple_name / 'std.core.cjo').write_text('module fixture\n')
    (root / 'std-producer.json').write_text(json.dumps({'compiler_sha256': sha(tool)}))
for name in ('libcangjie-runtime', 'libboundscheck'):
    copy(host, f'runtime/lib/{tuple_name}/{name}.{ext}', base)
for name in ('llc', 'opt', linker):
    copy(tool, 'third_party/llvm/bin/' + name, base)
    copy(tool, 'bin/' + name, tuple_root)
copy(llvm, 'third_party/llvm/lib/' + library, base)
if darwin:
    copy(host, 'lib/native-dependency.dylib', base)
    (base / 'lib/native-alias.dylib').symlink_to('native-dependency.dylib')
(base / 'third_party/llvm/MANIFEST').write_text('LLVM_SHA=' + llvm_sha + '\n')
(tuple_root / 'MANIFEST').write_text('LLVM_SHA=' + llvm_sha + '\n')
for relative in ('lib/STATIC_LLVM.txt', 'fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/llc.gz',
                 'fixed-llc/opt.gz', 'fixed-llc/' + linker + '.gz', 'fixed-llc/llvm-tools.manifest'):
    target = tuple_root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('tuple fixture\n')
(tuple_root / 'SHA256SUMS').write_text(''.join(f'{sha(p)}  ./{p.relative_to(tuple_root)}\n'
    for p in sorted(tuple_root.rglob('*')) if p.is_file()))
rt = out / pin
copy(runtime, 'libcangjie-runtime.' + ext, rt)
copy(host, 'libboundscheck.' + ext, rt)
records = []
for name, std_input, expected in (('native-layout', std, 0), ('official-std', official_std, 1)):
    copy(std_input, f'lib/{tuple_name}/libcangjie-std-core.a', prefix)
    target = out / name
    command = ['bash', str(product / 'sdk_build.sh'), '--from', str(base), '--to', str(target),
               '--target', tuple_name, '--runtime', str(rt), '--std', str(prefix),
               '--colour-runtime', str(runtime), '--host-runtime', str(host)]
    if name == 'native-layout':
        command += ['--llvm-tuple', str(tuple_root)]
    result = subprocess.run(command, capture_output=True)
    raw = result.stdout + result.stderr
    (out / (name + '.raw.log')).write_bytes(raw)
    text = raw.decode('utf-8', errors='backslashreplace')
    (out / (name + '.log')).write_text(text)
    # Nonfatal assertions all inspect assembler results, even on an early failure.
    checks = {'status': result.returncode == expected}
    if expected == 0:
        if darwin:
            alias = target / 'lib/native-alias.dylib'
            checks['private-dependency'] = alias.is_file() and not alias.is_symlink() and sha(alias) == sha(host)
        checks['installed-linker'] = (target / 'third_party/llvm/bin' / linker).is_file()
        checks['installed-std'] = (target / f'lib/{tuple_name}/libcangjie-std-core.a').is_file() and sha(target / f'lib/{tuple_name}/libcangjie-std-core.a') == sha(std_input)
        checks['lock-verified'] = 'SDK-VERIFY-OK' in text and 'SDK-BUILD-OK' in text
    else:
        checks['pair-refusal'] = 'STD-RUNTIME-COLOUR-MISMATCH' in text
    record = {'name': name, 'rc': result.returncode, 'checks': checks}
    records.append(record)
    print('ASSERT native-sdk-result ' + json.dumps(record), flush=True)
identities = {str(p.relative_to(product)): sha(p) for p in product.glob('*') if p.is_file()}
(out / 'results.json').write_text(json.dumps({'results': records, 'product': identities,
    'objects': {str(p.name): sha(p) for p in (runtime, host, std, official_std, tool, llvm)}}, indent=2))
assert all(all(r['checks'].values()) for r in records), records
