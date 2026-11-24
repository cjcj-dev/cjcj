import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {WINDOWS_RUNTIME_CC, defaultWindowsCandidates, pickWindowsCC} from './pick_cc.mjs';

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
// CJCJ_NATIVE_LLVM_BIN names the actual MINGW64 bin (setup-msys2 under RUNNER_TEMP).
// A real compiler reached through that directory's clang.exe must be picked by the
// default candidates; with no working compiler there the probe falls through.
test('default candidates probe a working CJCJ_NATIVE_LLVM_BIN clang.exe first',async t=>{
 const bin=fs.mkdtempSync(path.join(os.tmpdir(),'llvm-bin-'));
 t.after(()=>fs.rmSync(bin,{recursive:true,force:true}));
 fs.symlinkSync('/usr/lib/llvm-15/bin/clang',path.join(bin,'clang.exe'));
 assert.equal(await pickWindowsCC(defaultWindowsCandidates({CJCJ_NATIVE_LLVM_BIN:bin})),path.join(bin,'clang.exe'));
});
test('an empty CJCJ_NATIVE_LLVM_BIN falls through to fallbacks that the runtime rejects',async t=>{
 const bin=fs.mkdtempSync(path.join(os.tmpdir(),'llvm-bin-empty-'));
 t.after(()=>fs.rmSync(bin,{recursive:true,force:true}));
 const picked=await pickWindowsCC(defaultWindowsCandidates({CJCJ_NATIVE_LLVM_BIN:bin})).catch(error=>error);
 assert.notEqual(picked,path.join(bin,'clang.exe'));
 if(typeof picked==='string')assert.doesNotMatch(picked,WINDOWS_RUNTIME_CC);
 else assert.match(picked.message,/no working C compiler/);
});
