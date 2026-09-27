import path from 'node:path';

export function crossStdArguments(text, root, {artifact = '', tuple = ''} = {}) {
  const entries = JSON.parse(text);
  if (!Array.isArray(entries)) throw new Error('cross std artifacts must be a JSON array');
  if (artifact || tuple) {
    if (!artifact || !tuple) throw new Error('single cross std input requires both artifact and tuple');
    if (entries.length) throw new Error('use either the cross std list or the single tuple input');
    entries.push({artifact, tuple});
  }
  const tuples = new Set();
  return entries.flatMap(({tuple, artifact}) => {
    if (!/^[a-z0-9_]+_cjnative$/.test(tuple) || !/^final-std-[a-z0-9-]+$/.test(artifact)) {
      throw new Error('invalid cross std tuple/artifact');
    }
    if (tuples.has(tuple)) throw new Error(`duplicate cross std tuple: ${tuple}`);
    tuples.add(tuple);
    const directory = path.join(root, artifact);
    const args = ['--cross-std-dir', `${tuple}=${directory}`];
    if (tuple === 'linux_android_aarch64_cjnative') {
      args.push('--cross-runtime-dir', `${tuple}=${path.join(directory, 'cross-runtime')}`);
    }
    return args;
  });
}
