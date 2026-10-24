#!/usr/bin/env zx
// Export the ordinary source options used by public fetch/build. The fetch
// command persists these same options through buildConfig/saveSourceSelection.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepos,REPO_NAMES} from '../../build/lib/config.mjs';
import {nativePair} from '../runtime-pin.mjs';
import {nativeSourceSelection} from '../bootstrap/native-source-selection.mjs';
export function workflowSourceSelection(env=process.env) {
  const overrides=JSON.parse(env.CJCJ_SOURCE_SELECTION||'{}');
  if(!overrides||Array.isArray(overrides)||typeof overrides!=='object'
    ||Object.keys(overrides).some(name=>!REPO_NAMES.includes(name)))throw Error('WORKFLOW_SOURCE_SELECTION');
  const pair=nativePair(env);
  if(!pair) {
    if(env.CANGJIE_COMPILER_URL&&env.CANGJIE_COMPILER_SHA)
      overrides.compiler={url:env.CANGJIE_COMPILER_URL,tag:env.CANGJIE_COMPILER_SHA,...overrides.compiler};
    if(env.RUNTIME_REF&&env.RUNTIME_SRC_URL) {
      const row=overrides.runtime;
      if(row&&(row.url!==undefined&&row.url!==env.RUNTIME_SRC_URL||row.tag!==undefined&&row.tag!==env.RUNTIME_REF))
        throw Error('WORKFLOW_NATIVE_SOURCE_CONFLICT runtime');
      overrides.runtime={url:env.RUNTIME_SRC_URL,tag:env.RUNTIME_REF};
    }
  }
  if(pair) {
    const {selection}=nativeSourceSelection(env,pair);
    for(const [name,key] of [['compiler','ast'],['runtime','runtime']]) {
      const selected={url:selection[key].repository,tag:selection[key].commit},given=overrides[name];
      if(given&&(given.url!==undefined&&given.url!==selected.url||given.tag!==undefined&&given.tag!==selected.tag))
        throw Error('WORKFLOW_NATIVE_SOURCE_CONFLICT '+name);
      overrides[name]=selected;
    }
  }
  const repos=makeRepos({overrides}),result={};
  for(const name of REPO_NAMES) {
    const {url,tag}=repos[name];
    if(!url||/[\r\n]/.test(url)||!/^[a-f0-9]{40}$/.test(tag||''))throw Error('WORKFLOW_FIXED_SOURCE_REQUIRED '+name);
    const prefix=name==='compiler'?'CANGJIE_COMPILER':name.toUpperCase();
    result[prefix+(name==='compiler'?'_URL':'_SRC_URL')]=url;
    result[prefix+(name==='compiler'?'_SHA':'_REF')]=tag;
  }
  if(pair)result.LLVM_SHA=pair.llvm;
  return result;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    if(!process.env.GITHUB_ENV)throw Error('GITHUB_ENV required');
    const selected=workflowSourceSelection();
    await fs.appendFile(process.env.GITHUB_ENV,Object.entries(selected).map(([k,v])=>`${k}=${v}\n`).join(''));
    console.log(JSON.stringify(selected));
  }catch(error){console.error(error.stack);process.exitCode=1;}
}
