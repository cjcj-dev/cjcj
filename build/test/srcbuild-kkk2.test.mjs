import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const repoRoot = path.resolve('.');
const scriptPath = path.join(repoRoot, 'tools', 'srcbuild_kkk2.sh');
const script = fs.readFileSync(scriptPath, 'utf8');

function shellFunction(name) {
  const match = script.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}$`, 'm'));
  assert.ok(match, `missing shell function ${name}`);
  return match[0];
}

function runBash(source, args = []) {
  return spawnSync('bash', ['-c', source, 'bash', ...args], {encoding: 'utf8'});
}

function runGit(args) {
  const result = spawnSync('git', args, {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function writeTuple(root, embeddedSha) {
  const pinText = fs.readFileSync(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
  const field = name => pinText.match(new RegExp(`^${name}=([0-9a-f]{40})$`, 'm'))[1];
  const llvmSha = field('LLVM_SHA');
  fs.writeFileSync(path.join(root, 'llc.gz'), 'llc fixture');
  fs.writeFileSync(path.join(root, 'cjselfhost_llvmshim.o'), 'shim fixture');
  const opt = path.join(root, 'opt');
  fs.writeFileSync(opt, `opt fixture\0CJLLVM-COMMIT:${embeddedSha}\0`);
  const gzip = spawnSync('gzip', ['-n', '-c', opt], {encoding: null});
  assert.equal(gzip.status, 0, gzip.stderr?.toString());
  fs.writeFileSync(path.join(root, 'opt.gz'), gzip.stdout);
  fs.writeFileSync(path.join(root, 'llvm-tools.manifest'), [
    'PLATFORM=linux_x86_64',
    `LLVM_SHA=${llvmSha}`,
    `CANGJIE_COMPILER_SHA=${field('CANGJIE_COMPILER_SHA')}`,
    `FLATBUFFERS_SHA=${field('FLATBUFFERS_SHA')}`,
    `LLC_SHA256=${'1'.repeat(64)}`,
    `OPT_SHA256=${'2'.repeat(64)}`,
    `SHIM_SHA256=${'3'.repeat(64)}`,
    '',
  ].join('\n'));
  return llvmSha;
}

function writeDepotChecksums(depot) {
  const files = [
    'fixed-llc/llc.gz',
    'fixed-llc/opt.gz',
    'fixed-llc/cjselfhost_llvmshim.o',
    'fixed-llc/llvm-tools.manifest',
  ];
  const rows = files.map(file => {
    const digest = crypto.createHash('sha256').update(fs.readFileSync(path.join(depot, file))).digest('hex');
    return `${digest}  ./${file}`;
  });
  fs.writeFileSync(path.join(depot, 'SHA256SUMS'), `${rows.join('\n')}\n`);
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

test('source-build CPU windows preserve explicit placement and derive their width', () => {
  const invoke = `source "$1" --lib-only\n`
    + 'test "$(explicit_cpuset 048-063)" = 48-63\n'
    + 'test "$(cpuset_width 48-63)" = 16\n'
    + 'test "$(cpuset_width 2-3,8,11-13)" = 6\n'
    + 'if explicit_cpuset 63-48; then exit 17; fi\n';
  const result = runBash(invoke, [scriptPath]);
  assert.equal(result.status, 0, result.stderr);
});

test('source-build records affinity from a real build-tool descendant', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-affinity-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const timings = path.join(root, 'timings.tsv');
  fs.writeFileSync(path.join(root, 'Makefile'), 'all:\n\tsleep 0.5\n');
  const invoke = `${shellFunction('elapsed_seconds')}\n`
    + `${shellFunction('capture_build_child_affinity')}\n`
    + `${shellFunction('run_step')}\n`
    + 'STATE_ROOT=$1 LOG_ROOT=$1 TIMINGS=$2 START_STAMP=fixture\n'
    + 'CPUSET=$(LC_ALL=C taskset -pc $$ | sed "s/.*: //")\n'
    + 'load_github_state() { :; }\n'
    + 'step_10() { taskset -c "$CPUSET" make -C "$STATE_ROOT"; }\n'
    + 'run_step 10 build-support-libraries step_10\n';
  const result = runBash(invoke, [root, timings]);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const record = fs.readFileSync(timings, 'utf8');
  assert.match(record, /^affinity\tstep=10\tpid=[0-9]+\tcommand=make\trequested=([^\t]+)\tactual=\1\targs=.*make/m);
});

test('source-build shell fetch uses the selected mirror and keeps canonical origin', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-shell-git-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'source');
  const mirror = path.join(root, 'source.git');
  const checkout = path.join(root, 'checkout');
  const authoritative = 'https://github.com/cjcj-dev/cjcj-llvm.git';
  runGit(['init', source]);
  fs.writeFileSync(path.join(source, 'value'), 'fixture\n');
  runGit(['-C', source, 'add', 'value']);
  runGit(['-C', source, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-m', 'fixture']);
  const sha = runGit(['-C', source, 'rev-parse', 'HEAD']);
  runGit(['clone', '--bare', source, mirror]);
  runGit(['init', checkout]);
  runGit(['-C', checkout, 'remote', 'add', 'origin', authoritative]);

  const helper = path.join(repoRoot, 'build/lib/srcbuild_git.sh');
  const invoke = 'source "$1"\n'
    + 'CJCJ_SRCBUILD_SOURCE_MIRRORS="$2=file://$3"\n'
    + 'srcbuild_git_fetch "$4" "$2" "$5"\n';
  const fetched = runBash(invoke, [helper, authoritative, mirror, checkout, sha]);
  assert.equal(fetched.status, 0, fetched.stderr);
  assert.equal(runGit(['-C', checkout, 'rev-parse', 'FETCH_HEAD']), sha);
  assert.equal(runGit(['-C', checkout, 'remote', 'get-url', 'origin']), authoritative);

  const missing = runBash(invoke,
    [helper, authoritative, path.join(root, 'missing.git'), checkout, sha]);
  assert.notEqual(missing.status, 0, 'missing mirror unexpectedly fell back to canonical URL');
});

test('source-build shell mirror fallback is visible and optionally required', () => {
  const helper = path.join(repoRoot, 'build/lib/srcbuild_git.sh');
  const authoritative = 'https://example.invalid/source.git';
  const fallback = runBash(
    'source "$1"\nunset CJCJ_SRCBUILD_SOURCE_MIRRORS CJCJ_SRCBUILD_REQUIRE_MIRRORS\n'
      + 'srcbuild_git_resolve_source_mirror "$2"\n',
    [helper, authoritative],
  );
  assert.equal(fallback.status, 0, fallback.stdout + fallback.stderr);
  assert.equal(fallback.stdout.trim(), authoritative);
  assert.match(fallback.stderr, /SOURCE-MIRROR none, falling back to https:\/\/example\.invalid\/source\.git/);

  const required = runBash(
    'source "$1"\nunset CJCJ_SRCBUILD_SOURCE_MIRRORS\nCJCJ_SRCBUILD_REQUIRE_MIRRORS=1\n'
      + 'srcbuild_git_resolve_source_mirror "$2"\n',
    [helper, authoritative],
  );
  assert.equal(required.status, 1, required.stdout + required.stderr);
  assert.match(required.stderr, /source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1/);
});

test('source-build shell exact checkout repairs a stale origin before fetching the pin', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-shell-checkout-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'source');
  const mirror = path.join(root, 'source.git');
  const checkout = path.join(root, 'checkout');
  const authoritative = 'https://github.com/cjcj-dev/cjcj-llvm.git';
  runGit(['init', source]);
  fs.writeFileSync(path.join(source, 'value'), 'pinned fixture\n');
  runGit(['-C', source, 'add', 'value']);
  runGit(['-C', source, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-m', 'fixture']);
  const sha = runGit(['-C', source, 'rev-parse', 'HEAD']);
  runGit(['clone', '--bare', source, mirror]);
  runGit(['init', checkout]);
  runGit(['-C', checkout, 'remote', 'add', 'origin', 'https://example.invalid/stale.git']);

  const helper = path.join(repoRoot, 'build/lib/srcbuild_git.sh');
  const invoke = 'source "$1"\n'
    + `${shellFunction('checkout_exact')}\n`
    + 'CJCJ_SRCBUILD_SOURCE_MIRRORS="$2=file://$3"\n'
    + 'checkout_exact "$4" "$2" "$5"\n';
  const result = runBash(invoke, [helper, authoritative, mirror, checkout, sha]);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(runGit(['-C', checkout, 'rev-parse', 'HEAD']), sha);
  assert.equal(runGit(['-C', checkout, 'remote', 'get-url', 'origin']), authoritative);
});

test('fixed tuple requires pin, manifest, and embedded opt commit to agree', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-fixed-tuple-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const pinText = fs.readFileSync(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
  const llvmSha = pinText.match(/^LLVM_SHA=([0-9a-f]{40})$/m)[1];
  const invoke = `${shellFunction('fixed_tuple_is_current')}\n`
    + 'REPO_ROOT=$1 CJCJ_FIXED_LLVM_DIR=$2\n'
    + 'fixed_tuple_is_current\n';

  writeTuple(root, llvmSha);
  const current = runBash(invoke, [repoRoot, root]);
  assert.equal(current.status, 0, current.stderr);
  console.log(`FIXED_TUPLE_ARM tuple=current rc=${current.status}`);

  writeTuple(root, '75a0000000000000000000000000000000000000');
  const stale = runBash(invoke, [repoRoot, root]);
  assert.equal(stale.status, 1, stale.stderr);
  console.log(`FIXED_TUPLE_ARM tuple=stale-opt rc=${stale.status}`);
});

test('fixed tuple depot seeds only checksum-valid pinned payloads and otherwise rebuilds', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-fixed-depot-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const pinText = fs.readFileSync(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
  const llvmSha = pinText.match(/^LLVM_SHA=([0-9a-f]{40})$/m)[1];
  const depotRoot = path.join(root, 'depot');
  const depot = path.join(depotRoot, llvmSha);
  const tuple = path.join(depot, 'fixed-llc');
  const destination = path.join(root, 'destination');
  fs.mkdirSync(tuple, {recursive: true});
  writeTuple(tuple, llvmSha);
  writeDepotChecksums(depot);
  const pinnedSumsSha = sha256(path.join(depot, 'SHA256SUMS'));

  const seedInvoke = `${shellFunction('fixed_tuple_is_current')}\n`
    + `${shellFunction('seed_fixed_tuple_from_depot')}\n`
    + 'REPO_ROOT=$1 CJCJ_FIXED_LLVM_DIR=$2 LLVM_SHA=$3 LLVM_TUPLE_SUMS_SHA=$4\n'
    + 'seed_fixed_tuple_from_depot "$5"\n';
  const seeded = runBash(seedInvoke, [repoRoot, destination, llvmSha, pinnedSumsSha, depotRoot]);
  assert.equal(seeded.status, 0, seeded.stderr);
  assert.match(seeded.stdout, /seeded fixed LLVM tuple from verified depot/);

  fs.rmSync(destination, {recursive: true, force: true});
  fs.appendFileSync(path.join(tuple, 'llc.gz'), 'tampered');
  const rejected = runBash(seedInvoke, [repoRoot, destination, llvmSha, pinnedSumsSha, depotRoot]);
  assert.equal(rejected.status, 1, rejected.stdout + rejected.stderr);
  assert.match(rejected.stderr, /SHA256SUMS verification failed/);
  assert.equal(fs.existsSync(destination), false, 'rejected depot payload was copied');

  writeDepotChecksums(depot);
  const rewritten = runBash(seedInvoke, [repoRoot, destination, llvmSha, pinnedSumsSha, depotRoot]);
  assert.equal(rewritten.status, 1, rewritten.stdout + rewritten.stderr);
  assert.match(rewritten.stderr, /SHA256SUMS digest disagrees with ci\/llvm_pin\.env/);
  assert.equal(fs.existsSync(destination), false, 'jointly rewritten payload and checksums were copied');

  const checkoutMarker = path.join(root, 'rebuild-started');
  const buildInvoke = `${shellFunction('fixed_tuple_is_current')}\n`
    + `${shellFunction('seed_fixed_tuple_from_depot')}\n`
    + `${shellFunction('build_fixed_tuple')}\n`
    + 'checkout_exact() { touch "$CHECKOUT_MARKER"; return 17; }\n'
    + 'checkout_sparse_exact() { return 17; }\n'
    + 'DRY_RUN=0 REPO_ROOT=$1 STATE_ROOT=$2 CJCJ_FIXED_LLVM_DIR=$2 JOBS=1 '
    + 'CHECKOUT_MARKER=$3 CJCJ_LLVM_DEPOT_ROOT=$4 LLVM_TUPLE_SUMS_SHA=$5\n'
    + 'build_fixed_tuple\n';
  const rebuilt = runBash(buildInvoke,
    [repoRoot, path.join(root, 'build-destination'), checkoutMarker, depotRoot, pinnedSumsSha]);
  assert.equal(rebuilt.status, 1, rebuilt.stdout + rebuilt.stderr);
  assert.equal(fs.existsSync(checkoutMarker), true, 'rebuild path did not start after rejecting depot');
});

test('fixed tuple build stops when an exact checkout fails', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-checkout-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const sparseMarker = path.join(root, 'sparse-called');
  const invoke = `${shellFunction('build_fixed_tuple')}\n`
    + 'fixed_tuple_is_current() { return 1; }\n'
    + 'checkout_exact() { return 17; }\n'
    + 'checkout_sparse_exact() { touch "$SPARSE_MARKER"; return 0; }\n'
    + 'DRY_RUN=0 REPO_ROOT=$1 STATE_ROOT=$2 CJCJ_FIXED_LLVM_DIR=$2 JOBS=1 SPARSE_MARKER=$3\n'
    + 'build_fixed_tuple\n';
  const failed = runBash(invoke, [repoRoot, root, sparseMarker]);
  assert.equal(failed.status, 1, failed.stderr);
  assert.equal(fs.existsSync(sparseMarker), false, 'later checkout ran after the first failure');
});

test('stage3 dry-run requires the stage2 product directory', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-stage3-contract-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const stage2ProductDir = path.join(root, 'target', 'release', 'bin');
  const invoke = `${shellFunction('validate_stage_step_contracts')}\n`
    + 'FROM_STEP=33 THROUGH_STEP=33 STAGE1_STEP_SCRIPT=$1 STAGE2_STEP_SCRIPT=$1 '
    + 'STAGE3_STEP_SCRIPT=$1 STAGE2_PRODUCT_DIR=$2\n'
    + 'validate_stage_step_contracts\n';

  const missing = runBash(invoke, [scriptPath, stage2ProductDir]);
  assert.equal(missing.status, 1, missing.stderr);
  assert.match(missing.stderr, /dry-run stage3 input missing: stage2 product directory/);
  console.log(`STAGE3_INPUT_ARM directory=missing rc=${missing.status}`);

  fs.mkdirSync(stage2ProductDir, {recursive: true});
  const present = runBash(invoke, [scriptPath, stage2ProductDir]);
  assert.equal(present.status, 0, present.stderr);
  console.log(`STAGE3_INPUT_ARM directory=present rc=${present.status}`);
});

test('step13 stops before build CLI when an interrupted clone repair fails', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-step13-repair-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const cliMarker = path.join(root, 'build-cli-called');
  const invoke = `${shellFunction('step_13')}\n`
    + 'repair_calls=0\n'
    + 'ensure_exact_clone() { repair_calls=$((repair_calls + 1)); '
    + 'if ((repair_calls == 2)); then return 17; fi; return 0; }\n'
    + 'build_cli() { touch "$CLI_MARKER"; }\n'
    + 'CANGJIE_WORKSPACE=$1 CLI_MARKER=$2 COMPILER_SRC_URL=a COMPILER_REF=aa '
    + 'RUNTIME_SRC_URL=b RUNTIME_REF=bb TOOLS_SRC_URL=c TOOLS_REF=cc '
    + 'STDX_SRC_URL=d STDX_REF=dd\n'
    + 'step_13\n';
  const failed = runBash(invoke, [root, cliMarker]);
  assert.equal(failed.status, 1, failed.stderr);
  assert.equal(fs.existsSync(cliMarker), false, 'build CLI ran after clone repair failed');
});
