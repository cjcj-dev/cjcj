import assert from 'node:assert/strict';
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

test('source-build CPU windows preserve explicit placement and derive their width', () => {
  const invoke = `source "$1" --lib-only\n`
    + 'test "$(explicit_cpuset 048-063)" = 48-63\n'
    + 'test "$(cpuset_width 48-63)" = 16\n'
    + 'test "$(cpuset_width 2-3,8,11-13)" = 6\n'
    + 'if explicit_cpuset 63-48; then exit 17; fi\n';
  const result = runBash(invoke, [scriptPath]);
  assert.equal(result.status, 0, result.stderr);
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
