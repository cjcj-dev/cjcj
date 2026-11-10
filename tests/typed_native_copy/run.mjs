#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const [sdkArg, outputArg, cpus] = process.argv.slice(2);
assert(sdkArg && outputArg && cpus, 'usage: node run.mjs INSTALLED_SDK NEW_OUTPUT CPUS');
const sdk = path.resolve(sdkArg), out = path.resolve(outputArg);
const source = path.dirname(fileURLToPath(import.meta.url));
fs.mkdirSync(out);
for (const name of ['lib', 'temps']) fs.mkdirSync(path.join(out, name));
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const stage = JSON.parse(fs.readFileSync(path.join(sdk, 'STAGE-INPUTS.json')));
const compiler = path.join(sdk, 'bin/cjc');
assert.equal(hash(path.join(sdk, stage.compilerFile)), stage.compilerSha256);
const env = {...process.env, CANGJIE_HOME: sdk,
  CANGJIE_PATH: path.join(sdk, 'modules/linux_x86_64_cjnative'),
  LD_LIBRARY_PATH: ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
    'third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p)).join(':')};
const result = {compilerFile: stage.compilerFile, compilerSha256: stage.compilerSha256,
  runtimeSha256: hash(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so')),
  commands: [], ir: {before: {}, after: {}}, complete: false};
const save = () => fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(result, null, 2) + '\n');
function run(label, args) {
  const p = spawnSync('taskset', ['-c', cpus, ...args], {cwd: out, env, encoding: 'utf8', maxBuffer: 32*1024*1024});
  fs.writeFileSync(path.join(out, label+'.stdout'), p.stdout ?? '');
  fs.writeFileSync(path.join(out, label+'.stderr'), p.stderr ?? '');
  result.commands.push({label, args, rc: p.status, signal: p.signal, error: p.error?.message}); save();
  assert.equal(p.status, 0, label); return p.stdout;
}
run('producer', [compiler, '-O2', '-p', path.join(source, 'producer'), '--output-type=staticlib',
  '--output-dir', path.join(out, 'lib'), '--save-temps', path.join(out, 'temps')]);
run('consumer', [compiler, '-O2', path.join(source, 'main.cj'), '--import-path', path.join(out, 'lib'),
  '-L', path.join(out, 'lib'), '-ltyped_copy_values', '-o', path.join(out, 'consumer')]);
result.elfSha256 = hash(path.join(out, 'consumer'));
const stdout = run('assertions', [path.join(out, 'consumer')]);
assert(stdout.includes('TYPED_NATIVE_COPY_EXECUTED pair=true option=true'));
assert(stdout.includes('TYPED_REFERENCE_CONTROL_EXECUTED ok=true'));
for (const file of fs.readdirSync(path.join(out, 'temps')).filter(f => f.endsWith('.bc'))) {
  const text = run('decode-'+file, [path.join(sdk, 'third_party/llvm/bin/llvm-dis'), path.join(out, 'temps', file), '-o', '-']);
  const arm = file.endsWith('.opt.bc') ? result.ir.after : result.ir.before;
  for (const body of text.match(/^define[^\n]*\{\n[\s\S]*?^}/gm) ?? []) {
    for (const name of ['choosePair', 'chooseByte', 'referenceControl']) {
      if (body.split('\n')[0].includes(name)) {
        assert(!arm[name], 'unique '+name+' in '+file);
        arm[name] = {file, typedCopy: body.includes('@llvm.cj.copy.no.ref.struct'),
          hasAggType: body.includes('!AggType'), definition: body.split('\n')[0]};
      }
    }
  }
}
save();
for (const name of ['choosePair', 'chooseByte']) {
  assert(result.ir.before[name]?.typedCopy && result.ir.before[name]?.hasAggType, name+' reaches typed producer');
  assert(result.ir.after[name] && !result.ir.after[name].typedCopy, name+' reaches early lowering');
}
assert(result.ir.before.referenceControl && !result.ir.before.referenceControl.typedCopy, 'reference copy keeps its path');
result.complete = true; save(); console.log(JSON.stringify(result));
