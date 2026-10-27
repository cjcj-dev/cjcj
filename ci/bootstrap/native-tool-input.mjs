#!/usr/bin/env zx
// Resolve the source producer's native-tool locations into ordinary build
// options. Reuse the same inputs across job handoff and public tools.run.
import fs from 'node:fs/promises';
import path from 'node:path';
import {readJson,atomicJson,relative} from './sdk-flow.mjs';
import {readNativeToolDependencies} from '../../build/srcbuild/native-tool-dependencies.mjs';
export async function configureNativeToolInput({root,workspace,platform,envFile}) {
  root=await fs.realpath(root);
  const locations=await readJson(path.join(root,'locations.json'));
  if(locations.platform!==platform)throw Error('GHA_NATIVE_ARTIFACT_PLATFORM');
  // N/bootstrap-only inputs need not carry tool sources. The public tools
  // producer requires its explicit input when that stage is actually selected.
  if(!locations.nativeToolDependencies)return null;
  relative(locations.nativeToolDependencies);
  const file=await fs.realpath(path.join(root,locations.nativeToolDependencies));
  if(!file.startsWith(root+path.sep))throw Error('GHA_NATIVE_TOOL_INPUT_PATH');
  const selection=await readJson(file),resolved={};
  for(const name of ['json']) {
    const row=selection[name];
    if(!row)throw Error('GHA_NATIVE_TOOL_SOURCE '+name);
    relative(row.path);
    const source=await fs.realpath(path.resolve(path.dirname(file),row.path));
    if(!source.startsWith(root+path.sep))throw Error('GHA_NATIVE_TOOL_SOURCE_PATH '+name);
    resolved[name]={...row,path:source};
  }
  const output=path.join(workspace,'native-tool-dependencies.json');
  await atomicJson(output,resolved);
  await readNativeToolDependencies(output,['cjlint']);
  if(envFile)await fs.appendFile(envFile,'CJCJ_NATIVE_TOOL_DEPENDENCIES='+output+'\n');
  return output;
}
export async function verifyNativeToolHandoff({root,environment}) {
  const file=environment.CJCJ_NATIVE_TOOL_DEPENDENCIES;
  if(!file)return;
  const archived=path.join(await fs.realpath(root),'.srcbuild')+path.sep;
  const selection=await readNativeToolDependencies(file,['cjlint']);
  for(const item of [file,...Object.values(selection).map(row=>row.path)]) {
    if(!path.resolve(item).startsWith(archived)||!(await fs.realpath(item)).startsWith(archived))throw Error('handoff native tool dependency outside archived inputs');
  }
}
