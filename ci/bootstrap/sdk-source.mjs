// Check the selected archive digest or clone HEAD before ordinary source use.
// Native builds own their private working files; never certify a whole tree.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execute = promisify(execFile);
export const effectiveSourceRoot = repo => repo.archive ? repo.root : (repo.checkout || repo.root);
const fields = ['source', 'commit', 'source-archive', 'source-archive-sha256'];
export function nativeSourceOptions(argv) {
  const result = {};
  for (let i = 2; i < argv.length; ++i) for (const key of fields) {
    const name = '--' + key;
    if (argv[i] !== name && !argv[i].startsWith(name + '=')) continue;
    if (Object.hasOwn(result, key)) throw new Error('NATIVE_SOURCE_ARGUMENT_DUPLICATE ' + key);
    result[key] = argv[i] === name ? argv[++i] : argv[i].slice(name.length + 1);
    if (!result[key] || result[key].startsWith('--')) throw new Error('NATIVE_SOURCE_ARGUMENT ' + key);
    break;
  }
  return result;
}
export function bindNativeSource(argv, repos) {
  if (path.basename(argv[1] || '') !== 'sdk-native-stage.mjs') return argv;
  const options = nativeSourceOptions(argv);
  const matches = Object.values(repos || {}).filter(repo => options.source
    && path.resolve(effectiveSourceRoot(repo)) === path.resolve(options.source));
  for (const repo of matches) {
    if (options.commit && options.commit !== repo.commit) throw new Error('NATIVE_SOURCE_COMMIT configured source ' + repo.commit);
    for (const [key, value] of Object.entries({'source-archive':repo.archive?.file, 'source-archive-sha256':repo.archive?.sha256})) {
      if (options[key] !== undefined && options[key] !== value) throw new Error('NATIVE_SOURCE_ARCHIVE_INPUT ' + key);
    }
  }
  if (!matches.length) return argv; // Direct Git sources are checked by native.
  const repo = matches[0];
  if (matches.some(row => row.commit !== repo.commit || JSON.stringify(row.archive) !== JSON.stringify(repo.archive)))
    throw new Error('NATIVE_SOURCE_AMBIGUOUS');
  const added = [];
  if (!options.commit) added.push('--commit', repo.commit);
  if (repo.archive) for (const [key,value] of Object.entries({'source-archive':repo.archive.file, 'source-archive-sha256':repo.archive.sha256}))
    if (options[key] === undefined) added.push('--'+key,value);
  return argv.concat(added);
}
export async function verifyNativeSource(options, {signal} = {}) {
  const claimed = options.commit;
  const check = actual => {
    if (claimed && claimed !== actual) throw new Error('NATIVE_SOURCE_COMMIT actual '+actual+' expected '+claimed);
    return actual;
  };
  if (options['source-archive'] || options['source-archive-sha256']) {
    const file = options['source-archive'], digest = options['source-archive-sha256'];
    if (!file || !/^[a-f0-9]{64}$/.test(digest || '') || !/^[a-f0-9]{40}$/.test(claimed || ''))
      throw new Error('NATIVE_SOURCE_ARCHIVE_INPUT');
    const {createReadStream}=await import('node:fs');
    const hash=crypto.createHash('sha256');
    for await(const chunk of createReadStream(file)) {signal?.throwIfAborted();hash.update(chunk);}
    if(hash.digest('hex')!==digest)throw new Error('NATIVE_SOURCE_ARCHIVE_DIGEST');
    return claimed;
  }
  const source=await fs.realpath(options.source);
  let root;
  try { root = (await execute('git',['-C',source,'rev-parse','--show-toplevel'],{signal,env:{...process.env,LC_ALL:'C'}})).stdout.trim(); }
  catch (error) {
    if (signal?.aborted) throw error;
    // Only the ordinary no-repository result means unknown. I/O, missing Git
    // and other failures cannot silently downgrade a source check.
    if (error.code !== 128 || !error.stderr?.includes('not a git repository')) throw error;
    if (claimed) throw new Error('NATIVE_SOURCE_UNVERIFIABLE '+source,{cause:error});
    return 'unknown';
  }
  if (await fs.realpath(root) !== source) throw new Error('NATIVE_SOURCE_ROOT '+source);
  const actual = (await execute('git',['-C',source,'rev-parse','HEAD'],{signal})).stdout.trim();
  if (!/^[a-f0-9]{40}$/.test(actual)) throw new Error('NATIVE_SOURCE_HEAD');
  check(actual);
  return actual;
}

// A private materialized tree is the build input on reentry. The archive is
// needed only before the first extraction; failed temporary trees stay intact.
export async function materializeNativeSource(options, run, {signal} = {}) {
  if (!options['source-archive'] && !options['source-archive-sha256'])
    return verifyNativeSource(options, {signal});
  const root = path.resolve(options.source);
  const exists = await fs.lstat(root).then(() => true, error => {
    if (error.code === 'ENOENT') return false;
    throw error;
  });
  if (exists) return options.commit;
  const commit = await verifyNativeSource(options, {signal});
  await fs.mkdir(path.dirname(root), {recursive:true});
  const temporary = await fs.mkdtemp(path.join(path.dirname(root), '.'+path.basename(root)+'-'));
  await run(['tar','-xf',options['source-archive'],'-C',temporary], {signal});
  signal?.throwIfAborted();
  await fs.rename(temporary, root);
  return commit;
}
