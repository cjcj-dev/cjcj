#!/usr/bin/env zx
// Small explicit fixtures: real stdlib_build receipt calls and bootstrap CLI
// resume validation, not a real compiler/std/stage2 production claim.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const product = path.dirname(fileURLToPath(import.meta.url));
const root = fs.mkdtempSync(path.join(process.env.TEST_TMPDIR || os.tmpdir(), 'std-receipt-fixture-'));
const logRoot = process.env.RECEIPT_TEST_LOG || root;
fs.mkdirSync(logRoot, {recursive: true});
const put = (file, text) => {fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text);};
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function run(command, args, options = {}) {
  const result = spawnSync(command, args, {encoding: 'utf8', ...options});
  if (result.error) throw result.error;
  return result;
}
function good(command, args, options) {
  const result = run(command, args, options);
  assert.equal(result.status, 0, `${command} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}
const source = path.join(root, 'runtime');
const stdSource = path.join(source, 'stdlib');
put(path.join(stdSource, 'build.py'), `import os,sys\nif sys.argv[1] == 'install':\n p=sys.argv[sys.argv.index('--prefix')+1]\n for name in ['lib/a.a','modules/a.cjo','runtime/lib/a.so']:\n  f=os.path.join(p,name); os.makedirs(os.path.dirname(f),exist_ok=True);open(f,'w').write('fixture std payload')\n`);
good('git', ['init', '-q', source]);
const git = (...args) => good('git', ['-C', source, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', ...args]);
git('add', '.'); git('commit', '-qm', 'fixture std source');
const original = git('rev-parse', 'HEAD');
put(path.join(stdSource, 'different'), 'different tree'); git('add', '.'); git('commit', '-qm', 'different fixture tree');
const different = git('rev-parse', 'HEAD'); git('checkout', '-q', original);
const src = path.join(root, 'cjcj');
fs.cpSync(product, path.join(src, 'ci/bootstrap'), {recursive: true});
for (const name of ['runtime-pin.mjs', 'runtime_pin.env']) fs.copyFileSync(path.join(product, '..', name), path.join(src, 'ci', name));
put(path.join(src, 'cjpm.toml'), '# fixture\n');
put(path.join(src, 'ci/build_resources.sh'), 'configure_build_resources() { STD_BUILD_HEAP=1GB; STD_BUILD_JOBS=1; }\n');
put(path.join(src, 'ci/install_std_sdk_inputs.py'), '# fixture external input installer\n');
const sdk = path.join(root, 'host');
const compiler = path.join(sdk, 'bin/cjc'); fs.mkdirSync(path.dirname(compiler), {recursive: true}); fs.copyFileSync('/bin/true', compiler);
put(path.join(sdk, 'tools/bin/cjpm'), '# fixture never executed\n'); fs.chmodSync(path.join(sdk, 'tools/bin/cjpm'), 0o755);
const work = path.join(root, 'work'); const prefix = path.join(work, 'stdlib-stage1');
const q = s => `'${s.replaceAll("'", "'\\''")}'`;
// Keep actual stdlib_build and cmd; replace only unrelated heavy fixture
// infrastructure. build.py performs a genuine small install into a fresh prefix.
const produce = `source ${q(path.join(src, 'ci/bootstrap/bootstrap.sh'))}; SRC=${q(src)}; STDSRC=${q(stdSource)}; WORK=${q(work)}; AST_SUPPORT=${q(path.join(root, 'ast'))}; HOST_TUPLE=linux_x86_64_cjnative; sdk_ld_path() { printf ''; }; prepare_build_env() { BUILD_TMPDIR=${q(root)}; }; assert_std_install_shape() { test -f "$1/modules/a.cjo" || exit 31; }; stdlib_build fixture ${q(sdk)} ${q(root)} ${q(prefix)}`;
const produced = run('bash', ['-c', produce]);
put(path.join(logRoot, 'producer.log'), produced.stdout + produced.stderr);
put(path.join(logRoot, 'producer.rc'), `${produced.status}\n`);
assert.equal(produced.status, 0, produced.stdout + produced.stderr);
assert(fs.existsSync(path.join(prefix, 'STDLIB_SOURCE_SHA')), 'FRESH_SOURCE_RECEIPT');
assert.equal(fs.readFileSync(path.join(prefix, 'STDLIB_SOURCE_SHA'), 'utf8').trim(), original, 'FRESH_SOURCE_RECEIPT');
console.log('ASSERT FRESH_SOURCE_RECEIPT REACHED PASS');
const receiptPath = path.join(prefix, 'std-producer.json');
const receipt = JSON.parse(fs.readFileSync(receiptPath));
assert(receipt.files.some(item => item.path === 'modules/a.cjo'));
fs.copyFileSync(compiler, path.join(work, 'cjcj-stage1'));
const so = path.join(work, 'sdk-stage1/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so');
put(so, `fixture\0CJRT-COMMIT:${original}\0`);
const lockPath = path.join(work, 'sdk-stage1/SDK.lock.json');
const compilerSha = hash(compiler);
const lock = {components: {cjc: {sha256: compilerSha}, runtime: {commit: original, so_sha256: hash(so)}}};
put(lockPath, JSON.stringify(lock));
const sums = path.join(root, 'captured.sha256');
put(sums, `${hash(path.join(prefix, 'lib/a.a'))}  lib/a.a\n`); // deliberately partial: receipt must cover the rest
const pin = path.join(root, 'pin.env');
const formal = fs.readFileSync(path.join(src, 'ci/runtime_pin.env'), 'utf8');
const url = formal.match(/^RUNTIME_SRC_URL=(.*)$/m)[1];
put(pin, `RUNTIME_REF=${original}\nRUNTIME_SRC_URL=${url}\n`);
const ids = path.join(root, 'host-identities'); put(ids, 'explicit fixture');
const llvm = path.join(root, 'llvm'); put(llvm, 'fixture LLVM');
const ast = path.join(root, 'ast'); put(ast, 'fixture AST');
const tuple = path.join(root, 'tuple');
const llvmSha = 'a'.repeat(40);
const payloads = ['MANIFEST','bin/llc','bin/opt','bin/ld.lld','lib/STATIC_LLVM.txt','fixed-llc/cjselfhost_llvmshim.o','fixed-llc/llc.gz','fixed-llc/opt.gz','fixed-llc/ld.lld.gz','fixed-llc/llvm-tools.manifest'];
for (const name of payloads) put(path.join(tuple, name), name === 'MANIFEST' ? `LLVM_SHA=${llvmSha}\n` : name === 'bin/opt' ? `CJLLVM-COMMIT:${llvmSha}\n` : 'fixture');
put(path.join(tuple, 'SHA256SUMS'), payloads.map(name => `${hash(path.join(tuple, name))}  ./${name}\n`).join(''));
const args = [path.join(src,'ci/bootstrap/bootstrap.sh'),'--stage','supplied-stage1','--check-only','--resume-colour-gate',sums,'--work',work,'--src',src,'--cjcj-sha','b'.repeat(40),'--stdsrc',stdSource,'--stage1-elf',compiler,'--stage1-sha256',compilerSha,'--host-sdk',sdk,'--runtime-sha',original,'--runtime-pin',pin,'--colour-gate-source',source,'--colour-gate-install',root,'--host-identities',ids,'--host-identities-sha256',hash(ids),'--host-llvm-so',llvm,'--host-llvm-sha256',hash(llvm),'--colour-llvm-so',llvm,'--colour-llvm-sha256',hash(llvm),'--ast-support',ast,'--ast-support-sha256',hash(ast),'--colour-tuple',tuple,'--colour-llvm-sha',llvmSha,'--colour-rt',path.dirname(so),'--host-rt',path.dirname(so)];
const env = {...process.env, npm_config_offline:'true', CJCJ_ALLOW_RUNTIME_OVERRIDE:'1',CJCJ_RUNTIME_REF_OVERRIDE:original}; delete env.LD_LIBRARY_PATH; delete env.CANGJIE_HOME;
let n = 0;
function check(name, expected) {
 const r = run('bash', args, {env}); const text = r.stdout + r.stderr;
 put(path.join(logRoot, `${++n}-${name}.log`), text); put(path.join(logRoot,`${n}-${name}.rc`),`${r.status}\n`);
 if (!expected) {assert.equal(r.status,0,text); assert.match(text,/SUPPLIED-STAGE1-INPUTS-OK/);}
 else {assert.notEqual(r.status,0,`expected ${expected}\n${text}`); assert(text.includes(expected),`expected ${expected}\n${text}`);}
 console.log(`ASSERT ${name} REACHED PASS child_rc=${r.status}`);
}
check('normal');
const originalReceipt = fs.readFileSync(receiptPath);
const originalStamp = fs.readFileSync(path.join(prefix,'STDLIB_SOURCE_SHA'));
function mutation(name, apply, restore, expected) {apply(); check(name,expected); restore(); check(`${name}-restored`);}
mutation('source-tree',()=>{put(path.join(prefix,'STDLIB_SOURCE_SHA'),different);put(receiptPath,JSON.stringify({...receipt,source_commit:different,source_tree:git('rev-parse',`${different}:stdlib`)}));},()=>{put(path.join(prefix,'STDLIB_SOURCE_SHA'),originalStamp);put(receiptPath,originalReceipt);},'RESUME_STD_TREE_MISMATCH');
const moduleFile=path.join(prefix,'modules/a.cjo'); const moduleBytes=fs.readFileSync(moduleFile);
mutation('module-bytes',()=>put(moduleFile,'changed'),()=>put(moduleFile,moduleBytes),'RESUME_STD_PREFIX_MISMATCH');
mutation('prefix-added',()=>put(path.join(prefix,'runtime/lib/extra.so'),'extra'),()=>fs.unlinkSync(path.join(prefix,'runtime/lib/extra.so')),'RESUME_STD_PREFIX_MISMATCH');
mutation('producer-compiler',()=>put(receiptPath,JSON.stringify({...receipt,compiler_sha256:'0'.repeat(64)})),()=>put(receiptPath,originalReceipt),'RESUME_STD_COMPILER_MISMATCH');
mutation('sdk-compiler',()=>put(lockPath,JSON.stringify({components:{...lock.components,cjc:{sha256:'0'.repeat(64)}}})),()=>put(lockPath,JSON.stringify(lock)),'RESUME_SDK_COMPILER_MISMATCH');
const runtimeBytes=fs.readFileSync(so);
mutation('runtime-bytes',()=>put(so,'changed runtime'),()=>put(so,runtimeBytes),'RESUME_SDK_RUNTIME_HASH_MISMATCH');
mutation('runtime-stamp',()=>put(lockPath,JSON.stringify({components:{...lock.components,runtime:{...lock.components.runtime,commit:different}}})),()=>put(lockPath,JSON.stringify(lock)),'RESUME_SDK_RUNTIME_MISMATCH');
mutation('incomplete-production',()=>put(path.join(prefix,'.std-production.json'),'{}'),()=>fs.unlinkSync(path.join(prefix,'.std-production.json')),'RESUME_STD_RECEIPT_INVALID');
const beforeFailure = fs.readFileSync(path.join(stdSource,'build.py'));
put(path.join(stdSource,'build.py'), 'import sys\nsys.exit(37)\n'); git('add','.'); git('commit','-qm','fixture failed producer');
const reusedProduction=run('bash',['-c',produce]);
assert.notEqual(reusedProduction.status,0,'STALE_PREFIX_REJECTED');
assert((reusedProduction.stdout+reusedProduction.stderr).includes('STD_PREFIX_PRODUCER_MISMATCH'),'STALE_PREFIX_TARGET');
assert.equal(fs.readFileSync(receiptPath,'utf8'),originalReceipt.toString(),'REJECT_PRESERVES_VALID_RECEIPT');
const failedPrefix=path.join(work,'failed-stdlib');
const failedProduce=produce.replace(q(prefix),q(failedPrefix));
const failedProduction=run('bash',['-c',failedProduce]);
put(path.join(logRoot,'failed-producer.log'),failedProduction.stdout+failedProduction.stderr);put(path.join(logRoot,'failed-producer.rc'),`${failedProduction.status}\n`);
assert.equal(failedProduction.status,37,'FAILED_PRODUCER_RC_PRESERVED');
assert(!fs.existsSync(path.join(failedPrefix,'std-producer.json')),'FAILED_PRODUCER_NO_SUCCESS_RECEIPT');
assert(!fs.existsSync(path.join(failedPrefix,'STDLIB_SOURCE_SHA')),'FAILED_PRODUCER_NO_SOURCE_STAMP');
assert(fs.existsSync(path.join(failedPrefix,'.std-production.json')),'FAILED_PRODUCER_PENDING_MARKER');
console.log('ASSERT FAILED_PRODUCER_NO_SUCCESS_RECEIPT REACHED PASS child_rc=37');
git('checkout','-q',original); assert.equal(fs.readFileSync(path.join(stdSource,'build.py'),'utf8'),beforeFailure.toString());
const rebuilt=run('bash',['-c',produce]);
assert.equal(rebuilt.status,0,rebuilt.stdout+rebuilt.stderr);
check('same-producer-rebuild');
const recovering=path.join(work,'recovery-prefix');
good('node',[path.join(src,'ci/bootstrap/std-receipt.mjs'),'begin',recovering,stdSource,compiler]);
put(path.join(recovering,'modules/partial.cjo'),'same transaction partial output');
const recovered=run('bash',['-c',produce.replace(q(prefix),q(recovering))]);
assert.equal(recovered.status,0,recovered.stdout+recovered.stderr);
assert(fs.existsSync(path.join(recovering,'STDLIB_SOURCE_SHA')),'SAME_TRANSACTION_RECOVERY');
console.log('ASSERT SAME_TRANSACTION_RECOVERY REACHED PASS');
console.log(`FIXTURE_ONLY real CLI checks=${n}; no stage2/product compiler executed; root=${root}`);
