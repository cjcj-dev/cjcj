#!/usr/bin/env zx
// Finite srcbuild CLI -> real tuple acquisition -> copied fixed-tool bytes.
// These payloads are transport fixtures, not LLVM/compiler/SDK qualification.
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {fs, path, assert, repo, run, capture, diff, equalFiles, cleanupOnSignals} from './entry-common.mjs';

const self = fileURLToPath(import.meta.url);
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function observe(product, manifest) {
  const expected = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  const observed = Object.fromEntries(Object.keys(expected).map(name => {
    const file = path.join(product, '.srcbuild/fixed-llc', name);
    return [name, fs.existsSync(file) ? digest(fs.readFileSync(file)) : null];
  }));
  console.log(`ACQUIRE_TARGET_ASSERT_REACHED ${JSON.stringify(observed)}`);
  assert.deepEqual(observed, expected, 'srcbuild must publish the five verified fixed-tool payloads');
}

export async function acquireControl(work) {
  fs.mkdirSync(work);
  // Execute and cut the actual private product entry. Only its output state
  // is redirected to the admitted data volume, never a test-only source copy.
  const product = repo;
  const state = path.join(product, '.srcbuild');
  assert(!fs.existsSync(state), 'srcbuild output state must be absent before the isolated control');
  const files = ['tools/srcbuild_kkk2.sh', 'build/lib/srcbuild_git.sh',
    'build/lib/targets.mjs', 'build/lib/errors.mjs', 'ci/host_sdk_pin.env',
    'ci/srcbuild/steps/assert-host-contract.mjs', 'ci/llvm_pin.env',
    'ci/release/acquire_fixed_tuple.mjs', 'ci/release/bootstrap_tuple.mjs',
    'ci/release/bootstrap_store.mjs'];
  const identities = {};
  for (const file of files) {
    const bytes = fs.readFileSync(path.join(repo, file));
    identities[file] = digest(bytes);
  }
  fs.writeFileSync(path.join(work, 'source-identities.json'), JSON.stringify(identities, null, 2));
  const depot = path.join(work, 'depot');
  const payloads = ['llc.gz', 'opt.gz', 'ld.lld.gz', 'cjselfhost_llvmshim.o', 'llvm-tools.manifest'];
  fs.mkdirSync(path.join(depot, 'fixed-llc'), {recursive: true});
  const expected = {};
  for (const name of payloads) {
    const bytes = Buffer.from(`G1 transport fixture: ${name}\n`);
    fs.writeFileSync(path.join(depot, 'fixed-llc', name), bytes);
    expected[name] = digest(bytes);
  }
  const sums = payloads.map(name => `${expected[name]}  ./fixed-llc/${name}\n`).join('');
  fs.writeFileSync(path.join(depot, 'SHA256SUMS'), sums);
  const pin = {version: 1, repository: 'cjcj-dev/cjcj', run: 1, attempt: 1, artifact: 1,
    commit: 'b'.repeat(40), files: ['SHA256SUMS', ...payloads.map(name => `fixed-llc/${name}`)].map(file => {
      const sha = digest(fs.readFileSync(path.join(depot, file)));
      return {path: file, mode: 0o644, asset: 1, artifact_sha256: sha, release_sha256: sha};
    })};
  const pinFile = path.join(work, 'pin.json'), manifest = path.join(work, 'expected.json');
  fs.writeFileSync(pinFile, JSON.stringify(pin, null, 2));
  fs.writeFileSync(manifest, JSON.stringify(expected, null, 2));
  const environment = {...process.env, CJCJ_BOOTSTRAP_SOURCE: 'depot',
    CJCJ_BOOTSTRAP_SOURCE_REASON: 'G1 finite acquisition fixture; no LLVM execution',
    CJCJ_BOOTSTRAP_INPUTS_PIN: pinFile, CJCJ_BOOTSTRAP_COLOUR_TUPLE: depot,
    LLVM_TUPLE_SUMS_SHA: digest(Buffer.from(sums))};
  const driver = path.join(product, 'tools/srcbuild_kkk2.sh');
  const clean = await capture(['git', '-C', product, 'status', '--porcelain', '--', 'tools/srcbuild_kkk2.sh']);
  assert.equal(clean.stdout, '', 'srcbuild product entry must be clean before the isolated control');
  const original = fs.readFileSync(driver);
  fs.writeFileSync(path.join(work, 'srcbuild.saved'), original);
  const command = ['bash', driver, '--from-step', '2', '--through-step', '2', '--jobs', '8'];
  const records = [];
  async function arm(name, expectedRc) {
    // Fresh output makes a skipped acquisition observable even after a green
    // arm; the real driver still creates its own directories and runs step 2.
    for (const directory of ['colour-tuple', 'fixed-llc'])
      fs.rmSync(path.join(product, '.srcbuild', directory), {recursive: true, force: true});
    const result = await run(command, {cwd: product, env: environment,
      log: path.join(work, `${name}-driver.log`), check: false});
    const observation = await run([process.execPath, self, 'observe', product, manifest],
      {log: path.join(work, `${name}-target.log`), check: false});
    records.push({name, command, cwd: product, driverRc: result.exitCode, targetRc: observation.exitCode});
    fs.writeFileSync(path.join(work, 'results.json'), JSON.stringify(records, null, 2));
    assert.equal(result.exitCode, 0, result.stdall);
    assert.match(result.stdall, /RESULT=success through_step=2/);
    // Independent step 2 (real Git metadata) remains successful during the cut.
    const timings = fs.readFileSync(path.join(product, '.srcbuild/kkk2-timings.tsv'), 'utf8');
    fs.writeFileSync(path.join(work, `${name}-timings.tsv`), timings);
    assert(timings.split('\n').some(line => {
      const fields = line.split('\t');
      return fields[0] === 'step' && fields[1] === '2' && fields[3] === '0';
    }), timings);
    assert.match(observation.stdall, /ACQUIRE_TARGET_ASSERT_REACHED/);
    assert.equal(observation.exitCode, expectedRc, observation.stdall);
    if (expectedRc) assert.match(observation.stdall, /ERR_ASSERTION/);
  }
  fs.mkdirSync(path.join(work, 'state'));
  fs.symlinkSync(path.join(work, 'state'), state, 'dir');
  const cleanup = () => {
    fs.writeFileSync(driver, original);
    fs.unlinkSync(state);
    equalFiles(path.join(work, 'srcbuild.saved'), driver);
  };
  const removeSignalHandlers = cleanupOnSignals(cleanup);
  try {
    await arm('green', 0);
    const call = ['    node "$REPO_ROOT/ci/release/acquire_fixed_tuple.mjs" ' + '\\',
      '        "$STATE_ROOT/colour-tuple" "$CJCJ_FIXED_LLVM_DIR"'].join('\n');
    assert.equal(original.toString().split(call).length, 2);
    fs.writeFileSync(driver, original.toString().replace(call, '    : # G1 cut: skip actual acquisition call'));
    await diff(path.join(work, 'srcbuild.saved'), driver, path.join(work, 'acquire-cut.diff'));
    await arm('cut', 1);
    fs.writeFileSync(driver, original);
    await arm('restored', 0);
    console.log('ACQUIRE_CONTROL target=0/1/0 independent_step2=0/0/0; fixture only');
  } finally {
    try { cleanup(); } finally { removeSignalHandlers(); }
    const status = await capture(['git', '-C', product, 'diff', '--exit-code', '--', 'tools/srcbuild_kkk2.sh'], {check: false});
    fs.writeFileSync(path.join(work, 'restored.diff'), status.stdout);
    assert.equal(status.exitCode, 0);
  }
}

const entryIndex = process.argv.findIndex((arg, index) => index > 0 && path.resolve(arg) === self);
if (entryIndex > 0) {
  const [mode, ...args] = process.argv.slice(entryIndex + 1);
  if (mode === 'observe') observe(args[0], args[1]);
  else {
    assert(mode && args.length === 0, 'usage: test-srcbuild-acquire-wiring.mjs NEW_WORK');
    await acquireControl(path.resolve(mode));
  }
}
