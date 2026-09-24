#!/usr/bin/env python3
"""Integration check for an assembled stage1 SDK and its pinned target runtime.

Run on the build host: test_target_runtime_link.py SDK EMPTY_OUTPUT_DIRECTORY.
The SDK's cjc entry must already bind the host libraries separately. This test
checks executable linking, not target execution or runtime GC behavior.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    sdk, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
    output.mkdir(parents=True, exist_ok=False)
    compiler = sdk / 'bin/cjc'
    identities = {}
    for relative in ('bin/cjc', 'bin/cjcj-stage1',
                     'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
                     'runtime/lib/linux_x86_64_cjnative/libboundscheck.so',
                     'lib/linux_x86_64_cjnative/libcangjie-runtime.a'):
        identities[relative] = digest(sdk / relative)
    results = {}
    cases = (
        ('static_control', 'public func increment(x: Int64): Int64 { x + 1 }\n',
         ['--output-type=staticlib'], 'control.a'),
        ('executable_link', 'main(): Int64 { return 0 }\n',
         ['--link-option=-t'], 'main'),
    )
    for name, source, options, product in cases:
        src = output / (name + '.cj')
        src.write_text(source)
        temps = output / (name + '-temps')
        temps.mkdir()
        command = [str(compiler), str(src), '-V', '--save-temps', str(temps),
                   *options, '-o', str(output / product)]
        with (output / (name + '.stdout')).open('w') as stdout, \
                (output / (name + '.stderr')).open('w') as stderr:
            rc = subprocess.run(command, stdout=stdout, stderr=stderr,
                                cwd=output, timeout=120).returncode
        passed = rc == 0 and (output / product).is_file()
        results[name] = {'command': command, 'compiler_rc': rc, 'passed': passed,
                         'objects': {p.name: digest(p) for p in sorted(temps.glob('*.o'))}}
        if (output / product).is_file():
            results[name]['sha256'] = digest(output / product)
        print(f'ASSERT {name} executed compiler_rc={rc} passed={passed}', flush=True)
    (output / 'results.json').write_text(json.dumps(
        {'identities': identities, 'tests': results}, indent=2) + '\n')
    return 0 if all(test['passed'] for test in results.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
