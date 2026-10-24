#!/usr/bin/env zx
// Native artifact locations select the HLE component; its descriptor keeps
// paths relative so extraction and a subsequent job read the current root.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
export async function readHleDependencies(file, platform) {
  const input=JSON.parse(await fs.readFile(file,'utf8'));
  if(platform && input.platform!==platform)throw new Error('HLE_DEPENDENCIES_PLATFORM');
  const result={...input};
  for(const key of ['node','modules','cjbind']) {
    const row=input[key];
    if(!row || !row.path || !row.source || !row.version)throw new Error('HLE_DEPENDENCY_SOURCE '+key);
    const resolved=path.resolve(path.dirname(file),row.path);
    const stat=await fs.stat(resolved);
    if(key==='modules'?!stat.isDirectory():!stat.isFile())throw new Error('HLE_DEPENDENCY_PATH '+key);
    result[key]={...row,path:resolved};
  }
  return result;
}
export async function configureHleInput(root, platform, envFile) {
  root=await fs.realpath(root);
  const locations=JSON.parse(await fs.readFile(path.join(root,'locations.json'),'utf8'));
  if(locations.platform!==platform)throw new Error('GHA_NATIVE_ARTIFACT_PLATFORM');
  const relative=locations.hleDependencies;
  if(typeof relative!=='string'||!relative||path.isAbsolute(relative)||relative.split(/[\\/]/).includes('..'))
    throw new Error('GHA_HLE_ARTIFACT_PATH');
  const file=await fs.realpath(path.join(root,relative));
  if(!file.startsWith(root+path.sep))throw new Error('GHA_HLE_ARTIFACT_PATH');
  const input=await readHleDependencies(file,platform);
  for(const row of [input.node,input.modules,input.cjbind]) {
    if(!(await fs.realpath(row.path)).startsWith(root+path.sep))throw new Error('GHA_HLE_ARTIFACT_MEMBER');
  }
  if(envFile)await fs.appendFile(envFile,`CJCJ_HLE_DEPENDENCIES=${file}\n`);
  return file;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const [root,platform]=process.argv.slice(2);
    console.log(await configureHleInput(root,platform,process.env.GITHUB_ENV));
  }catch(error){console.error(error.stack);process.exitCode=1;}
}
