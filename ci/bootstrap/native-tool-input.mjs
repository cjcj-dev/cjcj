#!/usr/bin/env zx
// Resolve the source producer's native-tool locations into ordinary build
// options. Reuse the same inputs across job handoff and public tools.run.
import fs from 'node:fs/promises';
import path from 'node:path';
import {readJson,atomicJson,relative} from './sdk-flow.mjs';
import {prepareNativeToolDependencies,readNativeToolDependencies} from '../../build/srcbuild/native-tool-dependencies.mjs';
export async function configureNativeToolInput({root,workspace,platform}) {
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
    if(platform==='windows_x86_64'){
      // A descriptor can name a fixed dependency, but must not transport
      // its source tree. Materialize it in this job's private workspace.
      if(row.path!==undefined)throw Error('WINDOWS_NATIVE_TOOL_DEPENDENCY_REQUIRES_GIT '+name);
      resolved[name]={repo:row.repo,commit:row.commit,path:path.join(workspace,'native-sources',name)};
      continue;
    }
    relative(row.path);
    const source=await fs.realpath(path.resolve(path.dirname(file),row.path));
    if(!source.startsWith(root+path.sep))throw Error('GHA_NATIVE_TOOL_SOURCE_PATH '+name);
    resolved[name]={...row,path:source};
  }
  const output=path.join(workspace,'native-tool-dependencies.json');
  await atomicJson(output,resolved);
  await readNativeToolDependencies(output,['cjlint']);
  if(platform==='windows_x86_64')await prepareNativeToolDependencies({toolsDependencies:output},['cjlint']);
  return output;
}
export async function verifyNativeToolHandoff(root) {
  const file=path.join(root,'.srcbuild/workspace/native-tool-dependencies.json');
  const locations=path.join(root,'.srcbuild/native-inputs/locations.json');
  // Some bootstrap-only artifacts declare no tools. A declared descriptor
  // must survive both pack and restore, even if it was subsequently removed.
  const input=await readJson(locations).catch(error=>{if(error.code!=='ENOENT')throw error;});
  if(!input?.nativeToolDependencies && !await fs.lstat(file).catch(error=>{if(error.code!=='ENOENT')throw error;}))return;
  const archived=path.join(await fs.realpath(root),'.srcbuild')+path.sep;
  const selection=await readNativeToolDependencies(file,['cjlint']);
  for(const item of [file,...Object.values(selection).map(row=>row.path)]) {
    if(!path.resolve(item).startsWith(archived)||!(await fs.realpath(item)).startsWith(archived))throw Error('handoff native tool dependency outside archived inputs');
  }
}
