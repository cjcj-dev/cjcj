import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const repo = path.resolve('.');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(fs.readFileSync(file));

// Only external release bytes and the final bootstrap child are fixtures. The
// complete srcbuild driver, acquire/store and manifest validator are unmodified.
function fixture(t, {depot = 'missing', corrupt = '', sumsMismatch = false} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fixed-release-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  for (const dir of ['tools', 'build', 'ci']) fs.cpSync(path.join(repo, dir), path.join(root, dir), {recursive: true});
  const pinPath = path.join(root, 'ci/llvm_pin.env');
  const pinText = fs.readFileSync(pinPath, 'utf8');
  const field = name => pinText.match(new RegExp(`^${name}=(.*)$`, 'm'))[1];
  const llvm = field('LLVM_SHA');
  const compiler = field('CANGJIE_COMPILER_SHA');
  const payload = path.join(root, 'release');
  const raw = Buffer.from(`LLVM fixture\0CJLLVM-COMMIT:${llvm}\0`);
  const gzip = spawnSync('gzip', ['-n', '-c'], {input: raw});
  assert.equal(gzip.status, 0);
  const shim = Buffer.from('shim fixture');
  const manifest = Buffer.from(`PLATFORM=linux_x86_64\nLLVM_SHA=${llvm}\nCANGJIE_COMPILER_SHA=${compiler}\nFLATBUFFERS_SHA=${field('FLATBUFFERS_SHA')}\nLLC_SHA256=${digest(raw)}\nOPT_SHA256=${digest(raw)}\nSHIM_SHA256=${digest(shim)}\n`);
  const files = {'MANIFEST': manifest, 'bin/llc': raw, 'bin/opt': raw, 'lib/STATIC_LLVM.txt': manifest,
    'fixed-llc/llc.gz': gzip.stdout, 'fixed-llc/opt.gz': gzip.stdout,
    'fixed-llc/cjselfhost_llvmshim.o': shim, 'fixed-llc/llvm-tools.manifest': manifest};
  files.SHA256SUMS = Buffer.from(Object.entries(files).map(([name, bytes]) => `${digest(bytes)}  ./${name}\n`).join(''));
  const pin = {version: 1, repository: 'cjcj-dev/cjcj', run: 123, attempt: 1, artifact: 456,
    commit: 'a'.repeat(40), files: Object.entries(files).map(([name, bytes], index) => ({path: name,
      mode: name.startsWith('bin/') ? 0o755 : 0o644, asset: index + 1,
      artifact_sha256: digest(bytes), release_sha256: digest(bytes)}))};
  for (const [name, bytes] of Object.entries(files)) {
    const file = path.join(payload, name);
    fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, bytes);
  }
  fs.writeFileSync(path.join(root, 'ci/bootstrap_inputs_pin.json'), JSON.stringify(pin));
  fs.writeFileSync(pinPath, pinText.replace(/^LLVM_TUPLE_SUMS_SHA=.*$/m,
    `LLVM_TUPLE_SUMS_SHA=${sumsMismatch ? '0'.repeat(64) : digest(files.SHA256SUMS)}`));
  const depotRoot = path.join(root, 'depot');
  if (depot !== 'missing') {
    const selected = path.join(depotRoot, llvm, compiler);
    fs.cpSync(payload, selected, {recursive: true});
    if (depot === 'mismatch') fs.appendFileSync(path.join(selected, 'SHA256SUMS'), '# changed\n');
  }
  if (corrupt) fs.appendFileSync(path.join(payload, corrupt), 'changed');
  const requests = path.join(root, 'requests');
  const preload = path.join(root, 'release-fetch.mjs');
  fs.writeFileSync(preload, `import fs from 'node:fs';\nconst pin=${JSON.stringify(pin)};\nglobalThis.fetch=async url=>{\nfs.appendFileSync(${JSON.stringify(requests)},url+'\\n');\nconst f=pin.files.find(f=>url==='https://api.github.com/repos/'+pin.repository+'/releases/assets/'+f.asset);\nreturn f ? new Response(fs.readFileSync(${JSON.stringify(payload)}+'/'+f.path)) : new Response('',{status:404});\n};\n`);
  const bin = path.join(root, 'fixture-bin'); fs.mkdirSync(bin);
  if (os.hostname().split('.')[0] !== 'kkk2') fs.writeFileSync(path.join(bin, 'hostname'), '#!/bin/sh\necho kkk2\n', {mode: 0o755});
  const child = path.join(root, 'bootstrap-child.sh');
  fs.writeFileSync(child, '#!/bin/bash\nprintf "ARG=<%s>\\n" "$@"\n', {mode: 0o755});
  const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, NODE_OPTIONS: `--import=${preload}`,
    CJCJ_LLVM_DEPOT_ROOT: depotRoot, CJCJ_BOOTSTRAP_SH: child,
    CJCJ_BOOTSTRAP_CPP_SRC: root, CJCJ_SRCBUILD_HOST_SDK: root,
    CJCJ_BOOTSTRAP_HOST_LLVM_SO: child, CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: hash(child),
    CJCJ_BOOTSTRAP_AST_SUPPORT: child, CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: hash(child)};
  for (const key of ['CJCJ_LLVM_DEPOT_PUBLISH', 'CJCJ_BOOTSTRAP_COLOUR_TUPLE', 'CJCJ_SELECTED_COLOUR_TUPLE',
    'CJCJ_BOOTSTRAP_INPUTS_PIN', 'CJCJ_SRCBUILD_CPUSET', 'CJCJ_KKK2_AFFINED']) delete env[key];
  const state = path.join(root, '.srcbuild'); fs.mkdirSync(state);
  fs.writeFileSync(path.join(state, 'kkk2-github.env'), ''); fs.writeFileSync(path.join(state, 'kkk2-github.path'), '');
  return {root, state, files, requests, run() {
    const result = spawnSync('bash', [path.join(root, 'tools/srcbuild_kkk2.sh'), '--from-step', '31', '--through-step', '31'], {env, encoding: 'utf8'});
    const logs = fs.readdirSync(path.join(state, 'logs')).map(name => [name, fs.readFileSync(path.join(state, 'logs', name), 'utf8')]);
    const log = result.stdout + result.stderr + logs.map(([n, v]) => `\n${n}\n${v}`).join('');
    if (process.env.CJCJ_TEST_EVIDENCE) {
      const out = path.join(process.env.CJCJ_TEST_EVIDENCE, t.name.replaceAll(/[^a-zA-Z0-9]+/g, '-'));
      fs.mkdirSync(out, {recursive: true});
      fs.writeFileSync(path.join(out, 'run.log'), log);
      fs.writeFileSync(path.join(out, 'run.rc'), `${result.status}\n`);
      fs.writeFileSync(path.join(out, 'identity.json'), JSON.stringify({driver: hash(path.join(root, 'tools/srcbuild_kkk2.sh')),
        acquire: hash(path.join(root, 'ci/release/acquire_fixed_tuple.mjs')), store: hash(path.join(root, 'ci/release/bootstrap_store.mjs'))}));
    }
    return {...result, log};
  }};
}

for (const depot of ['missing', 'mismatch', 'valid']) {
  test(`fixed release ${depot} depot delivers pinned bytes to both consumers`, t => {
    const f = fixture(t, {depot});
    const result = f.run();
    const dest = path.join(f.state, 'fixed-llc/opt.gz');
    // Nonfatal existence handling keeps the target value assertion observable.
    const actual = fs.existsSync(dest) ? hash(dest) : 'MISSING';
    console.log(`ASSERT fixed-tool-bytes depot=${depot} actual=${actual} driver_rc=${result.status}`);
    assert.equal(actual, digest(f.files['fixed-llc/opt.gz']), result.log);
    const match = result.log.match(/ARG=<--colour-tuple>\nARG=<([^>]+)>/);
    const selected = match?.[1];
    const colourSums = selected && fs.existsSync(path.join(selected, 'SHA256SUMS')) ? hash(path.join(selected, 'SHA256SUMS')) : 'MISSING';
    console.log(`ASSERT bootstrap-tuple-bytes depot=${depot} actual=${colourSums}`);
    assert.equal(colourSums, digest(f.files.SHA256SUMS), result.log);
    assert.equal(result.status, 0, result.log);
    assert.doesNotMatch(result.log, /source mirror required|CMake Error/);
    if (depot === 'valid') assert.equal(fs.existsSync(f.requests), false);
    else assert.equal(fs.readFileSync(f.requests, 'utf8').trim().split('\n').length, 9);
    const again = f.run();
    assert.equal(again.status, 0, again.log);
    if (depot !== 'valid') assert.match(again.log, /reusing it/);
  });
}
for (const kind of ['asset', 'sums']) {
  test(`fixed release rejects ${kind} corruption before consumer publication`, t => {
    const f = fixture(t, kind === 'asset' ? {corrupt: 'bin/opt'} : {sumsMismatch: true});
    const result = f.run();
    assert.equal(result.status, 1, result.log);
    assert.match(result.log, kind === 'asset' ? /bootstrap digest mismatch: bin\/opt/ : /bootstrap digest mismatch: LLVM_TUPLE_SUMS_SHA/);
    assert.equal(fs.existsSync(path.join(f.state, 'colour-tuple')), false);
    assert.equal(fs.existsSync(path.join(f.state, 'fixed-llc/opt.gz')), false);
    assert.doesNotMatch(result.log, /source mirror required|ARG=<--colour-tuple>/);
    console.log(`ASSERT rejected-${kind} driver_rc=${result.status}`);
  });
}
