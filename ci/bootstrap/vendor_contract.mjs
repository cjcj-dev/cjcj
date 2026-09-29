import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

export const vendorFiles = Object.freeze([
  'bootstrap.sh', 'sdk_build.sh', 'test_bootstrap.sh',
  'stage1_host_runner.sh', 'stage1_host_identities.txt',
]);

function git(repo, args) {
  const result = spawnSync('git', ['-C', repo, ...args], {maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.status !== 0 || !result.stdout?.length) {
    throw new Error(result.error?.message || result.stderr?.toString().trim() || 'empty Git output');
  }
  return result.stdout;
}

export function checkVendor({sourceRepo = process.cwd(), commit = 'HEAD', consumerRoot = sourceRepo} = {}) {
  const result = {commit: null, files: [], errors: []};
  try {
    result.commit = git(sourceRepo, ['rev-parse', '--verify', '--end-of-options', `${commit}^{commit}`]).toString().trim();
    if (!/^[0-9a-f]{40,64}$/.test(result.commit)) throw new Error('invalid commit OID');
  } catch (error) {
    result.errors.push({kind: 'source-identity', detail: error.message});
    return result;
  }
  let records = '';
  try {
    records = fs.readFileSync(path.join(consumerRoot, 'ci/bootstrap/SOURCE.env'), 'utf8');
  } catch (error) {
    result.errors.push({kind: 'import-read', detail: error.code});
  }
  for (const name of vendorFiles) {
    const item = {name, errors: []};
    const values = records.split('\n').filter(line => line.startsWith(`TOOLS_${name}=`));
    if (values.length !== 1 || !/^[0-9a-f]{64}$/.test(values[0].slice(values[0].indexOf('=') + 1))) {
      item.errors.push({kind: 'import-record'});
    }
    const relative = `ci/bootstrap/${name}`;
    let expected;
    try {
      expected = git(sourceRepo, ['cat-file', 'blob', `${result.commit}:${relative}`]);
    } catch (error) {
      item.errors.push({kind: 'source-blob', detail: error.message});
    }
    let actual;
    try {
      actual = fs.readFileSync(path.join(consumerRoot, relative));
    } catch (error) {
      item.errors.push({kind: error.code === 'ENOENT' ? 'consumer-missing' : 'consumer-read', detail: error.code});
    }
    if (expected && actual && !expected.equals(actual)) item.errors.push({kind: 'content-drift'});
    result.files.push(item);
  }
  return result;
}

export function main(args) {
  const options = {};
  const keys = {'--source-repo': 'sourceRepo', '--commit': 'commit', '--consumer-root': 'consumerRoot'};
  for (let i = 0; i < args.length; i += 2) {
    if (!keys[args[i]] || !args[i + 1]) throw new Error(`invalid argument: ${args[i]}`);
    options[keys[args[i]]] = args[i + 1];
  }
  const result = checkVendor(options);
  process.stdout.write(`${JSON.stringify(result)}\n`);
  return result.errors.length || result.files.some(item => item.errors.length) ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`vendor-contract: ${error.message}\n`);
    process.exitCode = 2;
  }
}
