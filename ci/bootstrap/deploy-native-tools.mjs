#!/usr/bin/env zx
// Export the two actual H1 adapter modules from the paired private tools commit.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileDigest, atomicJson, privateRoot} from './sdk-flow.mjs';
const execute = promisify(execFile);
export async function deployNativeTools(repository, commit, destination) {
  if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error('NATIVE_TOOLS_COMMIT_REQUIRED');
  destination=await privateRoot(destination);
  await fs.mkdir(destination); // Never overlay another tool input.
  const actual=(await execute('git',['-C',repository,'rev-parse',commit+'^{commit}'])).stdout.trim();
  if(actual!==commit)throw new Error('NATIVE_TOOLS_COMMIT');
  const files={};
  for(const name of ['cjcj-stage1.mjs','stage1-transform.mjs']) {
    const rel='ts/src/sharedbuild/'+name, file=path.join(destination,rel);
    const {stdout}=await execute('git',['-C',repository,'show',commit+':'+rel]);
    await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,stdout);
    files[rel]=await fileDigest(file);
  }
  await atomicJson(path.join(destination,'BUILD-INPUTS.json'),{repository,commit,files});
  return {destination,commit,files};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{console.log(JSON.stringify(await deployNativeTools(...process.argv.slice(2))));}
  catch(error){console.error(error.stack);process.exitCode=1;}
}
