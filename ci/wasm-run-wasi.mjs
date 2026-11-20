#!/usr/bin/env node
// Runs a wasm32-wasi command module produced by cjc/cjpm under node:wasi (WASI preview1).
// Installed into the SDK as tools/wasm/run_wasi.mjs by ci/wasm-sdk-overlay.mjs.
//
//   node <CANGJIE_HOME>/tools/wasm/run_wasi.mjs app.wasm [args...]
//
// The module sees argv [app.wasm, args...] and only the CJ_WASM_* variables of this process
// (CJ_WASM_GC_STATS, CJ_WASM_GC_VERIFY, CJ_WASM_GC_EVERY, CJ_WASM_HEAP_REDZONE). The exit status
// is the module's exit code. Node is the one running this script; to pick another, run it with
// CJ_WASM_NODE=<node> (re-exec) or start the script with that node directly.
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';

const MIN_NODE_MAJOR = 20;
// V8 can crash in a GC triggered from the WASI fd_write fast-API callback once linear memory is
// large; the module is always run with fast API calls disabled.
const NODE_FLAG = '--no-turbo-fast-api-calls';
const script = fileURLToPath(import.meta.url);
const args = process.argv.slice(2);
const wanted = process.env.CJ_WASM_NODE;
if (!process.execArgv.includes(NODE_FLAG) || (wanted && wanted !== process.execPath && !process.env.CJ_WASM_RUNNER_CHILD)) {
  const node = wanted || process.execPath;
  const r = spawnSync(node, [NODE_FLAG, script, ...args], {stdio: 'inherit', env: {...process.env, CJ_WASM_RUNNER_CHILD: '1'}});
  if (r.error) { console.error(`run_wasi: cannot start ${node}: ${r.error.message}`); process.exit(127); }
  process.exit(r.status ?? 128 + 9);
}
const major = Number(process.versions.node.split('.')[0]);
if (!(major >= MIN_NODE_MAJOR)) {
  console.error(`run_wasi: node ${process.version} is older than v${MIN_NODE_MAJOR} (node:wasi preview1)`);
  process.exit(127);
}
const [wasmPath, ...moduleArgs] = args;
if (!wasmPath) { console.error('usage: run_wasi.mjs <app.wasm> [args...]'); process.exit(2); }
const {WASI} = await import('node:wasi');
const env = {};
for (const [k, v] of Object.entries(process.env)) if (k.startsWith('CJ_WASM_') && k !== 'CJ_WASM_RUNNER_CHILD' && k !== 'CJ_WASM_NODE') env[k] = v;
const wasi = new WASI({version: 'preview1', args: [wasmPath, ...moduleArgs], env, returnOnExit: true});
const module = await WebAssembly.compile(fs.readFileSync(wasmPath));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
let rc;
try { rc = wasi.start(instance); } catch (e) { console.error(`wasm trap: ${e && e.message}`); rc = 139; }
process.exitCode = rc;
