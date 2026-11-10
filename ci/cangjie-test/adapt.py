"""Python callers use the zx harness adapter; test cases stay in fixed worktrees."""
import json
from pathlib import Path
import subprocess


def prepare(inputs, output):
    record = json.loads(subprocess.check_output(
        ['node', str(Path(__file__).with_suffix('.mjs')), str(inputs), str(output)], text=True))
    return tuple(Path(record[key]) for key in ('test', 'framework', 'harness'))
