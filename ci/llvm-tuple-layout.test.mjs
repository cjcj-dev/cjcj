import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {gzipSync} from 'node:zlib';
import {exportBranches} from './llvm-tuple-branches.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const source = fs.readFileSync(new URL('./fixtures/llvm-tuple-layout-baseline.txt', import.meta.url), 'utf8');
const rows = exportBranches(source);
const product = path.join(repo, 'ci/llvm-tuple-layout.mjs');
function command(argv, options = {}) {
  const result = spawnSync(argv[0], argv.slice(1), {encoding: 'utf8', maxBuffer: 8e6, ...options});
  assert.ifError(result.error); assert.equal(result.signal, null);
  return result;
}
function fixture(root) {
  fs.mkdirSync(root, {recursive: true});
  const fixed = path.join(root, 'fixed'), git = path.join(root, 'recipe');
  fs.mkdirSync(fixed); fs.mkdirSync(git);
  for (const payload of ['llc', 'opt', 'ld.lld']) fs.writeFileSync(path.join(fixed, `${payload}.gz`), gzipSync(Buffer.from(`fixture ${payload}\n`)));
  for (const payload of ['cjselfhost_llvmshim.o', 'llvm-tools.manifest']) fs.writeFileSync(path.join(fixed, payload), `fixture ${payload}\n`);
  for (const argv of [['git', '-C', git, 'init', '-q'], ['git', '-C', git, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '--allow-empty', '-qm', 'tuple fixture']]) {
    const result = command(argv); assert.equal(result.status, 0, result.stderr);
  }
  return {LLVM_SHA: 'llvm-fixture', CANGJIE_COMPILER_SHA: 'compiler-fixture', REPO_ROOT: git, CJCJ_FIXED_LLVM_DIR: fixed};
}

test('tuple source exporter loses only the deleted real identity guard', () => {
  const guard = rows.find(row => row.kind === 'guard:identities');
  assert.ok(guard);
  const cut = exportBranches(source.replace(guard.source + '\n', ''));
  // Line numbers below the cut move by one; every other source/trigger is identical.
  const decisions = list => list.map(({line, ...row}) => row);
  assert.deepEqual(decisions(cut), decisions(rows.filter(row => row !== guard)));
  assert.equal(cut.length, rows.length - 1);
  console.log(`ASSERT SOURCE_DELETE_GUARD executed rows=${rows.length} cut=${cut.length}`);
});
test('tuple source exporter rejects a previously unknown decision', () => {
  assert.throws(() => exportBranches(source.replace('    echo ', '    [[ -f unknown ]] || return 1\n    echo ')), /unsupported guard/);
});
test('real tuple publisher emits all ten checksummed consumer payloads', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-publisher-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const env = {...process.env, ...fixture(root), LC_ALL: 'C'};
  const depot = path.join(root, "depot with spaces ' $ é");
  const result = command(['npx', '--yes', 'zx@8', product, depot], {env});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `published fixed LLVM tuple to depot ${depot}/${env.LLVM_SHA}/${env.CANGJIE_COMPILER_SHA}\n`);
  const tuple = path.join(depot, env.LLVM_SHA, env.CANGJIE_COMPILER_SHA);
  const checked = command(['sha256sum', '--strict', '-c', 'SHA256SUMS'], {cwd: tuple});
  assert.equal(checked.status, 0, checked.stderr);
  assert.equal(checked.stdout.trim().split('\n').length, 10);
  assert.deepEqual(fs.readFileSync(path.join(tuple, 'bin/llc')), Buffer.from('fixture llc\n'));
  assert.deepEqual(fs.readFileSync(path.join(tuple, 'MANIFEST')), fs.readFileSync(path.join(tuple, 'lib/STATIC_LLVM.txt')));
  console.log('ASSERT TEN_PAYLOADS executed count=10 byte-preserving=1');
});

// A finite, opt-in whole-table run. Ordinary CI executes the assertions above.
if (process.env.TUPLE_DIFFERENTIAL === '1') test('tuple source-derived full table matches retired publisher', () => {
  const evidence = process.env.TUPLE_EVIDENCE;
  assert.ok(evidence); fs.mkdirSync(evidence, {recursive: true});
  fs.writeFileSync(path.join(evidence, 'branches.json'), JSON.stringify(rows, null, 2));
  const entries = rows.flatMap(row => row.inputs.map((input, i) => ({branch: row.kind, line: row.line, trigger: i, input})));
  const results = [];
  for (const [index, entry] of entries.entries()) {
    const work = path.join(evidence, `input-${index}`), root = path.join(work, 'fixture');
    fs.mkdirSync(work);
    const identity = fixture(root);
    const nongit = path.join(root, 'nongit'), missing = path.join(root, 'missing'), unborn = path.join(root, 'unborn');
    fs.mkdirSync(nongit); fs.mkdirSync(unborn);
    assert.equal(command(['git', '-C', unborn, 'init', '-q']).status, 0);
    const replacements = {$DEPOT: path.join(root, 'depot'), $ARG: path.join(root, "explicit depot ' $ é"), $NONGIT: nongit, $MISSING: missing, $UNBORN: unborn};
    const input = entry.input;
    if (input.fixture === 'missing-payload') fs.unlinkSync(path.join(identity.CJCJ_FIXED_LLVM_DIR, input.payload));
    if (input.fixture === 'corrupt-gzip') fs.writeFileSync(path.join(identity.CJCJ_FIXED_LLVM_DIR, `${input.payload}.gz`), 'not gzip\n');
    const env = {...process.env, ...identity, LC_ALL: 'C'};
    delete env.CJCJ_LLVM_DEPOT_ROOT;
    delete env.BASH_ENV;
    const expand = value => replacements[value] || value;
    for (const [key, value] of Object.entries(input.env || {})) {
      if (value === null) delete env[key]; else env[key] = expand(value);
    }
    const args = (input.args || ['$DEPOT']).map(expand);
    const depotRoot = args[0] || env.CJCJ_LLVM_DEPOT_ROOT || '/root/llvmdepot';
    const tuple = `${depotRoot}/${env.LLVM_SHA || ''}/${env.CANGJIE_COMPILER_SHA || ''}`;
    const old = path.join(work, 'retired-entry.bash');
    fs.writeFileSync(old, 'set -e\n' + source + '\npublish_fixed_tuple_to_depot "$@"\n');
    const tools = ['git', 'mkdir', 'cp', 'gzip', 'chmod', 'sha256sum'];
    const real = Object.fromEntries(tools.map(tool => [tool, command(['bash', '-c', 'command -v "$1"', 'resolve-tool', tool]).stdout.trim()]));
    const bin = path.join(work, 'bin'); fs.mkdirSync(bin);
    if (input.fail && !['cd', 'printf', 'echo'].includes(input.fail.command)) {
      const tool = input.fail.command, state = path.join(work, 'counter');
      const trace = path.join(work, 'argv.json');
      const wrapper = `#!/usr/bin/env node\nimport fs from 'node:fs';\nimport {spawnSync} from 'node:child_process';\nconst state = ${JSON.stringify(state)};\nconst n = fs.existsSync(state) ? Number(fs.readFileSync(state, 'utf8')) + 1 : 1;\nfs.writeFileSync(state, String(n));\nif (n === ${input.fail.occurrence}) {\nfs.writeFileSync(${JSON.stringify(trace)}, JSON.stringify(process.argv.slice(2)));\nconsole.error(${JSON.stringify(`fixture command error: ${tool}`)}); process.exit(19);\n}\nconst result = spawnSync(${JSON.stringify(real[tool])}, process.argv.slice(2), {stdio: 'inherit'});\nif (result.error) throw result.error; process.exit(result.status);\n`;
      fs.writeFileSync(path.join(bin, tool), wrapper, {mode: 0o755});
      env.PATH = `${bin}:${env.PATH}`;
    }
    if (['cd', 'printf', 'echo'].includes(input.fail?.command)) {
      const bashEnv = path.join(work, 'bash-env');
      if (input.fail.command === 'cd') fs.writeFileSync(bashEnv, "cd() { printf '%s\\n' 'fixture command error: cd' >&2; return 19; }\n");
      else if (input.fail.command === 'printf') {
        const state = path.join(work, 'printf-counter');
        fs.writeFileSync(bashEnv, `printf() { local count=0; if [[ -f '${state}' ]]; then read -r count < '${state}' || :; fi; count=$((count + 1)); builtin printf '%s\\n' "$count" > '${state}'; if [[ $count == ${input.fail.occurrence} ]]; then builtin printf '%s\\n' 'fixture command error: printf' >&2; return 19; fi; builtin printf "$@"; }\n`);
      } else fs.writeFileSync(bashEnv, "echo() { builtin printf '%s\\n' 'fixture command error: echo' >&2; return 19; }\n");
      env.BASH_ENV = bashEnv;
    }
    const prepare = () => {
      if (depotRoot !== '/root/llvmdepot') fs.rmSync(depotRoot, {recursive: true, force: true});
      fs.rmSync(path.join(work, 'counter'), {force: true});
      fs.rmSync(path.join(work, 'printf-counter'), {force: true});
      fs.rmSync(path.join(work, 'argv.json'), {force: true});
      if (input.fixture === 'manifest-directory' || input.fixture === 'sums-directory') {
        fs.mkdirSync(path.join(tuple, input.fixture === 'manifest-directory' ? 'MANIFEST' : 'SHA256SUMS'), {recursive: true});
      }
      if (input.fixture === 'depot-file') fs.writeFileSync(depotRoot, 'obstructed depot\n');
    };
    // Strip only shell source locations from redirect errors; keep all command
    // diagnostics and all stdout. Both entries use exactly the same fixture paths.
    const normalize = text => text.replace(/^(?:[^\n]*: line \d+: )/gm, '');
    const arms = {};
    for (const [name, argv] of [['old', ['bash', old, ...args]], ['new', ['npx', '--yes', 'zx@8', product, ...args]]]) {
      prepare();
      const result = command(argv, {env, cwd: identity.REPO_ROOT});
      fs.writeFileSync(path.join(work, `${name}.stdout`), result.stdout);
      fs.writeFileSync(path.join(work, `${name}.stderr`), result.stderr);
      const trace = fs.existsSync(path.join(work, 'argv.json')) ? JSON.parse(fs.readFileSync(path.join(work, 'argv.json'), 'utf8')) : null;
      const sums = result.status === 0 ? fs.readFileSync(path.join(tuple, 'SHA256SUMS'), 'utf8') : null;
      arms[name] = {rc: result.status, stdout: normalize(result.stdout), stderr: normalize(result.stderr), trace, sums};
      fs.writeFileSync(path.join(work, `${name}.json`), JSON.stringify(arms[name], null, 2));
      // A green comparison without an observed fault is not a positive control.
      if (input.fail) assert.match(arms[name].stderr, new RegExp(`fixture command error: ${input.fail.command}`), `${name} must execute injected ${input.fail.command}`);
    }
    results.push({...entry, arms});
    fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(results, null, 2));
    assert.deepEqual(arms.new, arms.old, `branch ${entry.branch}:${entry.line} trigger ${entry.trigger}`);
    assert.equal(arms.new.rc, input.expected, `expected branch ${entry.branch}:${entry.line}`);
    console.log(`ASSERT TABLE_ROW executed index=${index} branch=${entry.branch}:${entry.line} trigger=${entry.trigger} rc=${arms.new.rc}`);
  }
  console.log(`ASSERT FULL_TABLE executed inputs=${results.length} branches=${rows.length}`);
});
