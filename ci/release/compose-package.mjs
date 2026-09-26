#!/usr/bin/env zx
// One cross-std list feeds both Unix and Windows packaging. The ordinary
// packager still owns the tuple overlay and all package validation.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

export function crossStdArguments(text, root) {
  const entries = JSON.parse(text);
  if (!Array.isArray(entries)) throw new Error('cross std artifacts must be a JSON array');
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

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const {values, positionals} = parseArgs({allowPositionals: true, strict: false,
    options: {'cross-root': {type: 'string'}}});
  if (!values['cross-root']) throw new Error('--cross-root is required');
  const args = crossStdArguments(process.env.CROSS_STD_ARTIFACTS ?? '[]', values['cross-root']);
  const script = fileURLToPath(new URL('../../scripts/package_sdk.mjs', import.meta.url));
  await $({stdio: 'inherit'})`npx --yes zx@8 ${script} ${args} ${positionals}`;
}
