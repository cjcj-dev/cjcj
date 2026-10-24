import test from 'node:test';
import assert from 'node:assert/strict';
import {pickWindowsCC} from './pick_cc.mjs';

// A real Linux compiler runs the probe here. This covers explicit compiler
// selection, not Windows runtime ABI, MSYS2 or Windows-native execution.
test('explicit compiler selection reaches a real compile probe',async()=>{
 const selected='/usr/lib/llvm-15/bin/clang';
 console.log('EXPLICIT_COMPILER_SELECTION_ASSERTION_REACHED');
 assert.equal(await pickWindowsCC([selected]),selected);
});
test('invalid explicit compiler cannot fall back to an unrelated default',async()=>{
 await assert.rejects(pickWindowsCC(['/nonexistent-explicit-toolchain/clang.exe']),/no working C compiler/);
});
