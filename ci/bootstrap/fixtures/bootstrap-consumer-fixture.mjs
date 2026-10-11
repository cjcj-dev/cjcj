#!/usr/bin/env zx
// Bootstrap tests consume the same complete plans and genuine small native
// producers as SDK consumers. This contains no SDK assembler or receipt writer.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {fixture, assemble, good, observe, tuple, readJson, fileDigest, atomicJson} from './sdk-consumer-fixture.mjs';
import {buildIdentities, validatePlan, resolveFiles, readOutput, objectId} from '../sdk-manifest.mjs';
import {BOOTSTRAP_PHASES, validateBootstrapPlans} from '../freeze-bootstrap-plans.mjs';
const here = path.dirname(fileURLToPath(new URL('../bootstrap.sh', import.meta.url)));
const repo = path.resolve(here, '../..');
export const write = async (file, bytes) => {await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, bytes);};
export async function bootstrapFixture() {
  const compiler = {'cjpm.toml': 'compile-option = "-O2"\n', 'main.cj': 'main() {}\n'};
  for (const rel of ['ci/build_resources.sh', 'ci/install_std_sdk_inputs.py', 'ci/host-toolchain-pin.mjs',
    'ci/host_sdk_pin.env', 'ci/runtime-pin.mjs', 'ci/runtime_pin.env']) {
    compiler[rel] = await fs.readFile(path.join(repo, rel));
  }
  // Preserve the actual phase entry and its local module closure under SRC.
  // The logged bootstrap call is executable too; a copied entry without its
  // imports must never fail at loading instead of reaching the phase assertion.
  const copied = new Set();
  async function moduleClosure(file) {
    file = path.resolve(file);
    assert.ok(file.startsWith(`${repo}${path.sep}`), 'product module must belong to this cjcj checkout');
    if (copied.has(file)) return;
    copied.add(file);
    const bytes = await fs.readFile(file); compiler[path.relative(repo, file)] = bytes;
    for (const match of bytes.toString().matchAll(/(?:from\s*|import\s*\(\s*)['"](\.[^'"]+\.mjs)['"]/g)) {
      await moduleClosure(path.resolve(path.dirname(file), match[1]));
    }
  }
  await moduleClosure(path.join(here, 'bootstrap-sdk.mjs'));
  // Non-module command dependencies of the copied phase verifier are original
  // files as well. They are never replaced by success stand-ins.
  for (const rel of ['ci/bootstrap/sdk_verify.py', 'ci/bootstrap/compiler_identity.py',
    'ci/bootstrap/std_runtime_colour.py', 'ci/llvm-dylib/verify.py']) compiler[rel] = await fs.readFile(path.join(repo, rel));
  const host = await fixture({role: 'host', sources: {compiler}});
  const target = await fixture({sources: {compiler}});
  good(await assemble(host, 'host-plan-input'));
  good(await assemble(target, 'target-plan-input'));
  const identities = buildIdentities(target.plan);
  const root = host.root, src = host.sources.compiler.repo;
  const cpp = path.join(root, 'cpp-src');
  for (const rel of ['third_party/llvm-project/llvm/include', 'build/build/third_party/llvm/include', 'build/build/include', 'build/build/schema']) {
    await write(path.join(cpp, rel, 'fixture.h'), '// controlled header fixture\n');
  }
  const stdsrc = path.join(root, 'stdsrc'); await write(path.join(stdsrc, 'build.py'), '# native bootstrap observer input\n');
  const ast = path.join(root, 'ast-input');
  await write(path.join(ast, 'libcangjie-ast-support.a'), await fs.readFile(path.join(host.out, 'lib', tuple, 'libcangjie-ast-support.a')));
  await fs.mkdir(path.join(ast, 'third_party/flatbuffers/bin'), {recursive: true});
  await fs.copyFile('/bin/true', path.join(ast, 'third_party/flatbuffers/bin/flatc'));
  for (const directory of ['include', 'schema']) await write(path.join(ast, directory, 'fixture.h'), 'AST input\n');
  await write(path.join(ast, 'SHA256SUMS'), (await Promise.all(['libcangjie-ast-support.a', 'third_party/flatbuffers/bin/flatc'].map(async rel =>
    `${await fileDigest(path.join(ast, rel))}  ${rel}\n`))).join(''));
  const phases = {};
  for (const phase of BOOTSTRAP_PHASES) {
    const selected = ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? host : target;
    const plan = structuredClone(selected.plan);
    if (['stage0-run', 'std-bootstrap'].includes(phase)) {
      // cjcj/initial std execute with the host runtime/std pair, while their
      // native LLVM inputs come from the exact declared target LLVM source.
      // These remain real recipes; no target receipt is relabelled as host.
      for (const id of ['llvm-tools', 'llvm-dylib']) {
        const component = plan.components.find(row => row.id === id);
        const native = target.plan.components.find(row => row.id === id);
        component.source = structuredClone(native.source);
        component.config.options.parameters = structuredClone(native.config.options.parameters);
      }
    }
    // Distinct std generation is declared before identities are computed;
    // this is a recipe input, never a copied success receipt.
    if (phase === 'stage1-std') plan.components.find(row => row.id === 'std').config.options.parameters.generation = 'second';
    plan.stage = phase === 'stage3' ? 'final' : ['stage2', 'stage3-std'].includes(phase) ? 'stage2' : 'stage1';
    phases[phase] = validatePlan(plan);
  }
  const bundle = validateBootstrapPlans({schema: 'bootstrap-sdk-plans-v1', phases});
  const plans = path.join(root, 'bundle.frozen.json'); await atomicJson(plans, bundle);
  const colourTuple = path.join(identities.get('llvm-tools').directory, 'artifacts');
  const hostSo = path.join(host.out, 'third_party/llvm/lib/libLLVM-15.so');
  const colourSo = path.join(identities.get('llvm-dylib').directory, 'artifacts/libLLVM-15.so');
  return {root, host, target, bundle, plans, src, cpp, stdsrc, ast,
    work: path.join(root, 'work'), colourTuple, hostSo, colourSo,
    hostSha: await fileDigest(hostSo), colourSoSha: await fileDigest(colourSo),
    astFile: path.join(ast, 'libcangjie-ast-support.a'), astSha: await fileDigest(path.join(ast, 'libcangjie-ast-support.a')),
    colourSha: target.sources.llvm.commit, sourceSha: host.sources.compiler.commit,
    hostRuntime: path.join(host.out, 'runtime/lib', tuple), colourRuntime: path.join(target.out, 'runtime/lib', tuple)};
}
export function bootstrapArgs(f, phase = 'all') {
  return ['--work', f.work, '--src', f.src, '--cjcj-sha', f.sourceSha, '--stdsrc', f.stdsrc, '--cpp-src', f.cpp,
    '--base', f.host.plan.components.find(row => row.id === 'official').source.root,
    '--host-llvm-so', f.hostSo, '--host-llvm-sha256', f.hostSha, '--colour-llvm-so', f.colourSo,
    '--colour-llvm-sha256', f.colourSoSha, '--ast-support', f.astFile, '--ast-support-sha256', f.astSha,
    '--colour-tuple', f.colourTuple, '--colour-llvm-sha', f.colourSha, '--colour-rt', f.colourRuntime,
    '--host-rt', f.hostRuntime, '--sdk-plans', f.plans, '--runtime-pin', f.target.plan.verification.runtimePin.path,
    '--stage', phase, '--dry-run'];
}
let phaseSequence = 0;
export async function loadPhaseResultFixture(input) {
  const saved = await readJson(input);
  assert.equal(path.resolve(input), path.join(saved.root, 'phase-causal-input.json'), 'original phase input descriptor must remain under its fixture root');
  assert.equal(saved.plans, path.join(saved.root, 'bundle.frozen.json'));
  const bundle = validateBootstrapPlans(await readJson(saved.plans));
  assert.equal(saved.hostRoot, saved.root);
  assert.equal(saved.src, bundle.phases.stage0.components.find(component => component.id === 'compiler').source.repo);
  return {root: saved.root, plans: saved.plans, src: saved.src, host: {root: saved.hostRoot}, bundle};
}
export async function qualifyBootstrapPhases(f, phases) {
  f.phaseQualifications ||= new Map();
  // Test input locator only. It does not contain a plan, receipt or success
  // claim; all original objects below are read and qualified independently.
  const input = path.join(f.root, 'phase-causal-input.json');
  const descriptor = {root: f.root, plans: f.plans, src: f.src, hostRoot: f.host.root};
  try { assert.deepEqual(await readJson(input), descriptor); }
  catch (error) { if (error.code !== 'ENOENT') throw error; await atomicJson(input, descriptor); }
  // Use the direct SDK CLI, independently of bootstrap-sdk's phase selector.
  // Complete every permitted alternate phase before running a selected-phase
  // target. A wrong selection must not be rejected merely for absent receipts.
  for (const phase of phases) {
    if (f.phaseQualifications.has(phase)) continue;
    const plan = f.bundle.phases[phase], expected = buildIdentities(plan);
    const label = `phase-${phase}-qualification`, planFile = path.join(f.root, `${label}.json`);
    const out = path.join(f.root, `${label}-sdk`);
    try { assert.deepEqual(await readJson(planFile), plan); }
    catch (error) { if (error.code !== 'ENOENT') throw error; await atomicJson(planFile, plan); }
    const argv = [process.execPath, path.join(f.src, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', planFile, '--out', out];
    let result;
    try {
      result = await readJson(path.join(f.host.root, `${label}-assembly.json`));
      assert.deepEqual(result.argv, argv, 'retained qualification must come from the exact direct SDK entry and original input');
      console.log(`PHASE_REUSED_QUALIFICATION phase=${phase} evidence=${f.host.root} rc=${result.rc}`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      result = await observe(f.host, `${label}-assembly`, argv);
    }
    good(result); // A failing legal control is a contract/input failure, never a phase cut success.
    const manifest = await readJson(path.join(out, 'SDK.manifest.json')), outputs = new Map();
    assert.equal(manifest.planSha256, objectId(plan));
    for (const component of plan.components) {
      const receipt = await readOutput(component.producer.receipt || expected.get(component.id).directory,
        component, expected.get(component.id));
      outputs.set(component.id, receipt);
      assert.equal(manifest.components[component.id].buildId, receipt.buildId);
      assert.equal(manifest.components[component.id].receiptSha256, receipt.receiptSha256);
    }
    const files = resolveFiles(plan, outputs), module = `modules/${tuple}/std/core/core.Int64.ti`;
    assert.deepEqual(manifest.files, {...files});
    const stdModuleSha256 = await fileDigest(path.join(out, module));
    const compilerSha256 = await fileDigest(path.join(out, 'bin/cjc'));
    const stdProducer = await readJson(path.join(out, 'std-producer.json'));
    assert.equal(stdModuleSha256, files[module].sha256);
    assert.equal(stdProducer.compiler_sha256, compilerSha256, `PHASE_CONTROL_STD_CJC phase=${phase}`);
    const qualified = {phase, planSha256: objectId(plan), stdModuleSha256, compilerSha256,
      stdCompilerSha256: stdProducer.compiler_sha256, stdBuildId: outputs.get('std').buildId,
      files: {...files}, receipts: Object.fromEntries([...outputs].map(([id, receipt]) => [id,
        {buildId: receipt.buildId, receiptSha256: receipt.receiptSha256}]))};
    f.phaseQualifications.set(phase, qualified);
    const qualificationFile = path.join(f.root, `${label}-result.json`);
    try { assert.deepEqual(await readJson(qualificationFile), qualified); }
    catch (error) { if (error.code !== 'ENOENT') throw error; await atomicJson(qualificationFile, qualified); }
    console.log(`PHASE_INPUT_QUALIFIED ${JSON.stringify(qualified)}`);
  }
}
async function phaseObservation(operation) {
  try { return {value: await operation()}; }
  catch (error) { return {error: {code: error.code ?? null, message: error.message}}; }
}
export async function phaseIdentities(f, phase, productRoot = path.join(f.src, 'ci/bootstrap')) {
  const qualified = f.phaseQualifications?.get(phase);
  assert.ok(qualified, `phase ${phase} and all cut alternates must be independently qualified first`);
  const label = `phase-${phase}-${++phaseSequence}`, armRoot = process.env.SDK_PHASE_WORK_ROOT || f.root;
  assert.ok(path.isAbsolute(armRoot), 'SDK_PHASE_WORK_ROOT must name an exclusively owned absolute arm directory');
  await fs.mkdir(armRoot, {recursive: true});
  const out = path.join(armRoot, `${label}-sdk`);
  const result = await observe({root: armRoot}, `${label}-assemble`, [process.execPath, path.join(productRoot, 'bootstrap-sdk.mjs'),
    '--plans', f.plans, '--phase', phase, '--out', out]);
  // Read actual output before any fatal assertion. Missing output is recorded,
  // not thrown by a stat/readFile that would hide the selected-phase assertion.
  const manifest = await phaseObservation(() => readJson(path.join(out, 'SDK.manifest.json')));
  const std = await phaseObservation(() => fileDigest(path.join(out, `modules/${tuple}/std/core/core.Int64.ti`)));
  const compiler = await phaseObservation(() => fileDigest(path.join(out, 'bin/cjc')));
  const producer = await phaseObservation(() => readJson(path.join(out, 'std-producer.json')));
  const observation = {phase, result, manifest, std, compiler, producer};
  await atomicJson(path.join(armRoot, `${label}-observation.json`), observation);
  console.log(`PHASE_RESULT_OBSERVED ${JSON.stringify(observation)}`);
  assert.equal(result.rc, 0, `PHASE_RESULT_EXECUTION_QUALIFICATION: a missing receipt/loading/STD_CJC failure is not phase selection evidence: ${result.stderr}`);
  const actual = {planSha256: manifest.value?.planSha256, stdModuleSha256: std.value,
    compilerSha256: compiler.value, stdCompilerSha256: producer.value?.compiler_sha256,
    stdBuildId: manifest.value?.components?.std?.buildId};
  const wanted = {planSha256: qualified.planSha256, stdModuleSha256: qualified.stdModuleSha256,
    compilerSha256: qualified.compilerSha256, stdCompilerSha256: qualified.stdCompilerSha256, stdBuildId: qualified.stdBuildId};
  console.log(`TARGET_ASSERTION_BEGIN bootstrap-phase-result phase=${phase} actual=${JSON.stringify(actual)} expected=${JSON.stringify(wanted)}`);
  assert.deepEqual(actual, wanted, 'bootstrap-phase-result: selected phase must install its own authenticated std and compiler identities');
  console.log(`TARGET_ASSERTION_PASS bootstrap-phase-result phase=${phase}`);
  assert.deepEqual(manifest.value.files, {...qualified.files});
  for (const [id, receipt] of Object.entries(qualified.receipts)) {
    assert.equal(manifest.value.components[id].buildId, receipt.buildId);
    assert.equal(manifest.value.components[id].receiptSha256, receipt.receiptSha256);
  }
  const dryOut = path.join(armRoot, `${label}-dry`);
  const dryResult = await observe({root: armRoot}, `${label}-identities`, [process.execPath, path.join(productRoot, 'bootstrap-sdk.mjs'),
    '--plans', f.plans, '--phase', phase, '--out', dryOut, '--dry-run']);
  good(dryResult);
  const rows = JSON.parse(dryResult.stdout.trim().split('\n').at(-1)).components;
  const expected = buildIdentities(f.bundle.phases[phase]);
  console.log(`ASSERT bootstrap-phase-identities executed phase=${phase} rows=${JSON.stringify(rows)}`);
  assert.deepEqual(Object.fromEntries(rows.map(row => [row.component, {buildId: row.buildId, directory: row.directory, dependencies: row.dependencies}])),
    Object.fromEntries([...expected].map(([id, row]) => [id, {buildId: row.buildId, directory: row.directory, dependencies: row.dependencies}])));
  await assert.rejects(fs.access(dryOut));
  return {stdModuleSha256: actual.stdModuleSha256, stdBuildId: actual.stdBuildId};
}
export async function installedMembers(f, roles) {
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  const outputs = new Map();
  for (const component of f.plan.components) {
    const identity = f.identities.get(component.id);
    outputs.set(component.id, await readOutput(component.producer.receipt || identity.directory, component, identity));
  }
  const declared = resolveFiles(f.plan, outputs);
  for (const [rel, row] of Object.entries(declared)) if (roles.some(role => f.plan.components.find(c => c.id === row.component).roles.includes(role))) {
    assert.deepEqual(manifest.files[rel], row);
    if (row.type !== 'directory') assert.equal(await fileDigest(path.join(f.out, rel)), row.sha256, rel);
  }
  return {manifest, outputs, declared};
}
