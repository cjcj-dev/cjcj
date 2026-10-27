// cjlint's ordinary JSON source input. Cangjie cjprof receives its SDK/JNI
// inputs directly and no longer consumes the retired C++ dependency closure.
import fs from 'node:fs/promises';
import path from 'node:path';
import {shallowClone,assertSourceIdentity,fetchSource} from '../lib/git.mjs';
import {run} from '../lib/runner.mjs';
import {readJson} from '../../ci/bootstrap/sdk-flow.mjs';
const sentinels={json:'include/nlohmann/json.hpp'};
export async function readNativeToolDependencies(file,names) {
  if(!names.includes('cjlint'))return {};
  if(!file)throw Error('TOOLS_DEPENDENCIES_REQUIRED: --tools-dependencies <fixed source JSON>');
  const selection=await readJson(file),needed=['json'];
  const result={};
  for(const name of needed) {
    const row=selection[name];
    if(!row||typeof row.repo!=='string'||!row.repo||!/^[0-9a-f]{40}$/.test(row.commit??'')||!path.isAbsolute(row.path??''))throw Error('TOOLS_DEPENDENCY_SOURCE '+name);
    result[name]={repo:row.repo,commit:row.commit,path:row.path};
  }
  return result;
}
export async function prepareNativeToolDependencies(config,names) {
  if(!names.includes('cjlint'))return;
  if(process.env.CANGJIE_BUILD_DRY_RUN==='1') {
    if(!config.toolsDependencies)throw Error('TOOLS_DEPENDENCIES_REQUIRED');
    return;
  }
  const selected=await readNativeToolDependencies(config.toolsDependencies,names);
  for(const [name,row]of Object.entries(selected)) {
    try {await fs.lstat(row.path);}
    catch(error){if(error.code!=='ENOENT')throw error;await shallowClone(row.repo,row.path,{tag:row.commit});}
    const gitRoot=await run(['git','-C',row.path,'rev-parse','--show-toplevel'],{capture:true,logOutput:false,stage:'tools.dependencies'});
    if(await fs.realpath(gitRoot.stdout.trim())!==await fs.realpath(row.path))throw Error('TOOLS_DEPENDENCY_GIT_ROOT '+name);
    // Normal job handoff excludes credential-bearing .git/config. Restore
    // only the explicitly selected ordinary origin, never overwrite one.
    const remotes=await run(['git','-C',row.path,'remote'],{capture:true,logOutput:false,stage:'tools.dependencies'});
    if(!remotes.stdout.trim().split('\n').includes('origin'))await run(['git','-C',row.path,'remote','add','origin',row.repo],{stage:'tools.dependencies'});
    const head=await run(['git','-C',row.path,'rev-parse','--verify','HEAD'],{capture:true,check:false,logOutput:false,stage:'tools.dependencies'});
    if(head.exitCode!==0) {
      const origin=await run(['git','-C',row.path,'remote','get-url','origin'],{capture:true,logOutput:false,stage:'tools.dependencies'});
      if(origin.stdout.trim()!==row.repo)throw Error('TOOLS_DEPENDENCY_ORIGIN '+name);
      await fetchSource(row.repo,row.commit,{cwd:row.path,stage:'tools.dependencies'});
      await run(['git','-C',row.path,'checkout','--detach',row.commit],{stage:'tools.dependencies'});
    }
    await assertSourceIdentity({name:'native-tool-'+name,url:row.repo,tag:row.commit},row.path);
    if(!(await fs.stat(path.join(row.path,sentinels[name]))).isFile())throw Error('TOOLS_DEPENDENCY_MEMBER '+name);
  }
}
