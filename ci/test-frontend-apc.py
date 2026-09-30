#!/usr/bin/env python3
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


WARNING = "'--apc' is not supported for a frontend output file."


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inspect_bitcode(library_path, bitcode):
    library = ctypes.CDLL(str(library_path))
    pointer = ctypes.c_void_p

    def api(name, result, *arguments):
        function = getattr(library, name)
        function.restype = result
        function.argtypes = list(arguments)
        return function

    context = api('LLVMContextCreate', pointer)()
    api('LLVMContextSetOpaquePointers', None, pointer, ctypes.c_int)(context, 0)
    buffer = pointer()
    message = ctypes.c_char_p()
    opened = api('LLVMCreateMemoryBufferWithContentsOfFile', ctypes.c_int,
                 ctypes.c_char_p, ctypes.POINTER(pointer), ctypes.POINTER(ctypes.c_char_p))(
                     os.fsencode(bitcode), ctypes.byref(buffer), ctypes.byref(message))
    if opened:
        raise RuntimeError(f'open_rc={opened}: {message.value}')
    module = pointer()
    parsed = api('LLVMParseBitcodeInContext2', ctypes.c_int, pointer, pointer,
                 ctypes.POINTER(pointer))(context, buffer, ctypes.byref(module))
    if parsed:
        raise RuntimeError(f'parse_rc={parsed}')
    first = api('LLVMGetFirstFunction', pointer, pointer)
    following = api('LLVMGetNextFunction', pointer, pointer)
    declaration = api('LLVMIsDeclaration', ctypes.c_int, pointer)
    name = api('LLVMGetValueName2', pointer, pointer, ctypes.POINTER(ctypes.c_size_t))
    definitions = []
    function = first(module)
    while function:
        if not declaration(function):
            length = ctypes.c_size_t()
            address = name(function, ctypes.byref(length))
            definitions.append(ctypes.string_at(address, length.value).decode())
        function = following(function)
    print(json.dumps({'parse_rc': parsed, 'definitions': sorted(definitions)}), flush=True)
    api('LLVMDisposeModule', None, pointer)(module)
    api('LLVMContextDispose', None, pointer)(context)


def run_matrix(arguments):
    root = arguments.work.resolve()
    root.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment['CANGJIE_HOME'] = str(arguments.sdk.resolve())
    library_dirs = [arguments.llvm_library.resolve().parent,
                    arguments.sdk / 'runtime/lib/linux_x86_64_cjnative',
                    arguments.sdk / 'lib/linux_x86_64_cjnative',
                    arguments.sdk / 'third_party/llvm/lib', arguments.sdk / 'tools/lib']
    environment['LD_LIBRARY_PATH'] = ':'.join(map(str, library_dirs))
    environment['cjHeapSize'] = '32GB'
    environment['TMPDIR'] = str(root / 'tmp')
    (root / 'tmp').mkdir(exist_ok=True)
    compiler = arguments.compiler.resolve()
    entry_dir = root / 'frontend'
    entry_dir.mkdir(exist_ok=True)
    shutil.copyfile(compiler, entry_dir / 'cjcj-stage1')
    (entry_dir / 'cjcj-stage1').chmod(0o755)
    (entry_dir / 'cjc-frontend').symlink_to('cjcj-stage1')
    (entry_dir / 'cjc').symlink_to('cjcj-stage1')
    identities = {str(path): sha256(path) for path in [compiler, arguments.llvm_library,
                  arguments.sdk / 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
                  arguments.sdk / 'runtime/lib/linux_x86_64_cjnative/libboundscheck.so']}
    (root / 'identities.json').write_text(json.dumps(identities, indent=2))
    (root / 'uptime-before.txt').write_text(subprocess.check_output(['uptime'], text=True))
    (root / 'affinity.txt').write_text(next(line for line in Path('/proc/self/status').read_text().splitlines()
                                         if line.startswith('Cpus_allowed_list:')))
    started = time.monotonic()
    assertions = []

    def check(name, passed, details):
        record = {'assertion': name, 'passed': passed, 'details': details}
        assertions.append(record)
        print(json.dumps(record), flush=True)

    def compile_case(surface, inputs, mode, apc, iteration, reference, incremental=False, execution=''):
        work = root / surface / mode / apc / str(iteration)
        work.mkdir(parents=True, exist_ok=True)
        evidence = work / execution if execution else work
        evidence.mkdir(parents=True, exist_ok=True)
        output = work / 'complete.bc'
        command = [str(entry_dir / ('cjc' if mode == 'driver' else 'cjc-frontend')),
                   *inputs, '--output-type=staticlib', '--jobs', str(os.cpu_count())]
        if apc == 'explicit':
            command.append('--apc=4')
        elif apc == 'bare':
            command.append('--apc')
        elif apc == 'one':
            command.append('--apc=1')
        elif apc == 'split':
            command.extend(['--apc-split-num', '5'])
        if incremental:
            command.append('--incremental-compile')
        if mode in ('file', 'incremental'):
            command.extend(['-o', str(output)])
        elif mode == 'directory':
            command.extend(['-o', str(work)])
        elif mode == 'driver':
            command.extend(['--save-temps', '-o', str(work / 'package.a')])
        (evidence / 'command.json').write_text(json.dumps(command))
        with (evidence / 'compile.log').open('w') as log:
            try:
                result = subprocess.run(command, cwd=work, env=environment, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=900)
                compile_rc = result.returncode
            except subprocess.TimeoutExpired:
                compile_rc = 124
        (evidence / 'compile.rc').write_text(str(compile_rc) + '\n')
        label = f'{surface}/{mode}/{apc}/{iteration}/{execution}'
        check(label + '/compile', compile_rc == 0, compile_rc)
        warning_count = (evidence / 'compile.log').read_text().count(WARNING)
        warning_expected = 1 if mode in ('file', 'incremental') and apc in ('explicit', 'bare') else 0
        check(label + '/warning', warning_count == warning_expected,
              {'count': warning_count, 'expected': warning_expected})
        files = sorted(work.glob('*.bc'))
        if mode == 'driver':
            files = sorted(work.rglob('*.bc'))
        check(label + '/output-contract', len(files) == 1 if mode in ('file', 'incremental') or apc == 'one'
              else len(files) > 1, [str(path) for path in files])
        definitions = set()
        for bitcode in files:
            if execution:
                copied = evidence / bitcode.name
                shutil.copyfile(bitcode, copied)
                bitcode = copied
            parse = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--inspect',
                                    str(arguments.llvm_library), str(bitcode)],
                                   env=environment, capture_output=True, text=True, timeout=120)
            bitcode.with_suffix('.parse.log').write_text(parse.stdout + parse.stderr)
            bitcode.with_suffix('.parse.rc').write_text(str(parse.returncode) + '\n')
            bitcode.with_suffix('.sha256').write_text(sha256(bitcode) + '\n')
            check(label + '/parse/' + bitcode.name, parse.returncode == 0, parse.returncode)
            if parse.returncode == 0:
                definitions.update(json.loads(parse.stdout)['definitions'])
        (evidence / 'definitions.json').write_text(json.dumps(sorted(definitions), indent=2))
        check(label + '/complete', bool(definitions) and (reference is None or definitions == reference),
              {'definitions': len(definitions), 'missing': sorted((reference or set()) - definitions),
               'extra': sorted(definitions - (reference or definitions))})
        return definitions

    surfaces = {
        'objects': [str(arguments.repo / 'tests/runtime_layout/layout.cj'), '-g', '-O0'],
        'arrays': ['-p', str(arguments.core), '--no-sub-pkg', '--no-prelude', '-O2'],
        'array-ref': [str(arguments.repo / 'tests/frontend_apc/arrays.cj'), '-O0'],
    }
    for surface, inputs in surfaces.items():
        reference = compile_case(surface, inputs, 'file', 'one', 0, None)
        if surface != 'arrays':
            names = ['childCount', 'newChild', 'makeNumber', 'makeReference'] if surface == 'objects' else [
                'readValue', 'writeValue', 'readReference', 'writeReference', 'arraySize']
            for name in names:
                check(surface + '/reference/' + name, any(name in function for function in reference), name)
        for mode in ('file', 'directory', 'no-output'):
            for apc in ('default', 'explicit', 'bare'):
                for iteration in range(1, arguments.iterations + 1):
                    compile_case(surface, inputs, mode, apc, iteration, reference)
        compile_case(surface, inputs, 'file', 'split', 1, reference)
        compile_case(surface, inputs, 'file', 'one', 1, reference)
        if surface != 'arrays':
            for apc in ('default', 'explicit', 'bare'):
                compile_case(surface, inputs, 'incremental', apc, 1, reference, True, 'cold')
                compile_case(surface, inputs, 'incremental', apc, 1, reference, True, 'warm')
            compile_case(surface, inputs, 'driver', 'explicit', 1, reference)
    result = {'assertions': assertions, 'failed': sum(not item['passed'] for item in assertions),
              'wall': time.monotonic() - started, 'jobs': os.cpu_count(), 'iterations': arguments.iterations}
    (root / 'result.json').write_text(json.dumps(result, indent=2))
    (root / 'uptime-after.txt').write_text(subprocess.check_output(['uptime'], text=True))
    return int(result['failed'] != 0)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--inspect':
        inspect_bitcode(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        parser = argparse.ArgumentParser()
        for option in ('compiler', 'sdk', 'llvm-library', 'repo', 'core', 'work'):
            parser.add_argument('--' + option, type=Path, required=True)
        parser.add_argument('--iterations', type=int, default=3)
        sys.exit(run_matrix(parser.parse_args()))
