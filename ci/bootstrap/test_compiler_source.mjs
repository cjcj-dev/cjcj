#!/usr/bin/env node
// Real source/header/shim and AST installation integration. Run on a build
// worker with a fetched compiler tree and an authenticated AST artifact.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const [cppArg, astArg, outArg] = process.argv.slice(2);
if (!outArg) throw new Error('usage: test_compiler_source.mjs <compiler> <AST artifact> <new output>');
const repo = path.resolve(import.meta.dirname, '../..');
const cpp = path.resolve(cppArg), ast = path.resolve(astArg), out = path.resolve(outArg);
fs.mkdirSync(out);
const pin = Object.fromEntries(fs.readFileSync(path.join(repo, 'ci/llvm_pin.env'), 'utf8')
  .split('\n').filter(line => /^[A-Z_]+=/.test(line)).map(line => line.split('=')));
const hash = file => fs.existsSync(file)
  ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : null;
const result = {commands: [], assertions: [], inputs: {}, started: new Date().toISOString()};
for (const file of ['ci/llvm_pin.env', 'ci/bootstrap/prepare_cpp_headers.mjs',
  'ci/install_std_sdk_inputs.py', 'runtime_shim/cjselfhost_llvmshim.cpp',
  'ci/bootstrap/test_compiler_source.mjs']) result.inputs[file] = hash(path.join(repo, file));
function save(rc) {
  result.rc = rc;
  fs.writeFileSync(path.join(out, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
}
function run(command, args, env = {}) {
  const file = path.join(out, `step-${result.commands.length}.log`);
  const fd = fs.openSync(file, 'w');
  const start = Date.now();
  const child = spawnSync(command, args, {cwd: repo, env: {...process.env, ...env}, stdio: ['ignore', fd, fd]});
  fs.closeSync(fd);
  result.commands.push({command: [command, ...args], rc: child.status, signal: child.signal,
    wall: (Date.now() - start) / 1000, log: file});
  console.log(`COMPILER_SOURCE_STEP rc=${child.status} command=${command} log=${file}`);
  if (child.status !== 0) { save(2); process.exit(2); }
  return fs.readFileSync(file, 'utf8').trim();
}
function check(name, actual, expected) {
  // Every target assertion is reported, even if an earlier invariant fails.
  let pass = true;
  try { assert.deepEqual(actual, expected); } catch { pass = false; }
  result.assertions.push({name, actual, expected, pass});
  console.log(`COMPILER_SOURCE_ASSERT ${name} ${pass ? 'PASS' : 'FAIL'} actual=${JSON.stringify(actual)}`);
}
const revision = run('git', ['-C', cpp, 'rev-parse', 'HEAD']);
run(process.execPath, ['ci/bootstrap/prepare_cpp_headers.mjs', cpp]);
const manifest = JSON.parse(fs.readFileSync(path.join(cpp, 'build/build/shim-headers.json')));
fs.copyFileSync(path.join(cpp, 'build/build/shim-headers.json'), path.join(out, 'shim-headers.json'));
fs.cpSync(path.join(repo, 'runtime_shim'), path.join(out, 'runtime_shim'), {recursive: true});
for (const file of fs.readdirSync(path.join(out, 'runtime_shim'))) {
  if (file.endsWith('.o')) fs.unlinkSync(path.join(out, 'runtime_shim', file));
}
run('bash', [path.join(out, 'runtime_shim/build_shim.sh')], {
  CANGJIE_CPP_SRC: cpp, CJCJ_LLVM_SHIM_O: '', CJCJ_COMMIT: 'compiler-source-integration',
});
const object = path.join(out, 'runtime_shim/cjselfhost_llvmshim.o');
result.shimSha256 = hash(object);
const symbols = run('nm', ['--defined-only', object]);
run('python3', ['ci/install_std_sdk_inputs.py', ast, path.join(out, 'sdk'), 'linux_x86_64_cjnative']);
const provenance = Object.fromEntries(fs.readFileSync(path.join(ast, 'PROVENANCE'), 'utf8')
  .split('\n').filter(Boolean).map(line => line.split('=')));
check('fetched-compiler-identity', revision, pin.CANGJIE_COMPILER_SHA);
check('shim-manifest-compiler-identity', manifest.compiler.sha, revision);
check('shim-cjo-schema-source', manifest.schema, {
  path: 'schema/CjoFormat.fbs', sha256: hash(path.join(cpp, 'schema/CjoFormat.fbs')),
});
check('compiled-shim-cjo-consumer', /^\S+ T CJOFPackageViewOpen$/m.test(symbols), true);
check('ast-compiler-identity', provenance.compiler, revision);
check('ast-schema-source', hash(path.join(ast, 'schema/StdAstFormat.fbs')),
  hash(path.join(cpp, 'schema/StdAstFormat.fbs')));
check('installed-schema-source', hash(path.join(out, 'sdk/schema/StdAstFormat.fbs')),
  hash(path.join(cpp, 'schema/StdAstFormat.fbs')));
check('installed-ast-archive', hash(path.join(out, 'sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a')),
  hash(path.join(ast, 'libcangjie-ast-support.a')));
check('installed-generated-ast-header', hash(path.join(out, 'sdk/include/flatbuffers/StdAstFormat_generated.h')),
  hash(path.join(ast, 'include/flatbuffers/StdAstFormat_generated.h')));
save(result.assertions.every(item => item.pass) ? 0 : 1);
process.exitCode = result.rc;
