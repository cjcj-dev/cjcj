#!/usr/bin/env node
// Linux CI execution boundary. LD_AUDIT is inherited by exec'd SDK children.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const args = process.argv.slice(2);
if (args.shift() !== '--' || !args.length) throw new Error('usage: with-runtime-audit.mjs -- command [args...]');
if (process.platform !== 'linux') throw new Error('runtime loader audit requires Linux/glibc');
const sdk = fs.realpathSync(process.env.CANGJIE_HOME);
const runtime = fs.realpathSync(path.join(process.env.CJCJ_PATCHED_RUNTIME_LIB_DIR, 'libcangjie-runtime.so'));
const sha = crypto.createHash('sha256').update(fs.readFileSync(runtime)).digest('hex');
const work = fs.mkdtempSync(path.resolve(process.env.RUNNER_TEMP || '.', 'runtime-audit-'));
const audit = path.join(work, 'audit.so');
const log = path.join(work, 'loads.log');
// Include copied SDK executables: moving a stock binary does not rebuild it.
const identities = new Set();
const compilerIdentities = new Set();
function inventory(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) inventory(file);
    else if (entry.isFile() && (fs.statSync(file).mode & 0o111)) {
      const bytes = fs.readFileSync(file);
      if (bytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) {
        const digest = crypto.createHash('sha256').update(bytes).digest('hex');
        identities.add(digest);
        if (['cjc', 'cjc-frontend'].includes(entry.name)) compilerIdentities.add(digest);
      }
    }
  }
}
inventory(sdk);
const identityFile = path.join(work, 'sdk-executables.sha256');
fs.writeFileSync(identityFile, [...identities].join('\n') + '\n');
const compilerFile = path.join(work, 'official-compilers.sha256');
fs.writeFileSync(compilerFile, [...compilerIdentities].join('\n') + '\n');
const llvmTools = [];
if (process.env.CJCJ_PATCHED_LLVM_BIN) {
  const bin = fs.realpathSync(process.env.CJCJ_PATCHED_LLVM_BIN);
  for (const name of ['opt', 'llc', 'ld.lld', 'ld64.lld']) {
    const file = path.join(bin, name);
    if (!fs.existsSync(file)) {
      if (name === 'opt' || name === 'llc') throw new Error(`incomplete isolated LLVM tuple: ${file}`);
      continue;
    }
    const real = fs.realpathSync(file);
    llvmTools.push(`${crypto.createHash('sha256').update(fs.readFileSync(real)).digest('hex')}\t${real}`);
  }
}
const toolsFile = path.join(work, 'llvm-tools.sha256');
fs.writeFileSync(toolsFile, llvmTools.join('\n') + '\n');
fs.writeFileSync(log, '');
const build = spawnSync('cc', ['-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror',
  new URL('./official-runtime-audit.c', import.meta.url).pathname, '-o', audit, '-lcrypto'], {stdio: 'inherit'});
if (build.status !== 0) throw new Error('cannot build runtime loader audit');
const auditSha = crypto.createHash('sha256').update(fs.readFileSync(audit)).digest('hex');
console.log(`RUNTIME_AUDIT sdk=${sdk} colour=${runtime} sha256=${sha} audit_sha256=${auditSha} log=${log}`);
const result = spawnSync(args[0], args.slice(1), {stdio: 'inherit', env: {...process.env,
  LD_AUDIT: [audit, process.env.LD_AUDIT].filter(Boolean).join(':'),
  CJCJ_AUDIT_LLVM_TOOLS: llvmTools.length ? toolsFile : '', CJCJ_AUDIT_COMPILERS: compilerFile,
  CJCJ_AUDIT_SDK: sdk, CJCJ_AUDIT_IDENTITIES: identityFile, CJCJ_AUDIT_RUNTIME: runtime, CJCJ_AUDIT_SHA256: sha, CJCJ_AUDIT_LOG: log,
}});
const observed = fs.readFileSync(log, 'utf8');
process.stdout.write(observed);
// Preserve failures even when a parent absorbs the rejected SDK child's status.
process.exitCode = /OFFICIAL_(?:RUNTIME|TOOLCHAIN)_MISMATCH/.test(observed) ? 86 : (result.status ?? 1);
