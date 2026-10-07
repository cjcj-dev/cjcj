#!/usr/bin/env zx
// Authenticate retained std independently from the runtime selected for SDK
// assembly. Equal source trees permit reuse; source provenance is never edited.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

const [work, sums, runtimeSource, selected, compilerSha] = process.argv.slice(2);
const std = path.join(work, 'stdlib-stage1');
const origin = fs.readFileSync(path.join(std, 'STDLIB_SOURCE_SHA'), 'utf8').trim();
if (![origin, selected].every(value => /^[0-9a-f]{40}$/.test(value))) throw Error('RESUME_STD_SOURCE_INVALID');
const git = async revision => {
  const result = await $({verbose: false})`ulimit -c 0; git -C ${runtimeSource} rev-parse ${revision}`;
  return result.stdout.trim();
};
const originalTree = await git(`${origin}:stdlib`);
const selectedTree = await git(`${selected}:stdlib`);
if (originalTree !== selectedTree) throw Error('RESUME_STD_TREE_MISMATCH');
await $({cwd: std, verbose: false})`ulimit -c 0; sha256sum -c ${path.resolve(sums)}`;
const lock = JSON.parse(fs.readFileSync(path.join(work, 'sdk-stage1/SDK.lock.json'), 'utf8'));
if (lock.components.cjc.sha256 !== compilerSha) throw Error('RESUME_SDK_COMPILER_MISMATCH');
const producer = JSON.parse(fs.readFileSync(path.join(std, 'std-producer.json'), 'utf8'));
if (producer.compiler_sha256 !== compilerSha) throw Error('RESUME_STD_COMPILER_MISMATCH');
// Validate the retained SDK against its own recorded runtime, then rebuild it
// with the selected target. Neither lock nor source stamp is rewritten here.
const runtime = path.join(work, 'sdk-stage1/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so');
const bytes = fs.readFileSync(runtime);
if (!bytes.includes(Buffer.from(`CJRT-COMMIT:${lock.components.runtime.commit}\0`))) {
  throw Error('RESUME_SDK_RUNTIME_MISMATCH');
}
const sourceTree = await git(`${lock.components.runtime.commit}:stdlib`);
if (sourceTree !== originalTree) throw Error('RESUME_SDK_STD_TREE_MISMATCH');
console.log(`RESUME_STD_IDENTITY source=${origin} tree=${originalTree} selected_runtime=${selected} retained_runtime=${lock.components.runtime.commit} runtime_sha256=${createHash('sha256').update(bytes).digest('hex')}`);
