#!/usr/bin/env zx
// Compatibility names resolve a complete frozen plan; loose component paths
// can no longer assemble a second SDK behind the manifest entry.
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {assembleSdk} from './toolchain-sdk.mjs';
import {readJson, reject, execute} from './sdk-manifest.mjs';

const shellQuote = value => `'${value.replaceAll("'", "'\\''")}'`;
export async function main(args = process.argv.slice(2)) {
  if (args[0] === 'env') {
    const {values} = parseArgs({args: args.slice(1), options: {'host-sdk': {type: 'string'}, 'target-sdk': {type: 'string'}}});
    const host = await fs.realpath(values['host-sdk']), target = await fs.realpath(values['target-sdk']);
    const hostLock = await readJson(path.join(host, 'SDK.lock.json')), targetLock = await readJson(path.join(target, 'SDK.lock.json'));
    if (hostLock.role !== 'host' || targetLock.role !== 'target') reject('DOMAIN', 'env', 'requires host and target SDK locks');
    const tuple = (await readJson(path.join(target, 'SDK.plan.json'))).platform + '_cjnative';
    const hostRuntime = path.join(host, 'runtime/lib', tuple);
    await execute('python3', [fileURLToPath(new URL('./sdk_verify.py', import.meta.url)), '--sdk', host, '--role', 'host']);
    await execute('python3', [fileURLToPath(new URL('./sdk_verify.py', import.meta.url)), '--sdk', target, '--role', 'target']);
    console.log(`export CANGJIE_HOME=${shellQuote(target)}`);
    console.log(`export PATH=${shellQuote(`${target}/bin:${target}/tools/bin:${target}/third_party/llvm/bin`)}:$PATH`);
    console.log(`export LD_LIBRARY_PATH=${shellQuote(hostRuntime)}:${shellQuote(`${target}/third_party/llvm/lib:${target}/tools/lib`)}`);
    return;
  }
  if (args.includes('--help') || args.includes('-h')) {
    console.log('sdk_build.sh --plan FROZEN_JSON --to PRIVATE_SDK [--dry-run] [--resume-failed]\nThe component producer/config/dependency tuple belongs in the plan. Loose --from/--llvm-so/--std inputs are rejected.'); return;
  }
  if (args.some(arg => ['--from', '--llvm-so', '--llvm-tuple', '--runtime', '--std', '--cjc', '--cjpm', '--llc', '--opt', '--force'].includes(arg))) {
    reject('FROZEN_PLAN_REQUIRED', 'sdk', 'loose component/overwrite interface retired; supply the complete --plan before building');
  }
  const {values} = parseArgs({args, strict: true, options: {plan: {type: 'string'}, to: {type: 'string'}, out: {type: 'string'},
    'dry-run': {type: 'boolean', default: false}, 'resume-failed': {type: 'boolean', default: false}}});
  if (!values.plan || (!values.to && !values.out && !values['dry-run'])) reject('FROZEN_PLAN_REQUIRED', 'sdk', 'requires --plan and --to/--out');
  const result = await assembleSdk(await readJson(values.plan), values.to || values.out,
    {dryRun: values['dry-run'], resumeFailed: values['resume-failed']});
  console.log(JSON.stringify(result)); return result;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
