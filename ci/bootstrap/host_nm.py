#!/usr/bin/env python3
"""Read native object symbols, normalizing the Mach-O ABI underscore."""
import platform
import subprocess
import sys


def nm_command(arguments):
    if platform.system() != 'Darwin':
        return ['nm', *arguments]
    translated = []
    for arg in arguments:
        if arg == '-D':
            translated.append('-g')
        elif arg == '--defined-only':
            translated.append('-U')
        else:
            translated.append(arg)
    return ['xcrun', 'nm', *translated]


def read_symbols(arguments):
    result = subprocess.run(nm_command(arguments), capture_output=True, text=True)
    if platform.system() == 'Darwin':
        lines = []
        for line in result.stdout.splitlines(keepends=True):
            fields = line.split()
            if len(fields) >= 2 and len(fields[-2]) == 1 and fields[-1].startswith('_'):
                offset = line.rfind(fields[-1])
                line = line[:offset] + line[offset + 1:]
            lines.append(line)
        result.stdout = ''.join(lines)
    return result


if __name__ == '__main__':
    result = read_symbols(sys.argv[1:])
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
