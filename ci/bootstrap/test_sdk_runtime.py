#!/usr/bin/env python3
"""Thin compatibility entry for the real frozen-plan SDK runtime consumers."""
import os
from pathlib import Path
import sys

if __name__ == '__main__':
    os.execvp('node', ['node', str(Path(__file__).with_name('sdk-consumer-cases.mjs')),
                       '--suite', 'runtime', *sys.argv[1:]])
