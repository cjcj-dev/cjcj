#!/usr/bin/env zx
// Export the ordinary source options used by public fetch/build. The fetch
// command persists these same options through buildConfig/saveSourceSelection.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepos,REPO_NAMES} from '../../build/lib/config.mjs';
export function workflowSourceSelection(env=process.env) {
  const overrides=JSON.parse(env.CJCJ_SOURCE_SELECTION||'{}');
  if(!overrides||Array.isArray(overrides)||typeof overrides!=='object'
    ||Object.keys(overrides).some(name=>!REPO_NAMES.includes(name)))throw Error('WORKFLOW_SOURCE_SELECTION');
  // Ordinary repository options and the canonical pair meet in buildConfig's
  // resolver. Persist only those options; do not create a second native JSON
  // environment selection alongside the workspace's normal source options.
  if(env.CANGJIE_COMPILER_URL&&env.CANGJIE_COMPILER_SHA&&!overrides.compiler)
    overrides.compiler={url:env.CANGJIE_COMPILER_URL,tag:env.CANGJIE_COMPILER_SHA};
  const repos=makeRepos({overrides,env}),result={};
  for(const name of REPO_NAMES) {
    const {url,tag}=repos[name];
    if(!url||/[\r\n]/.test(url)||!/^[a-f0-9]{40}$/.test(tag||''))throw Error('WORKFLOW_FIXED_SOURCE_REQUIRED '+name);
    const prefix=name==='compiler'?'CANGJIE_COMPILER':name.toUpperCase();
    result[prefix+(name==='compiler'?'_URL':'_SRC_URL')]=url;
    result[prefix+(name==='compiler'?'_SHA':'_REF')]=tag;
  }
  result.CJCJ_NATIVE_LLVM_REF=repos.llvm.tag;
  result.CJCJ_NATIVE_RUNTIME_REF=repos.runtime.tag;
  delete result.LLVM_REF;delete result.RUNTIME_REF;
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
