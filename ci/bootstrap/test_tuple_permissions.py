#!/usr/bin/env python3
"""Compatibility entry for the frozen real-producer tuple mode consumers."""
import os
from pathlib import Path
import sys

if __name__ == '__main__':
    os.execvp('node', ['node', str(Path(__file__).with_name('sdk-consumer-cases.mjs')),
                       '--suite', 'tuple', *sys.argv[1:]])
