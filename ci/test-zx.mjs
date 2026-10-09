// The CI npm-exec preparation owns resolution of zx@8. Tests consume only its receipt.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const fail = message => { throw new Error(`TEST_ZX_INPUT: ${message}`); };
function identity(cli) {
  cli = fs.realpathSync(cli);
  let directory = path.dirname(cli);
  while (!fs.existsSync(path.join(directory, 'package.json'))) {
    const parent = path.dirname(directory);
    if (parent === directory) fail('CLI has no package identity');
    directory = parent;
  }
  const packageFile = path.join(directory, 'package.json');
  const pkg = JSON.parse(fs.readFileSync(packageFile, 'utf8'));
  if (pkg.name !== 'zx' || !/^8\.\d+\.\d+(?:[-+].*)?$/.test(pkg.version)) fail('expected zx@8 package');
  const bin = typeof pkg.bin === 'string' ? pkg.bin : pkg.bin?.zx;
  if (!bin || fs.realpathSync(path.resolve(directory, bin)) !== cli) fail('CLI differs from package bin');
  const node = fs.realpathSync(process.execPath);
  return {version: pkg.version, packageFile, packageSha256: digest(packageFile), cli, cliSha256: digest(cli),
    node, nodeVersion: process.version, nodeSha256: digest(node)};
}
export function prepare(receipt) {
  // npm exec places the selected package's .bin first; never accept a global PATH zx.
  const prefix = (process.env.PATH || '').split(path.delimiter)[0];
  if (path.basename(prefix) !== '.bin' || path.basename(path.dirname(prefix)) !== 'node_modules')
    fail('prepare must run inside npm exec --package=zx@8');
  const tool = identity(path.join(prefix, 'zx'));
  const result = spawnSync(tool.node, [tool.cli, '--version'], {encoding: 'utf8'});
  if (result.status !== 0 || result.stdout.trim() !== tool.version) fail('CLI version execution failed');
  fs.mkdirSync(path.dirname(path.resolve(receipt)), {recursive: true});
  fs.writeFileSync(receipt, JSON.stringify(tool, null, 2) + '\n');
  if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV, `CJCJ_TEST_ZX_RECEIPT=${path.resolve(receipt)}\n`);
  console.log(`TEST_ZX_PREPARED ${JSON.stringify(tool)}`);
  return tool;
}
export function verifiedTool(env = process.env) {
  if (!env.CJCJ_TEST_ZX_RECEIPT) fail('CJCJ_TEST_ZX_RECEIPT is required; run formal tool preparation');
  try {
    const expected = JSON.parse(fs.readFileSync(env.CJCJ_TEST_ZX_RECEIPT, 'utf8'));
    const actual = identity(expected.cli);
    for (const key of Object.keys(actual)) if (actual[key] !== expected[key]) fail(`identity mismatch: ${key}`);
    return actual;
  } catch (error) { fail(error.message); }
}
export function zxCommand(args, env = process.env) {
  const tool = verifiedTool(env);
  return [tool.node, tool.cli, ...args];
}
export function adapterRun(kind, args) {
  const tool = verifiedTool();
  if (kind === 'npx') {
    if (args.length === 4 && args[0] === '--yes' && args[1] === '--package=zx@8'
        && args[2] === '-c' && args[3] === 'command -v zx') {
      console.log(path.join(process.env.CJCJ_TEST_ZX_BIN, 'zx'));
      return;
    }
    if (args[0] !== '--yes' || args[1] !== 'zx@8') fail('unsupported test npx syntax or package');
    args = args.slice(2);
  } else if (kind !== 'zx') fail('unsupported adapter');
  const event = {time: new Date().toISOString(), pid: process.pid, kind, cwd: process.cwd(),
    argv: [tool.node, tool.cli, ...args], cliSha256: tool.cliSha256};
  const record = value => {
    if (process.env.CJCJ_TEST_ZX_LOG) fs.appendFileSync(process.env.CJCJ_TEST_ZX_LOG, JSON.stringify(value) + '\n');
  };
  const start = performance.now();
  record({...event, event: 'begin'});
  const result = spawnSync(tool.node, [tool.cli, ...args], {stdio: 'inherit'});
  record({...event, event: 'end', wallMs: performance.now() - start, status: result.status,
    signal: result.signal, error: result.error?.message});
  if (result.signal) process.kill(process.pid, result.signal);
  else process.exitCode = result.status ?? 1;
}
export function testEnvironment(directory, env = process.env) {
  const tool = verifiedTool(env);
  fs.mkdirSync(directory, {recursive: true});
  if (env.CJCJ_TEST_ZX_LOG) fs.mkdirSync(path.dirname(env.CJCJ_TEST_ZX_LOG), {recursive: true});
  for (const kind of ['npx', 'zx']) {
    const text = `#!${tool.node}\nimport(${JSON.stringify(import.meta.url)}).then(m => m.adapterRun(${JSON.stringify(kind)}, process.argv.slice(2))).catch(e => { console.error(e.message); process.exitCode = 1; });\n`;
    fs.writeFileSync(path.join(directory, kind), text, {mode: 0o755});
  }
  return {...env, CJCJ_TEST_ZX_BIN: directory, PATH: `${directory}${path.delimiter}${env.PATH || ''}`};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, directory, ...args] = process.argv.slice(2);
  if (mode === 'prepare' && directory && !args.length) prepare(directory);
  else if (mode === 'run' && directory && args.length) {
    const env = testEnvironment(path.resolve(directory));
    const result = spawnSync(args[0], args.slice(1), {env, stdio: 'inherit'});
    if (result.signal) process.kill(process.pid, result.signal);
    else process.exitCode = result.status ?? 1;
  } else fail('usage: test-zx.mjs prepare RECEIPT | run PRIVATE_BIN COMMAND [ARGS...]');
}
