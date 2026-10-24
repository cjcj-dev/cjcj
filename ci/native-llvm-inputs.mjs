#!/usr/bin/env zx
// Resolve a native producer's source pair without editing the official pins.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const readPin=file=>Object.fromEntries(fs.readFileSync(path.join(root,file),'utf8').split(/\r?\n/)
  .filter(line=>/^[A-Z_]+=/.test(line)).map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const llvm=readPin('ci/llvm_pin.env'), runtime=readPin('ci/runtime_pin.env');
const requestedLlvm=process.env.NATIVE_LLVM_REF || '', requestedRuntime=process.env.NATIVE_RUNTIME_REF || '';
if (Boolean(requestedLlvm)!==Boolean(requestedRuntime)) throw new Error('NATIVE_LLVM_PAIR_REQUIRED');
for (const ref of [requestedLlvm || llvm.LLVM_SHA, requestedRuntime || runtime.RUNTIME_REF]) {
  if (!/^[a-f0-9]{40}$/.test(ref || '')) throw new Error('NATIVE_LLVM_REF_INVALID');
}
const selected={...llvm, LLVM_SHA:requestedLlvm || llvm.LLVM_SHA,
  CJCJ_NATIVE_RUNTIME_REF:requestedRuntime || runtime.RUNTIME_REF};
if (requestedRuntime) Object.assign(selected, {CJCJ_LLVM_RUNTIME_MODE:'private',
  CJCJ_LLVM_RUNTIME_URL:'https://github.com/cjcj-dev/cangjie-runtime.git',CJCJ_LLVM_RUNTIME_SHA:requestedRuntime});
const output=Object.entries(selected).map(([key,value])=>`${key}=${value}\n`).join('');
if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV,output);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT,`sha=${selected.LLVM_SHA}\nruntime_sha=${selected.CJCJ_NATIVE_RUNTIME_REF}\n`);
process.stdout.write(output);
