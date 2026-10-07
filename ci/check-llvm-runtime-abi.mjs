#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const entryIndex = process.argv.findIndex((arg, i) => i > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
const cliArgs = process.argv.slice(entryIndex + 1);
async function capture(command) {
  return await $({nothrow: true, quiet: true})`${command}`;
}
async function run(command) {
  const result = await capture(command);
  process.stdout.write(result.stdout); process.stderr.write(result.stderr);
  return result;
}
const usage = 'usage: check-llvm-runtime-abi.mjs \\\n  --llvm-repo PATH --llvm-ref REF \\\n  --runtime-repo PATH --runtime-ref REF\n';
const values = {};
const keys = ['llvm_repo', 'llvm_ref', 'runtime_repo', 'runtime_ref'];
const args = cliArgs.slice();
for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === '-h' || arg === '--help') { process.stdout.write(usage); process.exit(0); }
  if (!keys.some(key => arg === `--${key.replaceAll('_', '-')}`)) {
    const quoted = await capture(['bash', '-c', 'printf "%q" "$1"', 'abi-argument', arg]);
    console.error(`ABI_PAIR=INVALID_ARGUMENT argument=${quoted.stdout}`);
    process.stderr.write(usage); process.exit(2);
  }
  const key = arg.slice(2).replaceAll('-', '_');
  if (!args[i + 1]) { console.error(`ABI_PAIR=INVALID_ARGUMENT missing_value=${arg}`); process.exit(2); }
  values[key] = args[++i];
}
for (const key of keys) if (!values[key]) { console.error(`ABI_PAIR=INVALID_ARGUMENT missing=${key}`); process.exit(2); }
const commits = {};
for (const side of ['llvm', 'runtime']) {
  const result = await capture(['git', '-C', values[`${side}_repo`], 'rev-parse', '--verify', `${values[`${side}_ref`]}^{commit}`], {check: false});
  if (result.exitCode !== 0) { console.log(`ABI_PAIR=UNRESOLVABLE side=${side} ref=${values[`${side}_ref`]}`); process.exit(2); }
  commits[side] = result.stdout.replace(/\n+$/, '');
}
const temporary = await capture(['mktemp', '-d', `${process.env.TMPDIR || '/tmp'}/cjcj-runtime-layout.XXXXXX`]);
process.stderr.write(temporary.stderr);
if (temporary.exitCode !== 0) process.exit(2);
const work = temporary.stdout.replace(/\n+$/, '');
try {
  const extract = await $({nothrow: true, quiet: true})`git -C ${values.runtime_repo} archive ${commits.runtime} runtime | tar -x -C ${work}`;
  process.stdout.write(extract.stdout); process.stderr.write(extract.stderr);
  if (extract.exitCode !== 0) { console.log('ABI_PAIR=SOURCE_ERROR side=runtime'); process.exitCode = 2; }
  else {
    const header = path.join(work, 'CangjieRuntimeLayout.h');
    const source = await capture(['git', '-C', values.llvm_repo, 'show', `${commits.llvm}:llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h`], {check: false});
    if (source.exitCode !== 0) { process.stderr.write(source.stderr); console.log('ABI_PAIR=SOURCE_ERROR side=llvm'); process.exitCode = 2; }
    else {
      fs.writeFileSync(header, source.stdout);
      const generated = await run(['python3', path.join(work, 'runtime/tools/generate-runtime-layout.py'), '--header', header], {check: false});
      if (generated.exitCode !== 0) { console.log(`ABI_PAIR=MISMATCH llvm=${commits.llvm} runtime=${commits.runtime}`); process.exitCode = 1; }
      else {
        const codegen = await run(['python3', path.join(repo, 'ci/generate-codegen-runtime-layout.py'), '--runtime-root', work, '--header', header, '--check'], {check: false});
        console.log(`ABI_PAIR=${codegen.exitCode === 0 ? 'OK' : 'CODEGEN_MISMATCH'} llvm=${commits.llvm} runtime=${commits.runtime}`);
        process.exitCode = codegen.exitCode === 0 ? 0 : 1;
      }
    }
  }
} finally { fs.rmSync(work, {recursive: true, force: true}); }
