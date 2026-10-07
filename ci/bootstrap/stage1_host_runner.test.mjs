import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

const runner = process.env.STAGE1_RUNNER_PRODUCT || new URL('./stage1_host_runner.sh', import.meta.url).pathname;
const producer = new URL('./compiler_identity.py', import.meta.url).pathname;
const sha = p => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const cases = ['legal-alias', 'outside-alias', 'absolute-alias', 'dangling-alias', 'hash-mismatch', 'chained-alias', 'regular-entry'];
for (const kind of cases) test(kind, () => {
  const root = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'runner-alias-'));
  try {
    const target = path.join(root, 'target'), host = path.join(root, 'host'), run = path.join(root, 'run');
    const platform = `linux_${os.arch() === 'arm64' ? 'aarch64' : 'x86_64'}_cjnative`;
    const put = (p, data) => { fs.mkdirSync(path.dirname(p), {recursive:true}); fs.writeFileSync(p, data); };
    const elf = p => { fs.mkdirSync(path.dirname(p), {recursive:true}); fs.copyFileSync('/usr/bin/true', p); fs.chmodSync(p, 0o755); };
    for (const sdk of [target, host, run]) {
      put(path.join(sdk, 'third_party/llvm/lib/libLLVM-15.so'), 'llvm-fixture');
      for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) put(path.join(sdk, `runtime/lib/${platform}/${name}`), name);
    }
    for (const name of ['opt', 'llc', 'ld.lld']) elf(path.join(target, 'third_party/llvm/bin', name));
    elf(path.join(target, 'tools/bin/cjpm')); elf(path.join(host, 'tools/bin/cjpm'));
    const compiler = path.join(root, 'compiler'); elf(compiler);
    const installed = spawnSync('python3', [producer, target, '--install', compiler], {encoding:'utf8'});
    assert.equal(installed.status, 0, installed.stdout + installed.stderr);
    const cjc = path.join(target, 'bin/cjc'), real = path.join(target, 'bin/cjcj-stage1');
    if (kind === 'outside-alias' || kind === 'absolute-alias') {
      fs.unlinkSync(cjc); fs.symlinkSync(kind === 'outside-alias' ? '../../compiler' : real, cjc);
    } else if (kind === 'dangling-alias') fs.unlinkSync(real);
    else if (kind === 'hash-mismatch') fs.appendFileSync(real, 'different bytes');
    else if (kind === 'chained-alias') { fs.unlinkSync(real); fs.symlinkSync(compiler, real); }
    else if (kind === 'regular-entry') { fs.unlinkSync(cjc); elf(cjc); }
    const identities = path.join(root, 'identities');
    put(identities, ['libcangjie-runtime.so', 'libboundscheck.so', 'libLLVM-15.so'].map(name => {
      const file = name === 'libLLVM-15.so' ? path.join(host, 'third_party/llvm/lib', name) : path.join(host, `runtime/lib/${platform}`, name);
      return `${platform.replace('_cjnative', '')} ${name} ${sha(file)}\n`;
    }).join(''));
    const result = spawnSync('bash', [runner, target, host, host, sha(path.join(host, 'third_party/llvm/lib/libLLVM-15.so')), compiler, sha(compiler), run, sha(path.join(run, 'third_party/llvm/lib/libLLVM-15.so'))], {
      encoding:'utf8', env:{...process.env, STAGE1_HOST_IDENTITIES:identities},
    });
    console.log(`ASSERT ${kind} runner-status=${result.status} stderr=${result.stderr.trim()}`);
    if (kind === 'legal-alias' || kind === 'regular-entry') {
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /STAGE1-RUNNER-OK/);
      assert.equal(fs.lstatSync(cjc).isSymbolicLink(), false);
      assert.equal(sha(real), sha(compiler), 'wrapper must preserve compiler ELF');
      const call = spawnSync(cjc, [], {encoding:'utf8'});
      assert.equal(call.status, 0, call.stderr);
      assert.match(fs.readFileSync(cjc, 'utf8'), /export LD_LIBRARY_PATH=/);
      console.log(`ASSERT ${kind} wrapper-executed compiler-ELF-preserved`);
    } else {
      assert.equal(result.status, 1, result.stdout + result.stderr);
      const reason = ['outside-alias', 'absolute-alias'].includes(kind) ? 'unsupported compiler alias: bin/cjc' : kind === 'hash-mismatch' ? `sha mismatch: ${real} expected=${sha(compiler)}` : 'regular executable required: bin/cjcj-stage1';
      assert.ok(result.stderr.includes(`STAGE1-RUNNER-FAIL ${reason}`), result.stderr);
      assert.equal(fs.existsSync(path.join(target, '.stage1-host')), false, 'reject before mutation');
    }
  } finally { fs.rmSync(root, {recursive:true, force:true}); }
});
