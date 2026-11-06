#!/usr/bin/env zx
// Check the IR emitted by the real compiler for threadfuture-managed-copy.cj.
// Compile with -O2 --save-temps, then llvm-dis both pre/post optimization files.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [rawPath,optPath]=process.argv.slice(2);
assert(rawPath && optPath,'usage: check-threadfuture-managed-copy.mjs raw.ll optimized.ll');
function method(path) {
 const ir=fs.readFileSync(path,'utf8');
 const m=ir.match(/^define [^\n]*@"_CN11cjcj:driver12ThreadFuture8GetStateHv"[^\n]*\{\n[\s\S]*?^}/m);
 assert(m,'actual ThreadFuture.GetState definition must be emitted');
 return m[0];
}
for(const [stage,path] of [['frontend',rawPath],['optimized',optPath]]) {
 const ir=method(path);
 assert(ir.includes('_CNat6FutureIG_E3getHv'),'ordinary Future.get call must remain');
 // This no-reference field copy must not hide a moving heap address in an
 // integer/native pointer. Such a value is invisible to gc.relocate.
 assert(!/ptrtoint [^\n]*addrspace\(1\)/.test(ir),stage+': managed field address escaped through ptrtoint');
 assert(!/addrspacecast [^\n]*addrspace\(1\)\* [^\n]* to [^\n]*\*(?:,|$)/m.test(ir),stage+': managed field address escaped through addrspacecast');
 if(stage==='frontend')assert(/load i1, i1 addrspace\(1\)\*/.test(ir),'managed field load must retain AS1');
 else assert(ir.includes('llvm.cj.gc.relocate'),'optimized method must contain relocation');
 console.log(stage+': managed copy address-space invariant PASS');
}
