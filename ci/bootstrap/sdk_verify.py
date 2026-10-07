#!/usr/bin/env python3
"""Compatibility CLI; SDK lock implementation migrated to zx ESM (cjcj#883)."""
import os, pathlib, sys
os.execvp('node', ['node', str(pathlib.Path(__file__).with_suffix('.mjs')), *sys.argv[1:]])
