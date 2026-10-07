#!/usr/bin/env zx
// Execute the actual gha_run entry; absent SDK inputs deliberately stop later.
// This asserts host admission only, never compiler or SDK success.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [outArg, base, expected] = process.argv.slice(2);
if (!outArg || !/^[0-9a-f]{40}$/.test(base || '')
    || !/^(linux|darwin)_(x86_64|aarch64)_cjnative$/.test(expected || '')) {
  throw new Error('usage: test_host_route.mjs ABSOLUTE_OUT BASE_SHA EXPECTED_NATIVE_TUPLE');
}
if (!path.isAbsolute(outArg)) throw new Error('absolute evidence directory required');
const out = path.resolve(outArg);
fs.mkdirSync(out, {recursive: true});
const sha = (await $`git -C ${root} rev-parse HEAD`.quiet()).stdout.trim();
const rel = 'ci/bootstrap/bootstrap.sh';
const original = fs.readFileSync(path.join(root, rel), 'utf8');
const baseline = (await $`git -C ${root} show ${`${base}:${rel}`}`.quiet()).stdout;
const cut = original.replace(/^  host_tuple_init$/m, '  : # route control: disconnect the real main consumer');
if (cut === original || (original.match(/^  host_tuple_init$/gm) || []).length !== 1) {
  throw new Error('unique bearing main call required');
}
const hash = content => crypto.createHash('sha256').update(content).digest('hex');
const source = path.join(out, 'source');
await $`git -C ${root} worktree add --detach ${source} ${sha}`.quiet();
const absent = path.join(out, 'absent-inputs');
if (fs.existsSync(absent)) throw new Error('SDK inputs must be absent in the host-admission fixture');
const zero = '0'.repeat(64);
// The source path, Git identity, pin, fixture bytes and all other scripts stay
// identical across arms. Only the bootstrap carrier is replaced, sequentially.
const env = {...process.env,
  GITHUB_WORKSPACE: source, CANGJIE_WORKSPACE: absent,
  CJCJ_BOOTSTRAP_BASE: `${absent}/base`,
  CJCJ_BOOTSTRAP_HOST_LLVM_SO: `${absent}/host-llvm`, CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: zero,
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SO: `${absent}/colour-llvm`, CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256: zero,
  CJCJ_BOOTSTRAP_AST_SUPPORT: `${absent}/ast`, CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: zero,
  CJCJ_BOOTSTRAP_COLOUR_TUPLE: `${absent}/tuple`, CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA: sha,
  CJCJ_BOOTSTRAP_COLOUR_RT: `${absent}/colour-runtime`, CJCJ_BOOTSTRAP_HOST_RT: `${absent}/host-runtime`,
  CJCJ_BOOTSTRAP_CPP_SRC: `${absent}/cpp`, CJCJ_BOOTSTRAP_CJCJ_SHA: sha,
  CJCJ_BOOTSTRAP_RUNTIME_PIN: path.join(source, 'ci/runtime_pin.env'),
};
const fixtureHash = hash(JSON.stringify(env));
const nonCarriers = ['ci/bootstrap/gha_run.sh', 'ci/bootstrap/host_tools.mjs',
  'ci/runtime_pin.env', 'ci/runtime-pin.mjs', 'build/lib/targets.mjs', 'build/lib/errors.mjs'];
const results = {};
try {
  for (const [arm, content] of Object.entries({baseline, candidate: original, cut, restored: original})) {
    const evidence = path.join(out, arm);
    fs.mkdirSync(evidence);
    fs.writeFileSync(path.join(source, rel), content);
    if (arm === 'cut') {
      const diff = (await $`git -C ${source} diff -- ${rel}`.quiet()).stdout;
      fs.writeFileSync(path.join(out, 'cut.diff'), diff);
    }
    fs.writeFileSync(path.join(evidence, 'bootstrap.sh'), content);
    const host = spawnSync('uname', ['-sm'], {encoding: 'utf8'});
    if (host.error || host.status !== 0) throw new Error('native uname failed');
    fs.writeFileSync(path.join(evidence, 'host.txt'), host.stdout);
    const started = process.hrtime.bigint();
    const run = spawnSync('bash', [path.join(source, 'ci/bootstrap/gha_run.sh'), 'stage0'],
      {env, encoding: 'utf8', timeout: 120000, maxBuffer: 4 * 1024 * 1024});
    fs.writeFileSync(path.join(evidence, 'entry.log'), (run.stdout || '') + (run.stderr || ''));
    const entryRc = run.status;
    fs.writeFileSync(path.join(evidence, 'entry.rc'), `${entryRc === null ? 'NOT_EXITED' : entryRc}\n`);
    if (run.error || entryRc === null) throw new Error(`entry executor failure: ${run.error}`);
    const output = run.stdout + run.stderr;
    const observed = [...output.matchAll(/^HOST-TUPLE ([^ ]+) .+$/gm)].map(match => match[1]);
    const passed = observed.length === 1 && observed[0] === expected;
    const assertion = `ASSERT native-host-route expected=${expected} observed=${observed.join(',') || 'missing'} entry_rc=${entryRc}\n`;
    fs.writeFileSync(path.join(evidence, 'assertion.log'), assertion + `${passed ? 'PASS' : 'FAIL'} native-host-route\n`);
    const expectedRc = arm === 'cut' || (arm === 'baseline' && expected.startsWith('darwin_')) ? 1 : 0;
    const record = {entry_rc: entryRc, assertion_rc: passed ? 0 : 1, expected_rc: expectedRc,
      assertions: 1, observed, target_assertion: true, carrier_sha256: hash(content),
      fixture_sha256: fixtureHash, wall: Number(process.hrtime.bigint() - started) / 1e9,
      noncarriers: Object.fromEntries(nonCarriers.map(file => [file, hash(fs.readFileSync(path.join(source, file)))]))};
    results[arm] = record;
    fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify(results, null, 2) + '\n');
    console.log(`${arm}: ${assertion.trim()} assertion_rc=${record.assertion_rc}`);
    if (record.assertion_rc !== expectedRc) throw new Error(`first unexpected route result: ${arm}; stop dependent arms`);
    if (arm === 'baseline' && expected.startsWith('darwin_')
        && !output.includes('is not supported by bootstrap.sh')) {
      throw new Error('baseline failed before the expected host refusal; stop dependent arms');
    }
  }
} finally {
  fs.writeFileSync(path.join(source, rel), original);
  await $`git -C ${root} worktree remove ${source}`.quiet();
}
if (results.candidate.carrier_sha256 !== results.restored.carrier_sha256
    || results.cut.carrier_sha256 === results.candidate.carrier_sha256
    || Object.values(results).some(record => record.fixture_sha256 !== fixtureHash
      || JSON.stringify(record.noncarriers) !== JSON.stringify(results.candidate.noncarriers))) {
  throw new Error('arm identity mismatch');
}
