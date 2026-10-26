#!/usr/bin/env zx
// Resolve source defaults from their existing pin files; explicit native pairs
// remain caller selections and do not rewrite the defaults.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export function readSourcePins(repo=root) {
  const read=file=>Object.fromEntries(fs.readFileSync(path.join(repo,'ci',file),'utf8').split(/\r?\n/)
    .filter(line=>/^[A-Z_]+=/.test(line)).map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
  const source=read('source_pin.env');
  return {source,runtime:read('runtime_pin.env'),llvm:{...read('llvm_pin.env'),
    CANGJIE_COMPILER_URL:source.COMPILER_SRC_URL,CANGJIE_COMPILER_SHA:source.COMPILER_REF}};
}
export function nativeLlvmInputs(env=process.env) {
  const {llvm,runtime}=readSourcePins();
  const requestedLlvm=env.CJCJ_NATIVE_LLVM_REF || '', requestedRuntime=env.CJCJ_NATIVE_RUNTIME_REF || '';
  if (Boolean(requestedLlvm)!==Boolean(requestedRuntime)) throw new Error('NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED');
  for (const ref of [requestedLlvm || llvm.LLVM_SHA, requestedRuntime || runtime.RUNTIME_REF]) {
    if (!/^[a-f0-9]{40}$/.test(ref || '')) throw new Error('NATIVE_LLVM_REF_INVALID');
  }
  // Pin-file keys describe source facts; the process boundary has one pair.
  return {LLVM_URL:llvm.LLVM_URL, CANGJIE_COMPILER_URL:llvm.CANGJIE_COMPILER_URL,
    CANGJIE_COMPILER_SHA:llvm.CANGJIE_COMPILER_SHA, FLATBUFFERS_URL:llvm.FLATBUFFERS_URL,
    FLATBUFFERS_SHA:llvm.FLATBUFFERS_SHA,
    CJCJ_NATIVE_LLVM_REF:requestedLlvm || llvm.LLVM_SHA,
    CJCJ_NATIVE_RUNTIME_REF:requestedRuntime || runtime.RUNTIME_REF};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const selected=nativeLlvmInputs(),output=Object.entries(selected).map(([key,value])=>`${key}=${value}\n`).join('');
  if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV,output);
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT,`sha=${selected.CJCJ_NATIVE_LLVM_REF}\nruntime_sha=${selected.CJCJ_NATIVE_RUNTIME_REF}\n`);
  process.stdout.write(output);
}
