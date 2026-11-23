import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest} from '../../../../../ci/bootstrap/sdk-flow.mjs';
import {provenanceArtifacts} from '../../../../lib/release-manifest.mjs';

import {assertAndroidRuntimePair} from './android-runtime-pair.mjs';

export const androidTuple = 'linux_android_aarch64_cjnative';
export const androidStdRoots = ['modules', 'lib', 'runtime/lib'].map(dir => dir + '/' + androidTuple);
export const androidStdProvenance = 'PROVENANCE-' + androidTuple + '.txt';

export async function readAndroidInputs(sdk, hostSource, checkArtifact, stage) {
  let text;
  try { text = await fs.readFile(path.join(sdk, androidStdProvenance), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  const runtime = JSON.parse(await fs.readFile(path.join(sdk, 'CROSS-RUNTIME-' + androidTuple + '.json'), 'utf8'));
  const split = runtime.runtimeRef !== hostSource?.commit;
  if (split) {
    assertAndroidRuntimePair(hostSource?.commit, runtime.runtimeRef, stage);
    if (typeof runtime.sourceRepository !== 'string' || !runtime.sourceRepository) throw Error('ANDROID_TARGET_REPOSITORY');
  }
  const source = split ? {...hostSource, commit:runtime.runtimeRef, repository:runtime.sourceRepository} : hostSource;
  if (source?.status !== 'resolved' || !/^[0-9a-f]{40}$/.test(source.commit) || !text.split('\n').includes('STD_SOURCE_COMMIT = ' + source.commit))
    throw Error('ANDROID_INSTALL_STD_SOURCE');
  const std = provenanceArtifacts(text);
  if (!std) throw Error('ANDROID_STD_INVENTORY');
  const stdFiles = new Set();
  const libraries = [];
  async function measured(rel, expected) {
    const file = path.join(sdk, rel);
    if (await fs.realpath(file) !== file || (await fileDigest(file)) !== expected) throw Error('ANDROID_ARTIFACT_BYTES ' + rel);
    const row = {path:rel, sha256:expected};
    checkArtifact?.(row);
    return row;
  }
  for (const [rel, hash] of std) {
    if (!androidStdRoots.some(dir => rel.startsWith(dir + '/'))) continue;
    libraries.push(await measured(rel, hash));
    stdFiles.add(rel);
  }
  for (const rel of [androidStdRoots[0] + '/std/std.core.cjo', androidStdRoots[1] + '/libcangjie-std-core.a',
    androidStdRoots[2] + '/libcangjie-std-core.so']) if (!stdFiles.has(rel)) throw Error('ANDROID_STD_REQUIRED ' + rel);
  if (runtime.schema !== 1 || runtime.tuple !== androidTuple || runtime.runtimeRef !== source.commit) throw Error('ANDROID_INSTALL_RUNTIME_PAIR');
  const runtimeFiles = new Map();
  for (const row of runtime.files) {
    const dir = path.posix.dirname(row.path);
    if (!androidStdRoots.slice(1).includes(dir) || !/^[\w.+-]+$/.test(path.posix.basename(row.path))
        || stdFiles.has(row.path) || runtimeFiles.has(row.path)) throw Error('ANDROID_RUNTIME_PATH ' + row.path);
    runtimeFiles.set(row.path, await measured(row.path, row.sha256));
  }
  for (const rel of [androidStdRoots[1] + '/cjstart.o', androidStdRoots[2] + '/libcangjie-runtime.so',
    androidStdRoots[2] + '/libboundscheck.so']) if (!runtimeFiles.has(rel)) throw Error('ANDROID_RUNTIME_REQUIRED ' + rel);
  return {stdFiles, components:[
    {component:'android-std', source, artifacts:libraries},
    {component:'android-runtime', source, artifacts:[...runtimeFiles.values()]},
  ]};
}
