#!/usr/bin/env python3
"""Verify a separately pinned LLVM dylib, including the loaded C API origin."""
import argparse
import ctypes
import hashlib
import json
import re
from pathlib import Path
import subprocess


def verify(directory, llvm_sha, expected_sha):
    root = Path(directory).resolve()
    library = root / 'libLLVM-15.so'
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest['llvm_sha'] != llvm_sha:
        raise ValueError('LLVM_DYLIB_SOURCE_MISMATCH')
    library_bytes = library.read_bytes()
    actual = hashlib.sha256(library_bytes).hexdigest()
    if len(expected_sha) != 64 or actual != expected_sha or manifest['sha256'] != expected_sha:
        raise ValueError(f'LLVM_DYLIB_SHA256_MISMATCH expected={expected_sha} actual={actual}')
    stamps = set(re.findall(rb'CJLLVM-COMMIT:([0-9a-z-]+)', library_bytes))
    if stamps != {llvm_sha.encode()}:
        raise ValueError(f'LLVM_DYLIB_SOURCE_STAMP_MISMATCH expected={llvm_sha} actual={sorted(stamps)}')
    symbols = subprocess.check_output(['nm', '--defined-only', str(library)], text=True)
    defined = {line.split()[-1].split('@')[0] for line in symbols.splitlines() if line.split()}
    required = [f'LLVMInitialize{target}{part}' for target in ('X86', 'ARM', 'AArch64')
                for part in ('TargetInfo', 'Target', 'TargetMC', 'AsmPrinter', 'AsmParser')]
    missing = sorted(set(required) - defined)
    if missing:
        raise ValueError(f'LLVM_DYLIB_TARGETS_MISSING {missing}')
    llvm = ctypes.CDLL(str(library))
    class DlInfo(ctypes.Structure):
        _fields_ = [('name', ctypes.c_char_p), ('base', ctypes.c_void_p),
                    ('symbol', ctypes.c_char_p), ('address', ctypes.c_void_p)]
    dladdr = ctypes.CDLL(None).dladdr
    dladdr.argtypes = [ctypes.c_void_p, ctypes.POINTER(DlInfo)]
    info = DlInfo()
    if not dladdr(ctypes.cast(llvm.LLVMContextCreate, ctypes.c_void_p), ctypes.byref(info)):
        raise ValueError('LLVM_DYLIB_ORIGIN_UNRESOLVED')
    loaded = Path(info.name.decode()).resolve()
    if loaded != library or hashlib.sha256(loaded.read_bytes()).hexdigest() != expected_sha:
        raise ValueError(f'LLVM_DYLIB_LOADED_PATH_MISMATCH {loaded}')
    for symbol in required:
        fn = getattr(llvm, symbol)
        fn.argtypes = []
        fn.restype = None
        fn()
    llvm.LLVMContextCreate.restype = ctypes.c_void_p
    context = llvm.LLVMContextCreate()
    if not context:
        raise ValueError('LLVM_DYLIB_CONTEXT_FAILED')
    llvm.LLVMContextDispose.argtypes = [ctypes.c_void_p]
    llvm.LLVMContextDispose(context)
    print(json.dumps({'loaded': str(loaded), 'sha256': actual, 'llvm_sha': llvm_sha,
                      'targets': required, 'context_call': 'ok'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('llvm_sha')
    parser.add_argument('sha256')
    args = parser.parse_args()
    verify(args.directory, args.llvm_sha, args.sha256)
