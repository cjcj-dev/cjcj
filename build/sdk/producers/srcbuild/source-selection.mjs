#!/usr/bin/env zx
// Export the ordinary source options used by public fetch/build. The fetch
// command persists these same options through buildConfig/saveSourceSelection.
import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepos,REPO_NAMES} from '../../../lib/config.mjs';
// The native Windows SDK builds the same public tools commit as every other host:
// the product tools pin of ci/source_pin.env (no private repository, no read token).
export const windowsToolsDefaultRepository='cjcj-dev/cjcj-tools';
export const windowsToolsCommit=(()=>{
  const match=/^TOOLS_REF=([0-9a-f]{40})$/m.exec(fsSync.readFileSync(new URL('../../../../ci/source_pin.env',import.meta.url),'utf8'));
  if(!match)throw Error('WINDOWS_TOOLS_PIN ci/source_pin.env TOOLS_REF');
  return match[1];
})();
export function windowsToolsSource(env) {
  const repo=env.WINDOWS_TOOLS_REPOSITORY||windowsToolsDefaultRepository;
  if(!/^[\w.-]+\/[\w.-]+$/.test(repo)||repo.split('/').some(s=>s==='.'||s==='..'))throw Error('WINDOWS_TOOLS_REPOSITORY_INVALID');
  return {url:new URL(repo,(env.GITHUB_SERVER_URL||'https://github.com')+'/').href,tag:windowsToolsCommit};
}
export function workflowSourceSelection(env=process.env) {
  const overrides=JSON.parse(env.CJCJ_SOURCE_SELECTION||'{}');
  if(!overrides||Array.isArray(overrides)||typeof overrides!=='object'
    ||Object.keys(overrides).some(name=>!REPO_NAMES.includes(name)))throw Error('WORKFLOW_SOURCE_SELECTION');
  // Ordinary repository options and the canonical pair meet in buildConfig's
  // resolver. Persist only those options; do not create a second native JSON
  // environment selection alongside the workspace's normal source options.
  if(env.COMPILER_SRC_URL&&env.CANGJIE_COMPILER_SHA&&!overrides.compiler)
    overrides.compiler={url:env.COMPILER_SRC_URL,tag:env.CANGJIE_COMPILER_SHA};
  // Only the native Windows SDK selects this paired producer. Propagate it
  // through the ordinary fetch options and their persisted workspace record.
  if(env.CJCJ_SRCBUILD_TARGET==='windows-x64' && env.CJCJ_NATIVE_RUNTIME_ARTIFACT) {
    const pair=windowsToolsSource(env);
    if(overrides.tools && Object.entries(overrides.tools).some(([k,v])=>pair[k]!==v))
      throw Error('WINDOWS_TOOLS_SOURCE_PAIR_CHANGED');
    overrides.tools=pair;
  }
  const repos=makeRepos({overrides,env}),result={};
  for(const name of REPO_NAMES) {
    const {url,tag}=repos[name];
    if(!url||/[\r\n]/.test(url)||!/^[a-f0-9]{40}$/.test(tag||''))throw Error('WORKFLOW_FIXED_SOURCE_REQUIRED '+name);
    const prefix=name.toUpperCase();
    result[name==='llvm'?'LLVM_URL':prefix+'_SRC_URL']=url;
    const ref={compiler:'CANGJIE_COMPILER_SHA',llvm:'CJCJ_NATIVE_LLVM_REF',runtime:'CJCJ_NATIVE_RUNTIME_REF'}[name];
    result[ref || prefix+'_REF']=tag;
  }
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
