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

function runDriver(args) {
  return runBash('bash "$1" "${@:2}"', [scriptPath, ...args]);
}

function runGit(args) {
  const result = spawnSync('git', args, {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function writeTuple(root, embeddedSha, compilerSha) {
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
  const lld = path.join(root, 'ld.lld');
  fs.writeFileSync(lld, 'ld.lld fixture\n');
  const lldGzip = spawnSync('gzip', ['-n', '-c', lld], {encoding: null});
  assert.equal(lldGzip.status, 0, lldGzip.stderr?.toString());
  fs.writeFileSync(path.join(root, 'ld.lld.gz'), lldGzip.stdout);
  const lldSha = crypto.createHash('sha256').update(fs.readFileSync(lld)).digest('hex');
  fs.writeFileSync(path.join(root, 'llvm-tools.manifest'), [
    'PLATFORM=linux_x86_64',
    `LLVM_SHA=${llvmSha}`,
    `CANGJIE_COMPILER_SHA=${compilerSha || field('CANGJIE_COMPILER_SHA')}`,
    `FLATBUFFERS_SHA=${field('FLATBUFFERS_SHA')}`,
    `LLC_SHA256=${'1'.repeat(64)}`,
    `OPT_SHA256=${'2'.repeat(64)}`,
    'LLD_TOOL=ld.lld',
    `LLD_SOURCE=tuple:${llvmSha}`,
    'LLD_VERSION=LLD 15.0.4',
    `LLD_SHA256=${lldSha}`,
    `SHIM_SHA256=${'3'.repeat(64)}`,
    '',
  ].join('\n'));
  return {llvmSha, compilerSha: compilerSha || field('CANGJIE_COMPILER_SHA')};
}

function writeDepotChecksums(depot) {
  const files = [
    'fixed-llc/llc.gz',
    'fixed-llc/opt.gz',
    'fixed-llc/ld.lld.gz',
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

test('kkk2 calls the shared target/host assertion before CPU placement and P10', () => {
  const assertion = script.indexOf('assert-host-contract.mjs');
  const affinity = script.indexOf('inherited_cpuset=$(current_cpuset)');
  const state = script.indexOf('readonly STATE_ROOT=');
  const p10 = script.indexOf('step_31() {');
  assert.ok(assertion >= 0);
  assert.ok(assertion < affinity && affinity < state && state < p10);
  assert.match(script, /--target "\$TARGET" --profile kkk2 \|\| exit \$\?/);
});

test('target has no positional alias', () => {
  const result = runDriver(['windows-x64', '--dry-run']);
  assert.equal(result.status, 2, result.stdout + result.stderr);
  assert.match(result.stderr, /unexpected positional argument: windows-x64; use --target TARGET/);
  assert.doesNotMatch(result.stdout + result.stderr, /HOST_CONTRACT|Bootstrap stage0|DRY_RUN COMMAND=/);
});

test('kkk2 dry-run rejects windows-x64 and unknown target before P10', () => {
  const windows = runDriver(['--target', 'windows-x64', '--dry-run']);
  assert.equal(windows.status, 2, windows.stdout + windows.stderr);
  assert.match(windows.stderr, /required host/);
  assert.match(windows.stderr, /kkk2 supports only linux-x64/);
  assert.doesNotMatch(windows.stdout + windows.stderr, /DRY_RUN COMMAND=|step_31|Bootstrap stage0/);

  const unknown = runDriver(['--target', 'plan9-mips', '--dry-run']);
  assert.equal(unknown.status, 2, unknown.stdout + unknown.stderr);
  assert.match(unknown.stderr, /unknown target 'plan9-mips'/);
  assert.doesNotMatch(unknown.stdout + unknown.stderr, /DRY_RUN COMMAND=/);

  const aarch64 = runDriver(['--target', 'linux-aarch64', '--dry-run']);
  assert.equal(aarch64.status, 2, aarch64.stdout + aarch64.stderr);
  assert.match(aarch64.stderr, /required host linux\/arm64/);
});

test('source-build records affinity from the long top-level make instead of an earlier short make', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-affinity-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const timings = path.join(root, 'timings.tsv');
  const fakeBin = path.join(root, 'fake-bin');
  fs.mkdirSync(fakeBin);
  fs.copyFileSync('/usr/bin/sleep', path.join(fakeBin, 'make'));
  fs.chmodSync(path.join(fakeBin, 'make'), 0o755);
  fs.writeFileSync(path.join(root, 'Makefile'), 'all:\n\tsleep 1.5\n');
  const invoke = `${shellFunction('elapsed_seconds')}\n`
    + `${shellFunction('capture_build_child_affinity')}\n`
    + `${shellFunction('run_step')}\n`
    + 'STATE_ROOT=$1 LOG_ROOT=$1 TIMINGS=$2 START_STAMP=fixture\n'
    + 'CPUSET=$(LC_ALL=C taskset -pc $$ | sed "s/.*: //")\n'
    + 'load_github_state() { :; }\n'
    + 'step_10() {\n'
    + '  "$STATE_ROOT/fake-bin/make" 1 &\n'
    + '  short_pid=$!\n'
    + '  sleep 0.05\n'
    + '  taskset -c "$CPUSET" make -C "$STATE_ROOT" DESTDIR= RPATH_LIST=/usr/lib all\n'
    + '  wait "$short_pid"\n'
    + '}\n'
    + 'run_step 10 build-support-libraries step_10\n';
  const result = runBash(invoke, [root, timings]);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const record = fs.readFileSync(timings, 'utf8');
  assert.match(record, /^affinity\tstep=10\tpid=[0-9]+\tcommand=make\trequested=([^\t]+)\tactual=\1\targs=.*DESTDIR=/m);
  assert.doesNotMatch(record, /args=.*fake-bin\/make 1/);
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

test('source-build shell mirror contract reaches fetch on the selected bash', () => {
  const contract = path.join(repoRoot, 'build/test/srcbuild_git_shell_contract.sh');
  const result = spawnSync('bash', [contract], {encoding: 'utf8'});
  process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /ASSERT_REACHED name=fetch_head/);
  assert.match(result.stdout, /ASSERT_PASS name=fetch_head/);
  assert.match(result.stdout, /ASSERT_REACHED name=fetch_sources_head/);
  assert.match(result.stdout, /ASSERT_PASS name=fetch_sources_head/);
  assert.match(result.stdout, /ASSERT_REACHED name=invalid_message/);
  assert.match(result.stdout, /ASSERT_PASS name=invalid_message/);
  assert.match(result.stdout, /ASSERT_REACHED name=duplicate_message/);
  assert.match(result.stdout, /ASSERT_PASS name=duplicate_message/);
  assert.match(result.stdout, /ASSERT_REACHED name=glob_exact/);
  assert.match(result.stdout, /ASSERT_PASS name=glob_exact/);
  assert.match(result.stdout, /CONTRACT_FAILS=0/);
});

test('kkk2 source-build profile requires mirrors while local helpers keep fallback enabled', () => {
  const helper = path.join(repoRoot, 'build/lib/srcbuild_git.sh');
  const authoritative = 'https://example.invalid/source.git';
  const kkk2 = runBash(
    'source "$1" --lib-only\nsource "$2"\n'
      + 'unset CJCJ_SRCBUILD_SOURCE_MIRRORS CJCJ_SRCBUILD_REQUIRE_MIRRORS\n'
      + 'apply_source_mirror_profile kkk2\n'
      + 'srcbuild_git_resolve_source_mirror "$3"\n',
    [scriptPath, helper, authoritative],
  );
  assert.equal(kkk2.status, 1, kkk2.stdout + kkk2.stderr);
  assert.match(kkk2.stderr,
    /source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1: https:\/\/example\.invalid\/source\.git/);

  const local = runBash(
    'source "$1" --lib-only\nsource "$2"\n'
      + 'unset CJCJ_SRCBUILD_SOURCE_MIRRORS CJCJ_SRCBUILD_REQUIRE_MIRRORS\n'
      + 'apply_source_mirror_profile local\n'
      + 'srcbuild_git_resolve_source_mirror "$3"\n',
    [scriptPath, helper, authoritative],
  );
  assert.equal(local.status, 0, local.stdout + local.stderr);
  assert.equal(local.stdout.trim(), authoritative);
  assert.match(local.stderr, /SOURCE-MIRROR none, falling back to/);
  assert.match(script, /^apply_source_mirror_profile "\$host_name"$/m);
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

test('source-build sparse exact checkout repairs a stale origin before fetching the pin', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-sparse-checkout-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'source');
  const mirror = path.join(root, 'source.git');
  const checkout = path.join(root, 'checkout');
  const authoritative = 'https://github.com/cangjie-lang/cangjie_compiler.git';
  runGit(['init', source]);
  fs.mkdirSync(path.join(source, 'schema'));
  fs.writeFileSync(path.join(source, 'schema', 'fixture.fbs'), 'table Fixture {}\n');
  runGit(['-C', source, 'add', 'schema/fixture.fbs']);
  runGit(['-C', source, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-m', 'fixture']);
  const sha = runGit(['-C', source, 'rev-parse', 'HEAD']);
  runGit(['clone', '--bare', source, mirror]);
  runGit(['init', checkout]);
  runGit(['-C', checkout, 'remote', 'add', 'origin', 'https://example.invalid/stale.git']);

  const helper = path.join(repoRoot, 'build/lib/srcbuild_git.sh');
  const invoke = 'source "$1"\n'
    + `${shellFunction('checkout_sparse_exact')}\n`
    + 'CJCJ_SRCBUILD_SOURCE_MIRRORS="$2=file://$3"\n'
    + 'checkout_sparse_exact "$4" "$2" "$5" schema\n';
  const result = runBash(invoke, [helper, authoritative, mirror, checkout, sha]);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(runGit(['-C', checkout, 'rev-parse', 'HEAD']), sha);
  assert.equal(runGit(['-C', checkout, 'remote', 'get-url', 'origin']), authoritative);
  assert.equal(fs.existsSync(path.join(checkout, 'schema', 'fixture.fbs')), true);
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

test('fixed tuple publisher feeds the bootstrap consumer and rejects a missing static marker', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-publish-consume-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'source');
  fs.mkdirSync(source);
  const pin = fs.readFileSync(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
  const llvmSha = pin.match(/^LLVM_SHA=([0-9a-f]{40})$/m)[1];
  const {compilerSha} = writeTuple(source, llvmSha);
  const llc = Buffer.from('llc fixture\n');
  const compressed = spawnSync('gzip', ['-n', '-c'], {input: llc});
  assert.equal(compressed.status, 0, compressed.stderr?.toString());
  fs.writeFileSync(path.join(source, 'llc.gz'), compressed.stdout);
  const depotRoot = path.join(root, 'depot');
  const depot = path.join(depotRoot, llvmSha, compilerSha);
  const published = runBash('source "$1/ci/llvm-tuple-layout.sh"\n'
    + 'REPO_ROOT=$1 CJCJ_FIXED_LLVM_DIR=$2 LLVM_SHA=$3 CANGJIE_COMPILER_SHA=$4\n'
    + 'publish_fixed_tuple_to_depot "$5"\n',
  [repoRoot, source, llvmSha, compilerSha, depotRoot]);
  assert.equal(published.status, 0, published.stdout + published.stderr);
  assert.deepEqual(fs.readFileSync(path.join(depot, 'bin', 'llc')), llc);
  assert.deepEqual(fs.readFileSync(path.join(depot, 'bin', 'opt')),
    fs.readFileSync(path.join(source, 'opt')));
  const consume = () => runBash('source "$1/ci/bootstrap/bootstrap.sh"\n'
    + 'STAGE=published-tuple\nassert_colour_tuple "$2" "$3"\n',
  [repoRoot, depot, llvmSha]);
  const green = consume();
  assert.equal(green.status, 0, green.stdout + green.stderr);
  const marker = path.join(depot, 'lib', 'STATIC_LLVM.txt');
  const saved = fs.readFileSync(marker);
  fs.unlinkSync(marker);
  const red = consume();
  assert.equal(red.status, 1, red.stdout + red.stderr);
  assert.match(red.stdout + red.stderr, /colour LLVM tuple 缺 lib\/STATIC_LLVM\.txt/);
  fs.writeFileSync(marker, saved);
  const restored = consume();
  assert.equal(restored.status, 0, restored.stdout + restored.stderr);
  console.log(`PUBLISHER_CONSUMER_ARM green=${green.status} missing-static-marker=${red.status} restored=${restored.status}`);
});

test('fixed tuple depot seeds only checksum-valid pinned payloads; explicit publisher can rebuild', t => {
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
    + `${shellFunction('resolve_depot_tuple_root')}\n`
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
    + `${shellFunction('resolve_depot_tuple_root')}\n`
    + `${shellFunction('seed_fixed_tuple_from_depot')}\n`
    + `${shellFunction('build_fixed_tuple')}\n`
    + 'checkout_exact() { touch "$CHECKOUT_MARKER"; return 17; }\n'
    + 'checkout_sparse_exact() { return 17; }\n'
    + 'CJCJ_LLVM_DEPOT_PUBLISH=1 DRY_RUN=0 REPO_ROOT=$1 STATE_ROOT=$2 CJCJ_FIXED_LLVM_DIR=$2 JOBS=1 '
    + 'CHECKOUT_MARKER=$3 CJCJ_LLVM_DEPOT_ROOT=$4 LLVM_TUPLE_SUMS_SHA=$5\n'
    + 'build_fixed_tuple\n';
  const rebuilt = runBash(buildInvoke,
    [repoRoot, path.join(root, 'build-destination'), checkoutMarker, depotRoot, pinnedSumsSha]);
  assert.equal(rebuilt.status, 1, rebuilt.stdout + rebuilt.stderr);
  assert.equal(fs.existsSync(checkoutMarker), true, 'rebuild path did not start after rejecting depot');
});

test('fixed tuple depot seeds the nested compiler-sha key and rejects a mismatched pin', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-depot-compiler-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const pinText = fs.readFileSync(path.join(repoRoot, 'ci', 'llvm_pin.env'), 'utf8');
  const llvmSha = pinText.match(/^LLVM_SHA=([0-9a-f]{40})$/m)[1];
  const pinCompiler = pinText.match(/^CANGJIE_COMPILER_SHA=([0-9a-f]{40})$/m)[1];
  const otherCompiler = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const depotRoot = path.join(root, 'depot');
  const pinTuple = path.join(depotRoot, llvmSha, pinCompiler, 'fixed-llc');
  const otherTuple = path.join(depotRoot, llvmSha, otherCompiler, 'fixed-llc');
  fs.mkdirSync(pinTuple, {recursive: true});
  fs.mkdirSync(otherTuple, {recursive: true});
  writeTuple(pinTuple, llvmSha, pinCompiler);
  writeTuple(otherTuple, llvmSha, otherCompiler);
  writeDepotChecksums(path.join(depotRoot, llvmSha, pinCompiler));
  writeDepotChecksums(path.join(depotRoot, llvmSha, otherCompiler));
  const pinSums = sha256(path.join(depotRoot, llvmSha, pinCompiler, 'SHA256SUMS'));
  const otherSums = sha256(path.join(depotRoot, llvmSha, otherCompiler, 'SHA256SUMS'));
  const destination = path.join(root, 'destination');
  const seedInvoke = `${shellFunction('fixed_tuple_is_current')}\n`
    + `${shellFunction('resolve_depot_tuple_root')}\n`
    + `${shellFunction('seed_fixed_tuple_from_depot')}\n`
    + 'REPO_ROOT=$1 CJCJ_FIXED_LLVM_DIR=$2 LLVM_SHA=$3 CANGJIE_COMPILER_SHA=$4 '
    + 'LLVM_TUPLE_SUMS_SHA=$5\n'
    + 'seed_fixed_tuple_from_depot "$6"\n';

  const seeded = runBash(seedInvoke, [repoRoot, destination, llvmSha, pinCompiler, pinSums, depotRoot]);
  assert.equal(seeded.status, 0, seeded.stderr);
  assert.match(seeded.stdout, new RegExp(`${llvmSha}/${pinCompiler}`));

  fs.rmSync(destination, {recursive: true, force: true});
  const rejected = runBash(seedInvoke,
    [repoRoot, destination, llvmSha, otherCompiler, otherSums, depotRoot]);
  assert.equal(rejected.status, 1, rejected.stdout + rejected.stderr);
  assert.match(rejected.stderr, /pin, manifest, and opt lineage disagree/);
});

test('shared support cache misses until step 11 writes and then hits a second workspace', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-support-cache-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const cache = path.join(root, 'support-cache');
  const mirrors = path.join(root, 'mirrors');
  fs.mkdirSync(mirrors);
  const ncursesTar = path.join(mirrors, 'ncurses-6.5.tar.gz');
  const libeditTar = path.join(mirrors, 'libedit-20210910-3.1.tar.gz');
  fs.writeFileSync(ncursesTar, 'ncurses-fixture');
  fs.writeFileSync(libeditTar, 'libedit-fixture');
  const mapping = 'https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.5.tar.gz=file://'
    + ncursesTar
    + ';https://thrysoee.dk/editline/libedit-20210910-3.1.tar.gz=file://'
    + libeditTar;
  const workspaceA = path.join(root, 'ws-a');
  const workspaceB = path.join(root, 'ws-b');
  fs.mkdirSync(path.join(workspaceA, 'buildtools'), {recursive: true});
  fs.mkdirSync(path.join(workspaceB, 'buildtools'), {recursive: true});
  const helpers = `${shellFunction('support_cache_root')}\n`
    + `${shellFunction('srcbuild_tarball_resolve_mirror')}\n`
    + `${shellFunction('support_tarball_sha256')}\n`
    + `${shellFunction('support_cache_key')}\n`
    + `${shellFunction('support_cache_dir')}\n`
    + `${shellFunction('step_9')}\n`
    + `${shellFunction('step_10')}\n`
    + `${shellFunction('step_11')}\n`;
  const envPrefix = 'CJCJ_SRCBUILD_SUPPORT_CACHE=$1 CJCJ_SRCBUILD_TARBALL_MIRRORS=$2 '
    + 'CANGJIE_BUILD_ROOT=$3 TARGET=linux-x64 SRCBUILD_USER_HOME=$4\n';
  const miss = runBash(helpers + envPrefix + 'step_9\n',
    [cache, mapping, path.join(workspaceA, 'buildtools'), root]);
  assert.equal(miss.status, 0, miss.stderr);
  assert.match(miss.stdout, /local support-library cache miss/);

  fs.writeFileSync(path.join(workspaceA, 'buildtools', 'installed.marker'), 'built');
  const written = runBash(helpers + envPrefix + 'step_11 && step_9\n',
    [cache, mapping, path.join(workspaceA, 'buildtools'), root]);
  assert.equal(written.status, 0, written.stderr);
  assert.match(written.stdout, /local support-library cache hit/);

  const hitB = runBash(helpers + envPrefix + 'step_9 && step_10\n',
    [cache, mapping, path.join(workspaceB, 'buildtools'), root]);
  assert.equal(hitB.status, 0, hitB.stderr);
  assert.match(hitB.stdout, /local support-library cache hit/);
  assert.equal(fs.readFileSync(path.join(workspaceB, 'buildtools', 'installed.marker'), 'utf8'), 'built');
});

test('fixed tuple producer checks build-tree ld.lld through its symlink target', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-lld-symlink-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const clean = path.join(repoRoot, 'build/test/fixtures/colour-ld-lld/clean');
  const bad = path.join(repoRoot, 'build/test/fixtures/colour-ld-lld/bad');
  assert.equal(sha256(clean), '879294b77c945f5e7ddd821fbde7b4c2fd9bf2816987a4aed99cf80f5a569f33');
  assert.equal(sha256(bad), '29f24afc38b856aa11674d5ee87f3dfc7adcb4f31acb560d451d4b70f97947fb');
  const invoke = 'set -euo pipefail\n'
    + `${shellFunction('build_fixed_tuple')}\n`
    + 'fixed_tuple_is_current() { return 0; }\n'
    + 'seed_fixed_tuple_from_depot() { return 1; }\n'
    + 'checkout_exact() { return 0; }\n'
    + 'checkout_sparse_exact() { return 0; }\n'
    + 'cmake() { return 0; }\n'
    + 'ninja() {\n'
    + '  local dest=""\n'
    + '  while [[ $# -gt 0 ]]; do\n'
    + '    if [[ $1 == -C ]]; then dest=$2; shift 2; continue; fi\n'
    + '    shift\n'
    + '  done\n'
    + '  mkdir -p "$dest/bin"\n'
    + '  if [[ $dest == *llc-build ]]; then\n'
    + '    cp "$CLEAN_ELF" "$dest/bin/llc"\n'
    + '    cp "$CLEAN_ELF" "$dest/bin/opt"\n'
    + '    cp "$LLD_ELF" "$dest/bin/lld"\n'
    + '    ln -s lld "$dest/bin/ld.lld"\n'
    + '  else\n'
    + '    printf \'#!/bin/sh\\nexit 0\\n\' > "$dest/flatc"\n'
    + '    chmod +x "$dest/flatc"\n'
    + '  fi\n'
    + '}\n'
    + 'clang++() {\n'
    + '  local out=""\n'
    + '  while [[ $# -gt 0 ]]; do\n'
    + '    if [[ $1 == -o ]]; then out=$2; break; fi\n'
    + '    shift\n'
    + '  done\n'
    + '  mkdir -p "$(dirname "$out")"\n'
    + '  printf shim > "$out"\n'
    + '}\n'
    + 'publish_fixed_tuple_to_depot() { echo PUBLISHED; return 0; }\n'
    + 'resolve_depot_tuple_root() { printf \'%s\\n\' "$1/resolved"; }\n'
    + 'CJCJ_LLVM_DEPOT_PUBLISH=1 DRY_RUN=0 JOBS=1 REPO_ROOT=$1 STATE_ROOT=$2 '
    + 'CJCJ_FIXED_LLVM_DIR=$3 CLEAN_ELF=$4 LLD_ELF=$5\n'
    + 'mkdir -p "$CJCJ_FIXED_LLVM_DIR"\n'
    + 'build_fixed_tuple\n';
  const run = lldElf => runBash(invoke, [repoRoot, path.join(root, 'state'), path.join(root, 'out'), clean, lldElf]);
  const link = path.join(root, 'state', 'fixed-llvm-build', 'llc-build', 'bin', 'ld.lld');
  const cleanRun = run(clean);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true, 'producer fixture ld.lld must stay a symlink');
  assert.equal(fs.readlinkSync(link), 'lld');
  console.log(`FIXED_TUPLE_SYMLINK clean_rc=${cleanRun.status}`);
  console.log(cleanRun.stdout);
  console.log(cleanRun.stderr);
  assert.match(cleanRun.stdout, /NO_LIBXML2 lld/);
  assert.doesNotMatch(cleanRun.stdout + cleanRun.stderr, /not a regular file/);
  assert.equal(cleanRun.status, 0, cleanRun.stdout + cleanRun.stderr);
  assert.match(cleanRun.stdout, /NO_LIBXML2 llc/);
  assert.match(cleanRun.stdout, /NO_LIBXML2 opt/);
  assert.match(cleanRun.stdout, /PUBLISHED/);
  fs.rmSync(path.join(root, 'state'), {recursive: true, force: true});
  fs.rmSync(path.join(root, 'out'), {recursive: true, force: true});
  const badRun = run(bad);
  console.log(`FIXED_TUPLE_SYMLINK bad_rc=${badRun.status}`);
  console.log(badRun.stdout);
  console.log(badRun.stderr);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
  assert.match(badRun.stderr, /DT_NEEDED libxml2 in .*\/lld\n/);
  assert.doesNotMatch(badRun.stdout + badRun.stderr, /not a regular file/);
  assert.equal(badRun.status, 1, badRun.stdout + badRun.stderr);
  assert.match(badRun.stdout, /NO_LIBXML2 llc/);
  assert.match(badRun.stdout, /NO_LIBXML2 opt/);
  assert.doesNotMatch(badRun.stdout, /NO_LIBXML2 lld/);
  const directAfter = spawnSync('bash', [path.join(repoRoot, 'ci/assert_no_libxml2_needed.sh'), link], {encoding: 'utf8'});
  console.log(`FIXED_TUPLE_SYMLINK direct_symlink_rc=${directAfter.status}`);
  assert.equal(directAfter.status, 2, directAfter.stdout + directAfter.stderr);
  assert.match(directAfter.stderr, /not a regular file: .*\/ld\.lld\n/);
});

test('fixed tuple build stops when an exact checkout fails', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-checkout-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const sparseMarker = path.join(root, 'sparse-called');
  const invoke = `${shellFunction('build_fixed_tuple')}\n`
    + 'fixed_tuple_is_current() { return 1; }\n'
    + 'checkout_exact() { return 17; }\n'
    + 'checkout_sparse_exact() { touch "$SPARSE_MARKER"; return 0; }\n'
    + 'CJCJ_LLVM_DEPOT_PUBLISH=1 DRY_RUN=0 REPO_ROOT=$1 STATE_ROOT=$2 CJCJ_FIXED_LLVM_DIR=$2 JOBS=1 SPARSE_MARKER=$3\n'
    + 'build_fixed_tuple\n';
  const failed = runBash(invoke, [repoRoot, root, sparseMarker]);
  assert.equal(failed.status, 1, failed.stderr);
  assert.equal(fs.existsSync(sparseMarker), false, 'later checkout ran after the first failure');
});

test('stage3 dry-run requires the bootstrap stage2 compiler', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-stage3-contract-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const stage2ProductDir = path.join(root, 'bootstrap-work');
  const invoke = `${shellFunction('validate_stage_step_contracts')}\n`
    + 'FROM_STEP=33 THROUGH_STEP=33 STAGE1_STEP_SCRIPT=$1 STAGE2_STEP_SCRIPT=$1 '
    + 'STAGE3_STEP_SCRIPT=$1 CJCJ_BOOTSTRAP_WORK=$2\n'
    + 'validate_stage_step_contracts\n';

  const missing = runBash(invoke, [scriptPath, stage2ProductDir]);
  assert.equal(missing.status, 1, missing.stderr);
  assert.match(missing.stderr, /dry-run stage3 input missing: bootstrap stage2 compiler/);
  console.log(`STAGE3_INPUT_ARM directory=missing rc=${missing.status}`);

  fs.mkdirSync(stage2ProductDir, {recursive: true});
  fs.writeFileSync(path.join(stage2ProductDir, 'cjcj-stage2'), 'compiler');
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

function writeStub(file, body) {
  fs.writeFileSync(file, body);
  fs.chmodSync(file, 0o755);
}

const step8Preamble = 'source "$1" --lib-only\n'
  + 'append_env() { printf "%s=%s\\n" "$1" "$2" >> "$GITHUB_ENV"; }\n'
  + 'export GITHUB_ENV=$2 PATH=$3 CCACHE_STUB_LOG=$4\n';
const step8Invoke = `${step8Preamble}srcbuild_setup_compiler_cache\n`;

test('step 8 enables ccache launchers when sccache is absent and ccache is present', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-step8-ccache-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  writeStub(path.join(bin, 'ccache'),
    '#!/bin/bash\nprintf "ccache-stub %s\\n" "$*" >> "$CCACHE_STUB_LOG"\n');
  fs.symlinkSync('/usr/bin/mkdir', path.join(bin, 'mkdir'));
  const envFile = path.join(root, 'github.env');
  const cacheDir = path.join(root, 'cache');
  const workspace = path.join(root, 'workspace');
  const stubLog = path.join(root, 'ccache-calls.log');
  const invoke = `${step8Preamble}export CJCJ_SRCBUILD_CCACHE_DIR=$5 CANGJIE_WORKSPACE=$6\nsrcbuild_setup_compiler_cache\n`;
  const result = runBash(invoke, [scriptPath, envFile, bin, stubLog, cacheDir, workspace]);
  assert.equal(result.status, 0, result.stderr);
  const env = fs.readFileSync(envFile, 'utf8');
  for (const record of [
    'CMAKE_C_COMPILER_LAUNCHER=ccache',
    'CMAKE_CXX_COMPILER_LAUNCHER=ccache',
    `CCACHE_DIR=${cacheDir}`,
    `CCACHE_BASEDIR=${workspace}`,
    'CCACHE_NOHASHDIR=true',
    'CCACHE_SLOPPINESS=pch_defines,include_file_mtime,locale',
  ]) {
    assert.ok(env.includes(record), `missing ${record} in:\n${env}`);
  }
  assert.match(result.stdout, /ccache enabled as CMAKE compiler launcher/);
  const calls = fs.readFileSync(stubLog, 'utf8');
  assert.match(calls, /-M 60G/);
  assert.match(calls, /-z/);
});

test('step 8 keeps the launchers unset when neither sccache nor ccache is installed', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-step8-none-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const envFile = path.join(root, 'github.env');
  const result = runBash(step8Invoke, [scriptPath, envFile, bin, path.join(root, 'stub.log')]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /sccache is absent; build\/cli\.mjs will leave compiler launchers unset/);
  assert.equal(fs.existsSync(envFile), false, 'launcher env was appended without a cache tool');
});

test('step 8 ccache fallback honours the CJCJ_SRCBUILD_CCACHE=0 opt-out', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-step8-optout-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  writeStub(path.join(bin, 'ccache'), '#!/bin/bash\nexit 0\n');
  const envFile = path.join(root, 'github.env');
  const invoke = `${step8Preamble}export CJCJ_SRCBUILD_CCACHE=0\nsrcbuild_setup_compiler_cache\n`;
  const result = runBash(invoke, [scriptPath, envFile, bin, path.join(root, 'stub.log')]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /CJCJ_SRCBUILD_CCACHE=0; CMAKE compiler launcher is pathcanon/);
  const env = fs.readFileSync(envFile, 'utf8');
  assert.match(env, /srcbuild_pathcanon\.sh/);
  assert.ok(!env.includes('CMAKE_CXX_COMPILER_LAUNCHER=ccache'), env);
});

test('step 8 prefers sccache when it is on PATH', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'srcbuild-step8-sccache-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const stubLog = path.join(root, 'sccache-calls.log');
  writeStub(path.join(bin, 'sccache'),
    '#!/bin/bash\nprintf "sccache-stub %s\\n" "$*" >> "$CCACHE_STUB_LOG"\n');
  const envFile = path.join(root, 'github.env');
  const result = runBash(step8Invoke, [scriptPath, envFile, bin, stubLog]);
  assert.equal(result.status, 0, result.stderr);
  const env = fs.readFileSync(envFile, 'utf8');
  assert.ok(env.includes(`SCCACHE_PATH=${path.join(bin, 'sccache')}`), env);
  assert.ok(!env.includes('CCACHE_DIR'), env);
  const calls = fs.readFileSync(stubLog, 'utf8');
  assert.match(calls, /--start-server/);
  assert.match(calls, /--zero-stats/);
});

function parseDagOrder(text) {
  const match = text.match(/DAG_ORDER=\(([0-9 \n]+)\)/);
  assert.ok(match, 'DAG_ORDER missing');
  return match[1].trim().split(/\s+/).map(Number);
}

function compilerStdlibBeforeBootstrap(text) {
  const order = parseDagOrder(text);
  const boot = order.indexOf(31);
  assert.ok(boot >= 0, 'bootstrap step 31 missing from DAG');
  const forbidden = [];
  for (const id of [15, 16, 17, 18, 19, 27, 28]) {
    if (order.includes(id)) forbidden.push(`dag:${id}`);
  }
  if (/\nstep_1[5-9]\(\)/.test(text) || /\nstep_2[78]\(\)/.test(text)) {
    forbidden.push('removed-step-function');
  }
  if (/build_cli build compiler/.test(text)) forbidden.push('build compiler');
  if (/build_cli build stdlib/.test(text)) forbidden.push('build stdlib');
  if (/pin-compiler-llvm\.mjs/.test(text)) forbidden.push('pin-compiler-llvm');
  if (/activate-source-sdk\.mjs/.test(text)) forbidden.push('activate-source-sdk');
  return forbidden;
}

const BOOTSTRAP_FLAGS = [
  '--work', '--src', '--cjcj-sha', '--stdsrc', '--cpp-src', '--base', '--host-llvm-so', '--host-llvm-sha256',
  '--colour-llvm-so', '--colour-llvm-sha256', '--ast-support', '--ast-support-sha256', '--colour-tuple', '--colour-llvm-sha',
  '--colour-rt', '--host-rt', '--stage',
];

function extractFn(text, name) {
  const match = text.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, 'm'));
  return match ? match[0] : '';
}

function bootstrapExecDefects(text) {
  const defects = [];
  const step31 = extractFn(text, 'step_31');
  const step32 = extractFn(text, 'step_32');
  const argvText = extractFn(text, 'bootstrap_argv');
  if (!step31.includes('run_bootstrap_stage stage0')) defects.push('step_31-not-bootstrap');
  if (!step32.includes('run_bootstrap_stage stage1')) defects.push('step_32-not-bootstrap');
  if (!/BOOTSTRAP_SH=.*\$REPO_ROOT\/ci\/bootstrap\/bootstrap\.sh/.test(text)) {
    defects.push('bootstrap-sh-path');
  }
  if (/BOOTSTRAP_SH=.*\/root\/cj_build\/tools\/bootstrap\.sh/.test(text)) {
    defects.push('bootstrap-sh-campaign-abs');
  }
  for (const flag of BOOTSTRAP_FLAGS) {
    if (!argvText.includes(flag)) defects.push(`missing-flag:${flag}`);
  }
  if (step31.includes('build-stage1.mjs')) defects.push('step_31-build-stage1');
  if (/PATH=.*opt/.test(step31)) defects.push('stage0-colour-opt-on-path');
  return defects;
}

test('DAG runs bootstrap after verify-source-pins and omits removed compiler/stdlib steps', () => {
  const forbidden = compilerStdlibBeforeBootstrap(script);
  assert.deepEqual(forbidden, []);
  const order = parseDagOrder(script);
  assert.ok(order.indexOf(14) < order.indexOf(31));
  assert.ok(order.indexOf(31) < order.indexOf(32));
  assert.ok(order.indexOf(32) < order.indexOf(30));
  assert.ok(order.indexOf(30) < order.indexOf(33));
  assert.ok(order.indexOf(33) < order.indexOf(20));
  assert.ok(order.indexOf(20) < order.indexOf(26));
  assert.ok(order.indexOf(26) < order.indexOf(29));
  assert.ok(order.indexOf(29) < order.indexOf(34));
  assert.ok(order.indexOf(34) < order.indexOf(35));
  assert.ok(order.indexOf(35) < order.indexOf(36));
});

test('restoring removed 15-19 calls turns the DAG contract red and only that contract', () => {
  const mutated = script.replace(
    /DAG_ORDER=\(([^)]+)\)/,
    (_, order) => `DAG_ORDER=(${order.replace('14 31', '14 15 16 17 18 19 31')})`,
  ) + '\nstep_16() { build_cli build compiler; }\n';
  const forbidden = compilerStdlibBeforeBootstrap(mutated);
  assert.ok(forbidden.includes('dag:16'));
  assert.ok(forbidden.includes('build compiler'));
  assert.deepEqual(compilerStdlibBeforeBootstrap(script), []);
});

test('DAG compose endpoint installs recorded stage3 after package', () => {
  const order = parseDagOrder(script);
  assert.ok(order.indexOf(26) < order.indexOf(34));
  assert.ok(extractFn(script, 'step_34').includes('compose-sdk.mjs'));
  assert.ok(extractFn(script, 'step_35').includes('final-compiler.tar.gz'));
  assert.ok(extractFn(script, 'step_36').includes('verify.mjs'));
  const mutated = script.replace('compose-sdk.mjs', 'missing-compose.mjs');
  assert.equal(extractFn(mutated, 'step_34').includes('compose-sdk.mjs'), false);
  assert.ok(extractFn(script, 'step_34').includes('compose-sdk.mjs'));
});

test('step_31 execs bootstrap.sh not build-stage1.mjs and only that contract turns red on revert', () => {
  assert.deepEqual(bootstrapExecDefects(script), []);
  const mutated = script.replace(
    /step_31\(\) \{\n    ulimit -c unlimited \|\| true\n    run_bootstrap_stage stage0\n\}/,
    'step_31() {\n    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/build-stage1.mjs"\n}',
  );
  assert.deepEqual(bootstrapExecDefects(mutated), ['step_31-not-bootstrap', 'step_31-build-stage1']);
  assert.deepEqual(bootstrapExecDefects(script), []);
  assert.deepEqual(compilerStdlibBeforeBootstrap(mutated), []);
});

test('bootstrap argv missing one 66aec40 flag turns only the flag contract red', () => {
  assert.deepEqual(bootstrapExecDefects(script), []);
  const mutated = script.replace('        --stdsrc "$BOOTSTRAP_STDSRC" \\\n', '');
  const defects = bootstrapExecDefects(mutated);
  assert.deepEqual(defects, ['missing-flag:--stdsrc']);
  assert.deepEqual(bootstrapExecDefects(script), []);
});

test('stage0 PATH injection of colour opt turns only the isolation contract red', () => {
  assert.deepEqual(bootstrapExecDefects(script), []);
  const mutated = script.replace(
    /step_31\(\) \{\n    ulimit -c unlimited \|\| true\n    run_bootstrap_stage stage0\n\}/,
    'step_31() {\n    PATH=/root/llvmdepot/opt:$PATH\n    run_bootstrap_stage stage0\n}',
  );
  assert.deepEqual(bootstrapExecDefects(mutated), ['stage0-colour-opt-on-path']);
  assert.deepEqual(bootstrapExecDefects(script), []);
});

for (const step of [31, 32]) {
  for (const mismatch of [false, true]) {
    test(`dry-run bootstrap step ${step} ${mismatch ? 'rejects mismatched' : 'accepts matching'} pin`, t => {
      const fixture = bootstrapDriverFixture(t, {mismatch});
      for (let sample = 1; sample <= 2; sample++) {
        const result = fixture.dryRun(step, sample);
        assert.equal(result.error, undefined);
        assert.equal(result.signal, null);
        const command = result.stdout.match(/^DRY_RUN COMMAND=(.*)$/m)?.[1];
        // Evaluate the whole invariant before asserting so an earlier check
        // cannot hide which product result the test actually observed.
        const observed = {
          exit: result.status === 0 ? 'success' : 'failure',
          command: command === undefined ? 'absent' : command.length ? 'populated' : 'empty',
          success: /^DRY_RUN RESULT=success/m.test(result.stdout),
          mismatch: /LLVM_DYLIB_SOURCE_MISMATCH/.test(result.stderr),
        };
        console.log(`DRY_ASSERT step=${step} sample=${sample} ${JSON.stringify(observed)}`);
        assert.deepEqual(observed, mismatch
          ? {exit: 'failure', command: 'absent', success: false, mismatch: true}
          : {exit: 'success', command: 'populated', success: true, mismatch: false});
        if (!mismatch) assert.match(command, new RegExp(`--stage stage${step - 31}(?: |$)`));
      }
    });
  }
}

function ghaBootstrapDefects(yml, ghaRun) {
  const defects = [];
  if (!yml.includes('bash ci/bootstrap/gha_run.sh stage0')) defects.push('gha-stage0-not-inrepo');
  if (!yml.includes('bash ci/bootstrap/gha_run.sh stage1')) defects.push('gha-stage1-not-inrepo');
  if (yml.includes('/root/cj_build/tools/bootstrap.sh') || ghaRun.includes('/root/cj_build/tools/bootstrap.sh')) {
    defects.push('gha-campaign-abs');
  }
  if (!ghaRun.includes('$root/ci/bootstrap/bootstrap.sh')) defects.push('gha-run-not-inrepo');
  if (!ghaRun.includes('--base "$CJCJ_BOOTSTRAP_BASE"')) defects.push('gha-base-not-absolute-env');
  for (const flag of BOOTSTRAP_FLAGS) {
    if (!ghaRun.includes(flag)) defects.push(`missing-flag:${flag}`);
  }
  return defects;
}

test('GHA srcbuild does not build compiler or stdlib before bootstrap', () => {
  const yml = fs.readFileSync(path.join(repoRoot, '.github/workflows/srcbuild.yml'), 'utf8');
  const ghaRun = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/gha_run.sh'), 'utf8');
  const boot = yml.indexOf('Bootstrap stage0 compiler');
  const compiler = yml.indexOf('build compiler');
  const stdlib = yml.indexOf('build stdlib');
  assert.ok(boot >= 0);
  assert.equal(compiler, -1);
  assert.equal(stdlib, -1);
  assert.ok(yml.indexOf('pin-compiler-llvm.mjs') < 0);
  assert.ok(yml.indexOf('activate-source-sdk.mjs') < 0);
  assert.ok(yml.indexOf('Bootstrap stage0 compiler') < yml.indexOf('Build stdx from source'));
  assert.deepEqual(ghaBootstrapDefects(yml, ghaRun), []);
  assert.ok(!yml.includes('ci/srcbuild/steps/build-stage1.mjs'));
  assert.ok(!yml.includes('ci/srcbuild/steps/build-stage2.mjs'));
});

function readSourceEnv() {
  const text = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/SOURCE.env'), 'utf8');
  const map = {};
  for (const line of text.split('\n')) {
    const match = line.match(/^([A-Za-z0-9_.]+)=([0-9a-f]+)$/);
    if (match) map[match[1]] = match[2];
  }
  return map;
}

function vendorShaDefects(sourceEnv, files) {
  const defects = [];
  for (const name of ['bootstrap.sh', 'sdk_build.sh', 'test_bootstrap.sh', 'stage1_host_runner.sh', 'stage1_host_identities.txt']) {
    const recorded = sourceEnv[`TOOLS_${name}`];
    if (!/^[0-9a-f]{64}$/.test(recorded || '')) defects.push(`missing-record:${name}`);
    const vendor = sha256(files[name]);
    const vendorRecord = sourceEnv[`VENDOR_${name}`];
    if (!/^[0-9a-f]{64}$/.test(vendorRecord || '')) defects.push(`missing-vendor-record:${name}`);
    if (vendorRecord && vendor !== vendorRecord) defects.push(`vendor-drift:${name}`);
  }
  return defects;
}

function vendorFiles() {
  return {
    'bootstrap.sh': path.join(repoRoot, 'ci/bootstrap/bootstrap.sh'),
    'sdk_build.sh': path.join(repoRoot, 'ci/bootstrap/sdk_build.sh'),
    'test_bootstrap.sh': path.join(repoRoot, 'ci/bootstrap/test_bootstrap.sh'),
    'stage1_host_runner.sh': path.join(repoRoot, 'ci/bootstrap/stage1_host_runner.sh'),
    'stage1_host_identities.txt': path.join(repoRoot, 'ci/bootstrap/stage1_host_identities.txt'),
  };
}

test('in-repo bootstrap copies match VENDOR hashes and retain TOOLS source records', () => {
  assert.deepEqual(vendorShaDefects(readSourceEnv(), vendorFiles()), []);
});

test('SOURCE.env recorded sha bit-flip turns only the vendor-sha contract red', () => {
  const drifted = {...readSourceEnv(), 'VENDOR_bootstrap.sh': '0'.repeat(64)};
  assert.deepEqual(vendorShaDefects(drifted, vendorFiles()), ['vendor-drift:bootstrap.sh']);
  assert.deepEqual(vendorShaDefects(readSourceEnv(), vendorFiles()), []);
});

test('one-byte copy mutation turns only the vendor-sha contract red', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vendor-sha-'));
  const mutatedPath = path.join(tmp, 'bootstrap.sh');
  const original = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/bootstrap.sh'));
  fs.writeFileSync(mutatedPath, Buffer.concat([original, Buffer.from([0x0a])]));
  const files = {
    ...vendorFiles(),
    'bootstrap.sh': mutatedPath,
  };
  assert.deepEqual(vendorShaDefects(readSourceEnv(), files), ['vendor-drift:bootstrap.sh']);
  assert.deepEqual(vendorShaDefects(readSourceEnv(), vendorFiles()), []);
  fs.rmSync(tmp, {recursive: true, force: true});
});

test('GHA absolute campaign bootstrap path turns only the GHA contract red', () => {
  const yml = fs.readFileSync(path.join(repoRoot, '.github/workflows/srcbuild.yml'), 'utf8');
  const ghaRun = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/gha_run.sh'), 'utf8');
  assert.deepEqual(ghaBootstrapDefects(yml, ghaRun), []);
  const mutated = yml.replace(
    'bash ci/bootstrap/gha_run.sh stage0',
    'bash /root/cj_build/tools/bootstrap.sh --stage stage0',
  );
  assert.deepEqual(ghaBootstrapDefects(mutated, ghaRun), ['gha-stage0-not-inrepo', 'gha-campaign-abs']);
  assert.deepEqual(ghaBootstrapDefects(yml, ghaRun), []);
});


test('bootstrap entries bind the vendored SDK builder instead of a campaign path', () => {
  const bootstrap = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/bootstrap.sh'), 'utf8');
  assert.ok(bootstrap.includes('SDK_BUILD="${SDK_BUILD:-$(dirname "${BASH_SOURCE[0]}")/sdk_build.sh}"'));
  assert.ok(!bootstrap.includes('/root/cj_build/tools/sdk_build.sh'));
  assert.match(extractFn(script, 'run_bootstrap_stage'), /SDK_BUILD="\$REPO_ROOT\/ci\/bootstrap\/sdk_build.sh" "\$\{cmd\[@\]\}"/);
  const gha = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/gha_run.sh'), 'utf8');
  assert.match(gha, /export SDK_BUILD="\$root\/ci\/bootstrap\/sdk_build.sh"/);
});


test('bootstrap source isolation excludes its nested srcbuild state', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap-nested-work-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  fs.writeFileSync(path.join(root, 'cjpm.toml'), 'source');
  fs.mkdirSync(path.join(root, '.srcbuild'), {recursive: true});
  fs.writeFileSync(path.join(root, '.srcbuild', 'state'), 'build state');
  const destination = path.join(root, '.srcbuild', 'copy');
  const bootstrap = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/bootstrap.sh'), 'utf8');
  const invoke = `${extractFn(bootstrap, 'isolate_cjcj_src')}\n`
    + 'cmd() { eval "$*"; }\nSRC=$1 DRY=0\nisolate_cjcj_src "$2"\n';
  const result = runBash(invoke, [root, destination]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(destination, 'cjpm.toml'), 'utf8'), 'source');
  assert.equal(fs.existsSync(path.join(destination, '.srcbuild')), false);
  assert.equal(fs.readFileSync(path.join(root, '.srcbuild', 'state'), 'utf8'), 'build state');
});

test('stage1 compiler consumer sees the completed target std', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap-std-before-link-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  fs.mkdirSync(path.join(root, 'stdlib-stage1'));
  fs.writeFileSync(path.join(root, 'stdlib-stage1', 'std-id'), 'host');
  const bootstrap = fs.readFileSync(path.join(repoRoot, 'ci/bootstrap/bootstrap.sh'), 'utf8');
  const invoke = `${extractFn(bootstrap, 'stage1')}\n` + `
WORK=$1 DRY=1 COLOUR_TUPLE=tuple CRT=runtime HOST_LLVM_SO=llvm COLOUR_LLVM_SHA=sha STAGE1_HEAP=20GB
record() { :; }
assert_llvm() { :; }
prepare_stage0_run_sdk() { :; }
sdk_ld_path() { :; }
assemble_stage1_sdk() { mkdir -p "$1"; cp "$3/std-id" "$1/std-id"; }
stdlib_build() { mkdir -p "$4"; printf target > "$4/std-id"; }
isolate_cjcj_src() { mkdir -p "$1"; }
shim_build() { :; }
cjpm_build() {
  value=$(cat "$1/std-id")
  [[ $value == target ]] || { echo "compiler consumed $value std" >&2; return 17; }
  echo COMPILER_CONSUMED_TARGET_STD
}
resolve_cjpm_product() { printf '%s/compiled\\n' "$WORK"; }
install_stage_compiler() { :; }
assert_version() { :; }
stage1
`;
  const result = runBash(invoke, [root]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /COMPILER_CONSUMED_TARGET_STD/);
});


// Execute the complete driver, including retained-state loading, prerequisite,
// run_step and the final RESULT. Only external inputs live in the fixture.
function bootstrapDriverFixture(t, {mismatch = false, empty = false, partialFailure = false, child = false, runtimeCase = 'valid'} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap argv '));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  for (const dir of ['ci', 'build', 'tools']) {
    fs.cpSync(path.join(repoRoot, dir), path.join(root, dir), {recursive: true});
  }
  const driver = path.join(root, 'tools/srcbuild_kkk2.sh');
  if (empty || partialFailure) {
    const text = fs.readFileSync(driver, 'utf8');
    fs.writeFileSync(driver, text.replace(/^bootstrap_argv\(\) \{[\s\S]*?^\}/m,
      partialFailure
        ? 'bootstrap_argv() {\n    printf \'%q \' "$BOOTSTRAP_SH"\n    return 1\n}'
        : 'bootstrap_argv() {\n    return 0\n}'));
  }
  const state = path.join(root, '.srcbuild');
  fs.mkdirSync(path.join(state, 'fixed-llc'), {recursive: true});
  fs.writeFileSync(path.join(state, 'kkk2-github.env'), '');
  fs.writeFileSync(path.join(state, 'kkk2-github.path'), '');
  const {llvmSha} = writeTuple(path.join(state, 'fixed-llc'),
    fs.readFileSync(path.join(root, 'ci/llvm_pin.env'), 'utf8').match(/^LLVM_SHA=(.*)$/m)[1]);
  // The prerequisite now also needs the verified complete tuple for bootstrap.
  const cached = path.join(state, 'colour-tuple');
  fs.mkdirSync(cached);
  fs.cpSync(path.join(state, 'fixed-llc'), path.join(cached, 'fixed-llc'), {recursive: true});
  writeDepotChecksums(cached);
  const llvmPin = path.join(root, 'ci/llvm_pin.env');
  fs.writeFileSync(llvmPin, fs.readFileSync(llvmPin, 'utf8').replace(/^LLVM_TUPLE_SUMS_SHA=.*$/m,
    `LLVM_TUPLE_SUMS_SHA=${sha256(path.join(cached, 'SHA256SUMS'))}`));
  const pin = path.join(root, 'ci/llvm-dylib', `linux_${os.arch() === 'x64' ? 'x86_64' : 'aarch64'}.env`);
  fs.writeFileSync(pin, fs.readFileSync(pin, 'utf8').replace(/^LLVM_DYLIB_SOURCE_SHA=.*$/m,
    `LLVM_DYLIB_SOURCE_SHA=${mismatch ? '0'.repeat(40) : llvmSha}`));
  const inputs = path.join(root, 'inputs');
  const base = path.join(inputs, 'base');
  const tuple = path.join(inputs, 'tuple');
  for (const dir of [base + '/third_party/llvm/bin', tuple + '/bin', tuple + '/lib', tuple + '/fixed-llc']) {
    fs.mkdirSync(dir, {recursive: true});
  }
  fs.copyFileSync('/bin/true', base + '/third_party/llvm/bin/opt');
  fs.copyFileSync('/bin/true', inputs + '/libLLVM-15.so');
  fs.writeFileSync(inputs + '/ast.a', 'ast input\n');
  const runtimePin = fs.readFileSync(path.join(root, 'ci/runtime_pin.env'), 'utf8').match(/^RUNTIME_REF=(.*)$/m)[1];
  const runtimeDir = path.join(inputs, 'external runtime');
  fs.mkdirSync(runtimeDir);
  let stamp = `CJRT-COMMIT:${runtimePin}`;
  if (runtimeCase === 'old-pin') stamp = `CJRT-COMMIT:${'0'.repeat(40)}`;
  if (runtimeCase === 'dirty') stamp += '-dirty';
  if (runtimeCase === 'ambiguous') stamp += `\nCJRT-COMMIT:${'1'.repeat(40)}`;
  if (runtimeCase === 'unstamped') stamp = 'runtime without stamp';
  fs.writeFileSync(runtimeDir + '/libcangjie-runtime.so', stamp + '\n');
  fs.writeFileSync(runtimeDir + '/libboundscheck.so', 'boundscheck input\n');
  const runtimeSha = sha256(runtimeDir + '/libcangjie-runtime.so');
  const boundsSha = sha256(runtimeDir + '/libboundscheck.so');
  if (runtimeCase === 'runtime-corrupt') fs.appendFileSync(runtimeDir + '/libcangjie-runtime.so', 'changed');
  if (runtimeCase === 'bounds-corrupt') fs.appendFileSync(runtimeDir + '/libboundscheck.so', 'changed');
  if (runtimeCase === 'bounds-missing') fs.unlinkSync(runtimeDir + '/libboundscheck.so');

  fs.writeFileSync(tuple + '/MANIFEST', `LLVM_SHA=${llvmSha}\n`);
  fs.writeFileSync(tuple + '/bin/opt', `CJLLVM-COMMIT:${llvmSha}\n`);
  for (const name of ['bin/llc', 'bin/ld.lld', 'lib/STATIC_LLVM.txt', 'fixed-llc/cjselfhost_llvmshim.o',
    'fixed-llc/llc.gz', 'fixed-llc/opt.gz', 'fixed-llc/ld.lld.gz', 'fixed-llc/llvm-tools.manifest']) {
    fs.writeFileSync(path.join(tuple, name), 'input fixture\n');
  }
  const payloads = ['MANIFEST', 'bin/opt', 'bin/llc', 'bin/ld.lld', 'lib/STATIC_LLVM.txt',
    'fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/llc.gz', 'fixed-llc/opt.gz', 'fixed-llc/ld.lld.gz', 'fixed-llc/llvm-tools.manifest'];
  fs.writeFileSync(tuple + '/SHA256SUMS', payloads.map(name => `${sha256(path.join(tuple, name))}  ./${name}\n`).join(''));
  fs.copyFileSync(path.join(repoRoot, 'cjpm.toml'), path.join(root, 'cjpm.toml'));
  // Give the real bootstrap pin check an actual source identity, not a
  // placeholder SHA in an unversioned copy.
  for (const args of [
    ['init', '--quiet', root],
    ['-C', root, 'add', 'cjpm.toml'],
    ['-C', root, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
      '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'test fixture source identity'],
  ]) {
    const result = spawnSync('git', args, {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
  }
  const sourceIdentity = spawnSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(sourceIdentity.status, 0, sourceIdentity.stderr);
  const sourceSha = sourceIdentity.stdout.trim();
  const bin = path.join(inputs, 'bin');
  fs.mkdirSync(bin);
  // Host name is only a placement policy; keep this shell test usable in CI.
  if (os.hostname().split('.')[0] !== 'kkk2') {
    fs.writeFileSync(bin + '/hostname', '#!/bin/sh\nprintf "kkk2\\n"\n', {mode: 0o755});
  }
  const env = {...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    CJCJ_BOOTSTRAP_CPP_SRC: inputs,
    CJCJ_BOOTSTRAP_STDSRC: inputs,
    CJCJ_SRCBUILD_HOST_SDK: base,
    CJCJ_BOOTSTRAP_HOST_LLVM_SO: inputs + '/libLLVM-15.so',
    CJCJ_BOOTSTRAP_HOST_LLVM_SHA256: sha256(inputs + '/libLLVM-15.so'),
    CJCJ_BOOTSTRAP_AST_SUPPORT: inputs + '/ast.a',
    CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256: sha256(inputs + '/ast.a'),
    CJCJ_BOOTSTRAP_COLOUR_TUPLE: tuple,
    CJCJ_BOOTSTRAP_COLOUR_RT: runtimeCase === 'undeclared' ? '' : runtimeDir,
    CJCJ_BOOTSTRAP_COLOUR_RT_SHA256: runtimeCase === 'no-runtime-sha' ? '' : runtimeSha,
    CJCJ_BOOTSTRAP_BOUNDSCHECK_SHA256: runtimeCase === 'no-bounds-sha' ? '' : boundsSha,
    CJCJ_BOOTSTRAP_CJCJ_SHA: sourceSha,
  };
  delete env.CJCJ_BOOTSTRAP_SH;
  delete env.CJCJ_SRCBUILD_CPUSET;
  delete env.CJCJ_KKK2_AFFINED;
  if (child) {
    const entry = inputs + '/bootstrap child.sh';
    fs.writeFileSync(entry, '#!/bin/bash\nprintf "CHILD SDK_BUILD=%s\\n" "$SDK_BUILD"\nprintf "ARG=<%s>\\n" "$@"\nexit "${CHILD_RC:-0}"\n', {mode: 0o755});
    env.CJCJ_BOOTSTRAP_SH = entry;
  }
  return {
    root,
    runtimeDir,
    sourceSha,
    dryRun(step, sample) {
      const result = spawnSync('bash', [driver, '--from-step', String(step), '--through-step', String(step), '--dry-run'],
        {encoding: 'utf8', env});
      if (process.env.CJCJ_TEST_EVIDENCE) {
        const out = path.join(process.env.CJCJ_TEST_EVIDENCE, t.name.replaceAll(/[^a-zA-Z0-9]+/g, '-'), String(sample));
        fs.mkdirSync(out, {recursive: true});
        fs.writeFileSync(path.join(out, 'stdout.log'), result.stdout);
        fs.writeFileSync(path.join(out, 'stderr.log'), result.stderr);
        fs.writeFileSync(path.join(out, 'driver.rc'), `${result.status}\n`);
        fs.writeFileSync(path.join(out, 'identity.json'), JSON.stringify({driver: sha256(driver), test: sha256(import.meta.filename)}, null, 2) + '\n');
      }
      return result;
    },
    run(step, childRc = 0) {
      const result = spawnSync('bash', [driver, '--from-step', String(step), '--through-step', String(step)],
        {encoding: 'utf8', env: {...env, CHILD_RC: String(childRc)}});
      const logs = path.join(state, 'logs');
      const logFile = fs.readdirSync(logs).find(name => name.endsWith(`-step${step}.log`));
      assert.ok(logFile, result.stdout + result.stderr);
      const log = fs.readFileSync(path.join(logs, logFile), 'utf8');
      if (process.env.CJCJ_TEST_EVIDENCE) {
        const out = path.join(process.env.CJCJ_TEST_EVIDENCE, t.name.replaceAll(/[^a-zA-Z0-9]+/g, '-'), String(childRc));
        fs.mkdirSync(out, {recursive: true});
        fs.writeFileSync(path.join(out, 'driver.log'), result.stdout + result.stderr);
        fs.writeFileSync(path.join(out, 'step.log'), log);
        fs.writeFileSync(path.join(out, 'driver.rc'), `${result.status}\n`);
        fs.copyFileSync(path.join(state, 'kkk2-timings.tsv'), path.join(out, 'timings.tsv'));
        fs.writeFileSync(path.join(out, 'identity.json'), JSON.stringify({
          driver: sha256(driver), bootstrap: sha256(path.join(root, 'ci/bootstrap/bootstrap.sh')),
          sdkBuild: sha256(path.join(root, 'ci/bootstrap/sdk_build.sh')), test: sha256(import.meta.filename),
        }, null, 2) + '\n');
      }
      return {...result, log};
    },
  };
}

for (const step of [31, 32]) {
  test(`bootstrap driver step ${step} propagates pin mismatch`, t => {
    const result = bootstrapDriverFixture(t, {mismatch: true}).run(step);
    assert.match(result.log, /LLVM_DYLIB_SOURCE_MISMATCH/);
    assert.equal(result.status, 1, 'pin failure must reach driver exit');
    assert.match(result.stdout, new RegExp(`STEP=${step} .* rc=1 `));
    assert.doesNotMatch(result.stdout, /RESULT=success/);
    assert.doesNotMatch(result.log, /\[stage[01]\]/);
  });

  test(`bootstrap driver step ${step} rejects empty successful argv`, t => {
    const result = bootstrapDriverFixture(t, {empty: true}).run(step);
    assert.equal(result.status, 1, 'empty argv must fail before execution');
    assert.match(result.stdout, new RegExp(`STEP=${step} .* rc=1 `));
    assert.doesNotMatch(result.stdout, /RESULT=success/);
  });

  test(`bootstrap driver step ${step} rejects partial argv from a failed producer`, t => {
    const result = bootstrapDriverFixture(t, {partialFailure: true, child: true}).run(step);
    assert.equal(result.status, 1, 'producer failure must reject even nonempty argv');
    assert.match(result.stdout, new RegExp(`STEP=${step} .* rc=1 `));
    assert.doesNotMatch(result.log, /CHILD SDK_BUILD=/);
    assert.doesNotMatch(result.stdout, /RESULT=success/);
  });

  test(`bootstrap driver step ${step} executes quoted argv and propagates child status`, t => {
    const fixture = bootstrapDriverFixture(t, {child: true});
    for (const rc of [0, 23]) {
      const result = fixture.run(step, rc);
      assert.equal(result.status, rc, result.stdout + result.stderr);
      assert.match(result.log, /CHILD SDK_BUILD=.*\/ci\/bootstrap\/sdk_build.sh/);
      assert.ok(result.log.includes(`ARG=<${fixture.root}>`), 'space-containing source is one argument');
      assert.match(result.log, new RegExp(`ARG=<stage${step - 31}>`));
      assert.match(result.stdout, new RegExp(`STEP=${step} .* rc=${rc} `));
      if (rc === 0) assert.match(result.stdout, /RESULT=success/);
      else assert.doesNotMatch(result.stdout, /RESULT=success/);
    }
  });
}

test('bootstrap driver matching pins starts real stage0 and sdk_build', t => {
  const fixture = bootstrapDriverFixture(t);
  const result = fixture.run(31);
  assert.ok(result.log.includes(`ASSERT cjcj-sha expected=${fixture.sourceSha} actual=${fixture.sourceSha} source=git`), result.log);
  assert.match(result.log, /\[stage0\] official cjc/);
  // The deliberately incomplete SDK ends this bounded entry test before compilation.
  assert.match(result.log, /SDK-BUILD-FAIL .*不像 SDK（缺 bin\/cjc）/);
  console.log('OBSERVED real sdk_build input rejection after matching source pin');
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /STEP=31 .* rc=1 /);
  assert.doesNotMatch(result.stdout, /RESULT=success/);
});


test('P12 external runtime pin and both SO digests gate the actual bootstrap command', t => {
  const cases = {
    valid: 'COLOUR_RT_INPUT_VERIFIED',
    'old-pin': 'COLOUR_RT_PIN_MISMATCH',
    dirty: 'COLOUR_RT_PIN_MISMATCH',
    ambiguous: 'COLOUR_RT_PIN_MISMATCH',
    unstamped: 'COLOUR_RT_STAMP_MISSING',
    undeclared: 'COLOUR_RT_INPUT_REQUIRED',
    'no-runtime-sha': 'COLOUR_RT_SHA_REQUIRED',
    'no-bounds-sha': 'COLOUR_RT_SHA_REQUIRED',
    'runtime-corrupt': 'COLOUR_RT_SHA_MISMATCH',
    'bounds-corrupt': 'COLOUR_RT_SHA_MISMATCH',
    'bounds-missing': 'COLOUR_RT_FILE_MISSING',
  };
  const observed = [], expected = [];
  for (const [runtimeCase, marker] of Object.entries(cases)) {
    const fixture = bootstrapDriverFixture(t, {runtimeCase, child: true});
    for (const step of [31, 32]) {
      const result = fixture.dryRun(step, `${runtimeCase}-${step}`);
      const command = result.stdout.match(/^DRY_RUN COMMAND=(.*)$/m)?.[1] || '';
      const argv = command ? runBash(`eval "set -- $1"; printf '%s\\n' "$@"`, [command]).stdout.split('\n') : [];
      const valid = runtimeCase === 'valid';
      const row = {runtimeCase, step, rc: result.status, marker: result.stderr.includes(marker),
        runtime: argv[argv.indexOf('--colour-rt') + 1] || '',
        success: /^DRY_RUN RESULT=success/m.test(result.stdout)};
      observed.push(row);
      expected.push({runtimeCase, step, rc: valid ? 0 : 1, marker: true,
        runtime: valid ? fixture.runtimeDir : '', success: valid});
      console.log(`P12_ASSERT ${JSON.stringify(row)}`);
    }
  }
  // All product observations reach the target assertion, including failures.
  assert.deepEqual(observed, expected);
});
