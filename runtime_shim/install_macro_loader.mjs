#!/usr/bin/env zx
// Install the compiler-owned native macro caller beside the target runtime.
// The normal native compiler/SDK install invokes this after build_shim.mjs.
import fs from 'node:fs/promises';
import {constants} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

export async function installMacroLoader({source, prefix, platform}) {
  if (!['linux_x86_64', 'linux_aarch64'].includes(platform)) {
    if (['windows_x86_64', 'darwin_x86_64', 'darwin_aarch64'].includes(platform)) return;
    throw Error('unsupported macro loader install platform: ' + platform);
  }
  const from = path.join(source, 'runtime_shim', 'libcjcj-macro-loader.so');
  const directory = path.join(prefix, 'runtime', 'lib', platform + '_cjnative');
  // Never follow the build-tree runtime symlink into an official host SDK.
  const root = path.resolve(prefix);
  await fs.mkdir(root, {recursive: true});
  if ((await fs.lstat(root)).isSymbolicLink()) throw Error('macro loader install prefix is a symlink: ' + root);
  for (const component of ['runtime', 'runtime/lib', 'runtime/lib/' + platform + '_cjnative']) {
    const item = path.join(root, component);
    const stat = await fs.lstat(item).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (stat?.isSymbolicLink()) throw Error('macro loader install directory is a symlink: ' + item);
    await fs.mkdir(item, {recursive: true});
  }
  const to = path.join(directory, 'libcjcj-macro-loader.so');
  try {
    await fs.copyFile(from, to, constants.COPYFILE_EXCL);
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    if (!(await fs.readFile(from)).equals(await fs.readFile(to))) {
      throw Error('macro loader install already contains a different producer: ' + to);
    }
  }
  return to;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const {values} = parseArgs({options: {prefix: {type: 'string'}, platform: {type: 'string'}}});
  if (!values.prefix || !values.platform) throw Error('--prefix and --platform are required');
  await installMacroLoader({source: path.resolve(import.meta.dirname, '..'), ...values});
}
