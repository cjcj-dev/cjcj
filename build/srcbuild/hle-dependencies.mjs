#!/usr/bin/env zx
// Install separately acquired dependencies into the same SDK as the native HLE.
// This step never downloads packages or executes their install scripts.
import fs from 'node:fs/promises';
import path from 'node:path';
import {privateRoot,copyOutputs,atomicJson,fileDigest,publishPaths} from '../../ci/bootstrap/sdk-flow.mjs';
import {sdkPlatform} from '../../ci/bootstrap/sdk-platform.mjs';
import {assertLauncherFormat} from '../../ci/bootstrap/sdk-install-entries.mjs';
export async function installHleDependencies({toolsRoot,sdk,platform,input,prepareOnly=false}) {
  if(!input)throw new Error('HLE_DEPENDENCIES_REQUIRED: target Node, npm dependency tree and cjbind input');
  const native=sdkPlatform(platform);
  if(input.platform!==platform)throw new Error('HLE_DEPENDENCIES_PLATFORM');
  for(const key of ['node','modules','cjbind'])if(!input[key]?.source || !input[key]?.version || !input[key]?.path)throw new Error('HLE_DEPENDENCY_SOURCE '+key);
  const parser=path.join(toolsRoot,'hyperlangExtension/src/dtsparser');
  const manifest=JSON.parse(await fs.readFile(path.join(parser,'package.json'),'utf8'));
  for(const [name,wanted]of Object.entries(manifest.dependencies)) {
    const expected=wanted.replace(/^npm:[^@]+@/,'');
    const actual=JSON.parse(await fs.readFile(path.join(input.modules.path,name,'package.json'),'utf8'));
    if(actual.name!==name || actual.version!==expected)throw new Error('HLE_DEPENDENCY_VERSION '+name);
  }
  // HLE uses --auto-cstring, --array-pointers-in-args, --no-layout-test,
  // optional --no-detect-include-path, -p/-o and header -- clang arguments.
  // Both the original release and upstream 0.3.6 provide that CLI contract.
  // Preserve the producer's version/source; this is not production qualification.
  if(!['v1.1.0-alpha.53.1','0.3.6'].includes(input.cjbind.version))throw new Error('HLE_DEPENDENCY_VERSION cjbind');
  await assertLauncherFormat({binary:input.node.path,native,platform});
  await assertLauncherFormat({binary:input.cjbind.path,native,platform});
  sdk=await privateRoot(sdk);
  await fs.mkdir(path.dirname(sdk),{recursive:true});
  const pending=await fs.mkdtemp(sdk+'.hle-pending-');
  const destination=path.join(pending,'tools/dtsparser');
  const exclude=(await fs.readdir(parser)).filter(name=>name.endsWith('.cj') || name==='node_modules');
  await copyOutputs(pending,[{from:parser,to:'tools/dtsparser',owner:'fixed HLE parser',exclude},
    {from:input.modules.path,to:'tools/dtsparser/node_modules',exclude:['.bin'],owner:'explicit npm dependency tree'},
    {from:input.node.path,to:'tools/bin/node'+native.exe,owner:'target Node'},
    {from:input.cjbind.path,to:'tools/dtsparser/node_modules/.bin/cjbind'+native.exe,owner:'target cjbind'}]);
  const facts={platform,node:{...input.node,sha256:await fileDigest(input.node.path)},modules:input.modules,
    cjbind:{...input.cjbind,sha256:await fileDigest(input.cjbind.path)}};
  await atomicJson(path.join(destination,'DEPENDENCIES.json'),facts);
  if(prepareOnly)return {root:pending,facts};
  await publishPaths(['tools/dtsparser','tools/bin/node'+native.exe].map(relative=>({pending:path.join(pending,relative),destination:path.join(sdk,relative)})));
  return facts;
}
