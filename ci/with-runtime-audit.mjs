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
fs.writeFileSync(log, '');
const build = spawnSync('cc', ['-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror',
  new URL('./official-runtime-audit.c', import.meta.url).pathname, '-o', audit, '-lcrypto'], {stdio: 'inherit'});
if (build.status !== 0) throw new Error('cannot build runtime loader audit');
console.log(`RUNTIME_AUDIT sdk=${sdk} colour=${runtime} sha256=${sha} log=${log}`);
const result = spawnSync(args[0], args.slice(1), {stdio: 'inherit', env: {...process.env,
  LD_AUDIT: [audit, process.env.LD_AUDIT].filter(Boolean).join(':'),
  CJCJ_AUDIT_SDK: sdk, CJCJ_AUDIT_RUNTIME: runtime, CJCJ_AUDIT_SHA256: sha, CJCJ_AUDIT_LOG: log,
}});
const observed = fs.readFileSync(log, 'utf8');
process.stdout.write(observed);
// Preserve failures even when a parent absorbs the rejected SDK child's status.
process.exitCode = observed.includes('OFFICIAL_RUNTIME_MISMATCH') ? 86 : (result.status ?? 1);
