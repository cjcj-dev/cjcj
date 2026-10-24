// Execute the actual workflow run body. Stop at its first CMake call on Linux;
// this observes caller wiring, not Windows/MSYS2 or full LLVM production.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {load} from '../vendor/js-yaml/js-yaml.mjs';
const repo = path.resolve(import.meta.dirname, '../..');
const evidence = process.env.G2_WORKFLOW_EVIDENCE;
assert.ok(evidence && path.isAbsolute(evidence), 'private G2_WORKFLOW_EVIDENCE required');
fs.mkdirSync(evidence);
const workflow = load(fs.readFileSync(path.join(repo, '.github/workflows/build-llvm-tools.yml'), 'utf8'));
const step = workflow.jobs['build-tools'].steps.find(item => item.name === 'Build Windows LLVM tools');
assert.equal(step.shell, 'msys2 {0}');
assert.equal(step.if, "runner.os == 'Windows' && steps.cache.outputs.cache-hit != 'true'");
const base = {...process.env};
for (const key of Object.keys(base)) if (/^(CJCJ_LLVM_RUNTIME_|CJCJ_SRCBUILD_|TUPLE_|LLVM_|CANGJIE_COMPILER_|FLATBUFFERS_)/.test(key)) delete base[key];
delete base.RUNTIME_REF; delete base.RUNTIME_SRC_URL; delete base.NODE_TEST_CONTEXT;
function execute(label, command, cwd, env = base) {
  const out = fs.openSync(path.join(evidence, `${label}.stdout`), 'wx');
  const err = fs.openSync(path.join(evidence, `${label}.stderr`), 'wx');
  const result = spawnSync(command[0], command.slice(1), {cwd, env, stdio: ['ignore', out, err]});
  fs.closeSync(out); fs.closeSync(err);
  fs.writeFileSync(path.join(evidence, `${label}.json`), JSON.stringify({command, cwd, rc: result.status, signal: result.signal, error: result.error?.message}, null, 2));
  assert.equal(result.error, undefined); assert.equal(result.signal, null);
  return {rc: result.status, stdout: fs.readFileSync(path.join(evidence, `${label}.stdout`), 'utf8'), stderr: fs.readFileSync(path.join(evidence, `${label}.stderr`), 'utf8')};
}
let index = 0;
function git(cwd, ...args) {
  const result = execute(`git-${index++}`, ['git', ...args], cwd);
  assert.equal(result.rc, 0, result.stderr); return result.stdout.trim();
}
const input = path.join(evidence, 'source input'); fs.mkdirSync(input);
for (const [file, body] of Object.entries({
  'schema/ModuleFormat.fbs': 'table Fixture {}\n',
  'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h': 'enum EnumReflectionType {\n  ERT_NONE,\n};\n',
  'CMakeLists.txt': 'cmake_minimum_required(VERSION 3.16)\n',
  'runtime/tools/generate-runtime-layout.py': '# finite source transport\n',
})) { fs.mkdirSync(path.dirname(path.join(input, file)), {recursive: true}); fs.writeFileSync(path.join(input, file), body); }
git(input, 'init'); git(input, 'add', '.');
git(input, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'finite workflow transport');
const sha = git(input, 'rev-parse', 'HEAD');
const url = 'https://github.com/cjcj-dev/cangjie-runtime.git';
function invoke(label, changes = {}) {
  const cwd = path.join(evidence, label); fs.mkdirSync(cwd); fs.mkdirSync(path.join(cwd, 'bin'));
  fs.symlinkSync(path.join(repo, 'ci'), path.join(cwd, 'ci'));
  const capture = path.join(cwd, 'cmake.json');
  fs.writeFileSync(path.join(cwd, 'bin/cmake'), `#!${process.execPath}\nrequire('node:fs').writeFileSync(process.env.G2_CMAKE_CAPTURE, JSON.stringify(process.argv.slice(2))); process.exit(86);\n`, {mode: 0o755});
  const env = {...base, ...step.env, TUPLE_PLATFORM: 'windows_x86_64', LLVM_TARGETS: 'X86',
    CJCJ_LLVM_RUNTIME_MODE: 'private', CJCJ_LLVM_RUNTIME_URL: url, CJCJ_LLVM_RUNTIME_SHA: sha,
    CJCJ_SRCBUILD_REQUIRE_MIRRORS: '1', CJCJ_SRCBUILD_SOURCE_MIRRORS: `${url}=file://${input};file://${input}=file://${input}`,
    LLVM_URL: `file://${input}`, LLVM_SHA: sha, CANGJIE_COMPILER_URL: `file://${input}`, CANGJIE_COMPILER_SHA: sha,
    FLATBUFFERS_URL: `file://${input}`, FLATBUFFERS_SHA: sha, G2_CMAKE_CAPTURE: capture,
    GIT_TRACE: path.join(cwd, 'fetch.trace'), PATH: `${path.join(cwd, 'bin')}:${base.PATH}`, ...changes};
  fs.writeFileSync(path.join(cwd, 'workflow-command.json'), JSON.stringify({run: step.run, env: Object.fromEntries(Object.entries(env).filter(([key]) => !(key in base)))}, null, 2));
  return {cwd, capture, ...execute(label, ['bash', '-e', '-o', 'pipefail', '-c', step.run], cwd, env)};
}
test('workflow fetches selected runtime and passes it to the actual build entry', () => {
  const result = invoke('normal');
  console.log(`WORKFLOW_TARGET_ASSERT_REACHED first_cmake_rc=${result.rc} expected=86`);
  assert.equal(result.rc, 86, result.stdout + result.stderr);
  const args = JSON.parse(fs.readFileSync(result.capture, 'utf8'));
  const runtime = path.join(result.cwd, step.env.TUPLE_ROOT, 'paired-runtime');
  assert.deepEqual(args.filter(arg => arg.startsWith('-DCANGJIE_RUNTIME_SOURCE_DIR=')), [`-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`]);
  assert.equal(git(runtime, 'rev-parse', 'HEAD'), sha);
  assert.equal(git(runtime, 'status', '--porcelain'), '');
  assert.ok(args.includes('-DLLVM_ENABLE_LIBXML2=OFF'));
  console.log('WORKFLOW_TARGET_ASSERT_PASS selected_runtime_cmake');
});
test('workflow rejects malformed runtime input before any fetch independently', () => {
  const result = invoke('invalid', {CJCJ_LLVM_RUNTIME_SHA: 'short'});
  console.log(`WORKFLOW_CONTROL_ASSERT_REACHED rc=${result.rc}`);
  assert.equal(result.rc, 1);
  assert.match(result.stdout + result.stderr, /40-digit SHA/);
  assert.equal(fs.existsSync(result.capture), false);
  assert.equal(fs.existsSync(path.join(result.cwd, step.env.TUPLE_ROOT, 'llvm-project')), false);
  const trace = path.join(result.cwd, 'fetch.trace');
  assert.ok(!fs.existsSync(trace) || !fs.readFileSync(trace, 'utf8').includes(' fetch '));
  console.log('WORKFLOW_CONTROL_ASSERT_PASS input_rejection');
});
