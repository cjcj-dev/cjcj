import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {exportBranches} from './abi-branches.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const oldName = 'ci/check-llvm-runtime-abi.' + 'sh';
function command(args, options = {}) {
  const result = spawnSync(args[0], args.slice(1), {encoding: 'utf8', maxBuffer: 8e6, ...options});
  assert.ifError(result.error);
  return result;
}
function oldSource() {
  // Byte-for-byte retired source at b597f8618c6c2c555c9c23b57be3fc83c2e225e9.
  // A data fixture keeps mechanical export available in depth-one CI checkouts.
  return fs.readFileSync(new URL('./fixtures/llvm-runtime-abi-baseline.txt', import.meta.url), 'utf8');
}
const source = oldSource();
const rows = exportBranches(source);
test('ABI branch exporter loses exactly one row when a source case arm is deleted', () => {
  const row = rows.find(row => row.kind === 'case:value');
  const cut = exportBranches(source.replace(row.source, ''));
  assert.equal(cut.length, rows.length - 1);
  assert.ok(!cut.some(other => other.source === row.source));
});
test('ABI migrated real entry rejects non-whitelisted arguments with exit 2', () => {
  const result = command(['npx', '--yes', 'zx@8', path.join(root, 'ci/check-llvm-runtime-abi.mjs'), '--llvm-refs']);
  assert.equal(result.status, 2, result.stderr);
  assert.match(result.stderr, /ABI_PAIR=INVALID_ARGUMENT argument=--llvm-refs/);
  console.log('ASSERT ABI whitelist exit=2 executed');
});
// The full differential table is an explicit finite invocation, never an
// implicit full-suite experiment. The normal suite runs the targeted regressions.
if (process.env.ABI_DIFFERENTIAL === '1') test('ABI full source-derived decision table matches old entry', () => {
  const evidence = process.env.ABI_EVIDENCE;
  assert.ok(evidence); fs.mkdirSync(evidence, {recursive: true});
  fs.writeFileSync(path.join(evidence, 'branches.json'), JSON.stringify(rows, null, 2));
  const product = path.join(evidence, 'product');
  fs.mkdirSync(path.join(product, 'ci'), {recursive: true});
  for (const name of ['check-llvm-runtime-abi.mjs', 'generate-codegen-runtime-layout.py', 'llvm_pin.env', 'runtime_pin.env']) {
    fs.copyFileSync(path.join(root, 'ci', name), path.join(product, 'ci', name));
  }
  const old = path.join(product, oldName); fs.writeFileSync(old, source);
  function commit(dir, files) {
    fs.mkdirSync(dir, {recursive: true});
    for (const [name, text] of Object.entries(files)) {
      fs.mkdirSync(path.dirname(path.join(dir, name)), {recursive: true}); fs.writeFileSync(path.join(dir, name), text);
    }
    for (const args of [['init', '-q'], ['add', '.'], ['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'test fixture']]) {
      const result = command(['git', '-C', dir, ...args]); assert.equal(result.status, 0, result.stderr);
    }
    return dir;
  }
  // Real Git archive/show and the real codegen consumer. Only the external
  // runtime generator fixture is synthetic; no runtime behavior is claimed.
  const layout = fs.readFileSync(path.join(root, 'packages/codegen/src/RuntimeLayout.cj'), 'utf8');
  const fields = [...layout.matchAll(/    public static let (\w+): (?:Int64|UInt64) = (\d+)(?:u64)?\n/g)];
  const globals = ['ObjectHeaderSize', 'ArrayLengthOffset', 'ArrayHeaderSize', 'TypeInfoSize'];
  let header = fields.filter(([ , name]) => globals.includes(name))
    .map(([ , name, value]) => `constexpr unsigned ${name} = ${value};`).join('\n');
  header += '\nnamespace TypeInfo {\n' + fields.filter(([ , name]) => /^[a-z].*(?:Index|Offset)$/.test(name))
    .map(([ , name, value]) => `constexpr unsigned ${name} = ${value};`).join('\n') + '\n} // namespace TypeInfo\n';
  const llvm = commit(path.join(evidence, 'llvm'), {'llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h': header});
  const runtime = commit(path.join(evidence, 'runtime'), {'runtime/tools/generate-runtime-layout.py': "import sys\nprint('RUNTIME_FIXTURE=OK')\n"});
  const empty = commit(path.join(evidence, 'empty'), {'unrelated': 'empty'});
  const mismatch = commit(path.join(evidence, 'mismatch'), {'runtime/tools/generate-runtime-layout.py': "import sys\nprint('RUNTIME_FIXTURE=MISMATCH')\nsys.exit(1)\n"});
  fs.mkdirSync(path.join(product, 'packages/codegen/src'), {recursive: true});
  const rendered = command(['python3', path.join(product, 'ci/generate-codegen-runtime-layout.py'), '--runtime-root', runtime, '--write',
    '--header', path.join(llvm, 'llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h'), '--output', path.join(product, 'packages/codegen/src/RuntimeLayout.cj')]);
  assert.equal(rendered.status, 0, rendered.stderr);
  const output = path.join(product, 'packages/codegen/src/RuntimeLayout.cj');
  const validOutput = fs.readFileSync(output);
  const base = {llvm_repo: llvm, llvm_ref: 'HEAD', runtime_repo: runtime, runtime_ref: 'HEAD'};
  const argv = values => Object.entries(values).flatMap(([key, value]) => ['--' + key.replaceAll('_', '-'), value]);
  const records = [];
  for (const row of rows) for (const trigger of row.triggers) {
    let values = {...base}, args, env = {...process.env}; delete env.TMPDIR;
    fs.writeFileSync(output, validOutput);
    if (row.kind.startsWith('case:') || trigger.args) {
      args = trigger.args;
      if (trigger.key) {
        if (trigger.target === 'duplicate_last_empty') args = [...argv(values), ...args];
        else { values[trigger.key] = args[1]; args = argv(values); }
      }
    } else if (trigger.omit) { delete values[trigger.omit]; args = argv(values); }
    else {
      if (trigger.mode === 'bad-ref') values[`${trigger.side}_ref`] = 'not-a-ref';
      if (trigger.mode === 'bad-repo') values[`${trigger.side}_repo`] = path.join(evidence, 'absent');
      if (trigger.mode === 'SOURCE_ERROR') values[`${trigger.side}_repo`] = empty;
      if (trigger.mode === 'MISMATCH') values.runtime_repo = mismatch;
      if (trigger.mode === 'CODEGEN_MISMATCH') fs.writeFileSync(output, 'stale\n');
      if (trigger.tmp === 'invalid') env.TMPDIR = path.join(evidence, 'absent');
      if (trigger.tmp === '') env.TMPDIR = '';
      if (trigger.tmp === 'valid') env.TMPDIR = evidence;
      args = argv(values);
    }
    const before = command(['bash', old, ...args], {env});
    const after = command(['npx', '--yes', 'zx@8', path.join(product, 'ci/check-llvm-runtime-abi.mjs'), ...args], {env});
    const normalize = text => text.replaceAll('check-llvm-runtime-abi.' + 'sh', 'check-llvm-runtime-abi.mjs')
      .replace(/cjcj-runtime-layout\.[A-Za-z0-9]+/g, 'cjcj-runtime-layout.TEMP');
    const record = {line: row.line, kind: row.kind, trigger, args, old: {rc: before.status, stdout: before.stdout, stderr: before.stderr}, candidate: {rc: after.status, stdout: after.stdout, stderr: after.stderr}};
    records.push(record); fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(records, null, 2));
    assert.deepEqual([after.status, normalize(after.stdout), normalize(after.stderr)], [before.status, normalize(before.stdout), normalize(before.stderr)], JSON.stringify(record));
    console.log(`ASSERT ABI branch line=${row.line} trigger=${JSON.stringify(trigger)} rc=${after.status} executed`);
  }
});
