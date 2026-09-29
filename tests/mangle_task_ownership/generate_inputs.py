#!/usr/bin/env python3
"""Generate legal source; actual task membership is observed after desugaring."""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    macro = lambda name: f'public macro {name}(input: Tokens): Tokens {{ return input }}\n'
    lines = ['macro package ownership\n', 'import std.ast.*\n', macro('RaceA')]
    lines += [f'func before{i}(x: Int64): Int64 {{ x + {i} }}\n' for i in range(29)]
    lines += [macro('RaceB')]
    lines += [f'func after{i}(x: Int64): Int64 {{ x - {i} }}\n' for i in range(31)]
    lines += [macro('Remainder')]
    (args.output / 'parallel.cj').write_text('\n'.join(lines))
    (args.output / 'remainder.cj').write_text(
        'macro package ownershipsmall\nimport std.ast.*\n' + macro('Remainder'))
    (args.output / 'control.cj').write_text('''package ownershipcontrol
public class Recursive {
    public let next: Option<Recursive>
    public init(next: Option<Recursive>) { this.next = next }
}
public class Holder<T> {
    public let value: T
    public init(value: T) { this.value = value }
}
func identity<T>(value: T): T { value }
public func ordinary(x: Int64): Int64 {
    let f = { value: Int64 => identity(value) }
    f(x)
}
public func classLambda(node: Recursive): Option<Recursive> {
    let f = { value: Recursive => identity(value) }
    f(node).next
}
public func genericClass(value: Holder<Recursive>): Recursive { value.value }
''')


if __name__ == '__main__':
    main()
