#!/usr/bin/env zx
// Transfer the source-built tool outputs into the native SDK. H remains
// under .host for build execution; public tool ownership moves to these outputs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {copyOutputs, fileDigest, atomicJson, privateRoot, publishPaths} from '../../ci/bootstrap/sdk-flow.mjs';
import {installationRecipe} from '../../ci/bootstrap/sdk-targets.mjs';
import {installEntries} from '../../ci/bootstrap/sdk-install-entries.mjs';
import {sdkPlatform} from '../../ci/bootstrap/sdk-platform.mjs';
import {installPath as mingwInstallPath} from '../toolchain/mingw.mjs';
import {installedToolBuildInputs,sdkInputs} from './tool-build-inputs.mjs';
import {TOOL_NAMES,requireToolProducer,toolOutputs,toolPayloads,retainedToolPath} from './tool-layout.mjs';

export const sourceToolOutputs=toolOutputs;
export async function installSourceTools(config, installRoot=path.join(config.softwareDir,'cangjie'), {consume,dependencies}={}) {
  for(const name of TOOL_NAMES)requireToolProducer(name);
  const original=await privateRoot(installRoot);
  if(process.env.CANGJIE_BUILD_DRY_RUN==='1')return {status:'NOT_INSTALLED',reason:'DRY_RUN'};
  if(!config.target.spec.crossCompile&&!consume)throw Error('SOURCE_TOOL_CONSUMER_REQUIRED');
  const native=sdkPlatform(config.target.spec.llvmPlatform),rows=sourceToolOutputs(config);
  const records=[],files={};
  // Validate the complete produced set before modifying any installed tool.
  for(const row of rows){
    if(!(await fs.stat(row.from)).isFile())throw new Error('SOURCE_TOOL_OUTPUT '+row.name);
    const name=row.producer;
    files[row.to]={source:row.from,sha256:await fileDigest(row.from),producer:await installedToolBuildInputs(config,name,row.from)};
  }
  const payloads=(await Promise.all(rows.map(row=>toolPayloads(config,row.producer)))).flat();
  const payloadFiles={};
  for(const row of payloads){
    const sha256=await fileDigest(row.from),previous=payloadFiles[row.to];
    if(previous&&previous.sha256!==sha256)throw new Error('SOURCE_TOOL_PAYLOAD_COLLISION '+row.to);
    payloadFiles[row.to]={sha256,producers:[...(previous?.producers??[]),row.producer]};
  }
  // Independent HLE producer must already have supplied its runtime closure.
  for(const relative of ['tools/dtsparser/DEPENDENCIES.json','tools/bin/node'+native.exe,'tools/dtsparser/node_modules/.bin/cjbind'+native.exe])await fs.access(path.join(dependencies?.root??original,relative));
  // Prepare only the tool-owned directory boundaries, leaving old public
  // tools and all their retained bodies usable throughout launcher production.
  const sdk=await fs.mkdtemp(original+'.tools-pending-');
  for(const relative of ['tools','.target-tools/tools']) {
    if(await fs.stat(path.join(original,relative)).catch(error=>{if(error.code==='ENOENT')return null;throw error;}))
      await copyOutputs(sdk,[{from:path.join(original,relative),to:relative,owner:'existing tool payload'}]);
  }
  if(dependencies)for(const relative of ['tools/dtsparser','tools/bin/node'+native.exe]) {
    await fs.rm(path.join(sdk,relative),{recursive:true,force:true});
    await copyOutputs(sdk,[{from:path.join(dependencies.root,relative),to:relative,owner:'HLE dependencies'}]);
  }
  for(const row of rows){
    const installed=path.join(sdk,row.to),recipe=installed+'.entry';
    try{
      const lines=(await fs.readFile(recipe,'utf8')).trimEnd().split('\n');
      if(lines[0]!=='cjcj-sdk-entry-v1'||![ '.host-tools/tools/bin/'+row.name,'.target-tools/tools/bin/'+row.name,retainedToolPath(row)].includes(lines[2]))
        throw new Error('SOURCE_TOOL_OWNERSHIP '+row.name);
      if(lines[2].startsWith('.target-tools/'))await fs.rm(path.join(sdk,lines[2]),{force:true});
      await fs.unlink(recipe);
    }catch(e){if(e.code!=='ENOENT')throw e;}
    await fs.rm(installed,{force:true}); // This exact public H tool is superseded.
  }
  const recipe=installationRecipe({platform:config.target.spec.llvmPlatform},{tools:{rows,payloads}});
  await copyOutputs(sdk,recipe.copies.filter(row=>rows.some(tool=>tool.to===row.to)));
  // cjprof owns these static subtrees. A normal source update may delete or
  // rename a page; copying only today's members leaves yesterday's pages live.
  // Other tools share tools/config, so replace only the two owned subtrees.
  for(const relative of ['tools/config/static','.target-tools/tools/config/static','.target-tools/tools/cjlint']) {
    const directory=await privateRoot(path.join(sdk,relative));
    await fs.rm(directory,{recursive:true,force:true});
  }
  for(const {from:source,to:relative}of payloads){
    await privateRoot(path.dirname(path.join(sdk,relative)));
    await fs.rm(path.join(sdk,relative),{force:true});
    await copyOutputs(sdk,[{from:source,to:relative,owner:'source-built tools'}]);
  }
  await installEntries({root:sdk,build:path.join(config.workspace,'build/source-tool-entries'),
    groups:recipe.entries,
    // A cross target installs a launcher for that target, so the toolchain that
    // produces it travels with the call: without it the host compiler would
    // build the host's launcher and the installation would carry a binary the
    // target OS cannot start.
    tools:{launcher:process.env.CMAKE_CXX_COMPILER_LAUNCHER,
      ...(config.target.spec.needsMingw?{targetToolchain:path.join(mingwInstallPath(config.buildRoot),'bin')}:{})},
    records,platform:config.target.spec.llvmPlatform});
  for(const row of rows){
    const retained=retainedToolPath(row);
    if(await fileDigest(path.join(sdk,retained))!==files[row.to].sha256)throw new Error('SOURCE_TOOL_RETAINED_BYTES '+row.name);
    files[row.to].artifact={path:retained,sha256:files[row.to].sha256};
    files[row.to].entry={path:row.to,sha256:await fileDigest(path.join(sdk,row.to)),
      recipe:{path:row.to+'.entry',sha256:await fileDigest(path.join(sdk,row.to+'.entry'))}};
  }
  // The destination selection is an install fact, not a rewrite of any old
  // producer's build inputs. Record it once for native macro consumers; their
  // applicability is determined at the consumer, not by copying these facts.
  const installationInputs=rows.some(row=>row.producer==='lsp'
    &&files[row.to].producer.source.status==='resolved')?await sdkInputs(config,original):undefined;
  await atomicJson(path.join(sdk,'TOOLS-INPUTS.json'),{files,payloadFiles,commands:records,installationInputs,
    buildSelection:{phase:config.toolsPhase??'all',builtThisInvocation:config.toolsPhase==='install'?'none':config.toolsBuildSet??'all',
      reusedExistingOutputs:config.toolsPhase==='install'?TOOL_NAMES:config.toolsBuildSet&&config.toolsBuildSet!=='all'
        ? TOOL_NAMES.filter(name=>!config.toolsBuildSet.split(',').includes(name)):[]}});
  if(consume)await consume(sdk);
  await publishPaths(['tools','.target-tools/tools','TOOLS-INPUTS.json'].map(relative=>({pending:path.join(sdk,relative),destination:path.join(original,relative)})));
  console.log('SOURCE_TOOLS_INSTALLED '+JSON.stringify(files));
  return files;
}
