#!/usr/bin/env python3
"""Compatibility launcher; the source-input contract is implemented in zx ESM."""
import os
from pathlib import Path
import sys
os.execvp('node', ['node', str(Path(__file__).with_name('test-llvm-runtime-input.mjs')), *sys.argv[1:]])
