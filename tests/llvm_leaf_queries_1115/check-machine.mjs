#!/usr/bin/env zx
// Check the *built compiler*, not a source annotation or a target program's IR.
import fs from 'node:fs';
import {spawn} from 'node:child_process';
import readline from 'node:readline';
import {createHash} from 'node:crypto';
const [elf, mode, output] = process.argv.slice(2);
if (!elf || !output || !['baseline','candidate','cut'].includes(mode))
  throw Error('usage: check-machine.mjs COMPILER_ELF baseline|candidate|cut OUTPUT.json');
const leaves = ['LLVMTypeOf','LLVMGetTypeKind','LLVMGetIntTypeWidth',
  'LLVMGetTypeContext','LLVMGetPointerAddressSpace'];
const watched = new Set([...leaves, 'LLVMBuildNeg']);
const counts = Object.fromEntries([...watched].map(api => [api, {direct:0,c2n:0}]));
const examples = {};
const p = spawn('objdump', ['-d', elf]);
let stderr = '', fn = '', recent = [], pending = null;
p.stderr.on('data', b => stderr += b);
const finished = new Promise((resolve, reject) => {
  p.on('error', reject); p.on('close', (rc, signal) => resolve({rc, signal}));
});
for await (const line of readline.createInterface({input:p.stdout})) {
  if (/^\w+ <.*>:$/.test(line)) { fn = line; recent = []; pending = null; }
  recent.push(line); if (recent.length > 10) recent.shift();
  const reference = line.match(/<(LLVM\w+)(?:@[^>]+)?>/);
  const isCall = /\bcallq?\s/.test(line);
  let api, kind;
  if (reference && watched.has(reference[1])) {
    if (isCall) { api = reference[1]; kind = 'direct'; }
    else if (/\bmov\w*\s.*,%r11\b/.test(line)) pending = reference[1];
  }
  if (isCall) {
    if (/\bCJ_MCC_C2NStub(?:@|>)/.test(line) && pending) { api = pending; kind = 'c2n'; }
    if (api) {
      counts[api][kind]++;
      const key = api + ':' + kind;
      if (!examples[key]) examples[key] = {fn,asm:recent.join('\n')};
    }
    pending = null;
  }
}
const child = await finished;
const checks = leaves.map(api => {
  const c2n = mode === 'baseline' || mode === 'cut' && api === 'LLVMTypeOf';
  return {api,expected:c2n?'c2n':'direct',pass:counts[api][c2n?'c2n':'direct']>0 && counts[api][c2n?'direct':'c2n']===0};
});
checks.push({api:'LLVMBuildNeg',expected:'c2n',pass:counts.LLVMBuildNeg.c2n>0 && counts.LLVMBuildNeg.direct===0});
const result = {elf,mode,sha256:createHash('sha256').update(fs.readFileSync(elf)).digest('hex'),
  command:['objdump','-d',elf],child,stderr,counts,checks,examples,staticCountsOnly:true};
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
for (const check of checks) console.log(`${check.pass?'PASS':'FAIL'} ${check.api} expected=${check.expected} ${JSON.stringify(counts[check.api])}`);
process.exitCode = child.rc === 0 && !child.signal && checks.every(c=>c.pass) ? 0 : 1;
