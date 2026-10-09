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
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv[2] !== 'prepare' || process.argv.length !== 4) fail('usage: test-zx.mjs prepare RECEIPT');
  prepare(process.argv[3]);
}
