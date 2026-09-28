#!/usr/bin/env python3
"""Export pinned inputs from local git repositories into a new private directory."""
import argparse
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
from run import dump, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repositories', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    pins = json.loads(Path(__file__).with_name('inputs.json').read_text())
    args.output.mkdir(parents=True, exist_ok=False)
    for name, commit in pins.items():
        destination = args.output / name
        destination.mkdir()
        # Temporary archives live beside the output, never in /tmp.
        with tempfile.TemporaryFile(dir=args.output) as archive:
            subprocess.run(['git', '-C', str(args.repositories / name), 'archive', commit],
                           stdout=archive, check=True)
            archive.seek(0)
            with tarfile.open(fileobj=archive) as source:
                source.extractall(destination, filter='data')
    files = {str(path.relative_to(args.output)): sha(path)
             for path in sorted(args.output.rglob('*')) if path.is_file()}
    dump(args.output / 'source-manifest.json', {'pins': pins, 'files': files})


if __name__ == '__main__':
    main()
