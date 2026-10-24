#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {fileDigest, readJson} from './sdk-io.mjs';
import {entryPlatformName, sdkPlatform} from './sdk-platform.mjs';
const names=['cjc','cjc-frontend','cjc-upstream-oracle','cjc-oracle','cjcj-stage1','cjcj-stage2','cjcj'];
const exists=async file=>{try{return await fs.lstat(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}};
export async function compilerProducer(sdk) {
  const record=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  if(typeof record.compilerFile!=='string'||path.isAbsolute(record.compilerFile)
    ||record.compilerFile.includes('\\')||record.compilerFile.split('/').includes('..'))
    throw new Error('COMPILER_IDENTITY invalid compiler path');
  return path.join(sdk,record.compilerFile);
}
export async function verifyCompiler(sdk,expectedProducerSha256) {
  const record=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  const expected=record.compilerSha256, producer=await compilerProducer(sdk);
  if(!/^[a-f0-9]{64}$/.test(expected||''))throw new Error('COMPILER_IDENTITY invalid producer record');
  if(expectedProducerSha256!==undefined){
    if(!/^[a-f0-9]{64}$/.test(expectedProducerSha256))throw new Error('COMPILER_IDENTITY invalid expected producer SHA-256');
    if(expected!==expectedProducerSha256)throw new Error('COMPILER_IDENTITY independent bootstrap producer mismatch');
  }
  if(await fileDigest(producer)!==expected)throw new Error('COMPILER_IDENTITY producer hash mismatch');
  const suffix=record.platform?sdkPlatform(record.platform).exe:(producer.endsWith('.exe')?'.exe':'');
  for(const name of names){
    const file=path.join(sdk,'bin',name+suffix),stat=await exists(file);
    if(['cjc','cjc-frontend','cjcj-stage1'].includes(name)){
      if(!stat)throw new Error('COMPILER_IDENTITY missing '+name);
      if(name!=='cjcj-stage1'&&(!stat.isSymbolicLink()||await fs.readlink(file)!=='cjcj-stage1'+suffix))throw new Error('COMPILER_IDENTITY '+name+': expected same-directory cjcj-stage1 link');
      if(name==='cjcj-stage1'){
        if(!stat.isFile()||stat.isSymbolicLink())throw new Error('COMPILER_IDENTITY producer entry must be a physical copy');
        if(path.resolve(file)!==path.resolve(producer)){
          const recipe=(await fs.readFile(file+'.entry','utf8')).trimEnd().split('\n');
          if(recipe[0]!=='cjcj-sdk-entry-v1'||recipe[1]!=='1'||recipe[2]!==record.compilerFile||recipe[4]!== (record.platform?'native-target:'+sdkPlatform(record.platform).arch:'native-target')||recipe.slice(5).some(rel=>!rel||path.isAbsolute(rel)||rel.includes('\\')||rel.split('/').includes('..'))
            ||(record.platform&&recipe[3]!==entryPlatformName(record.platform)))
            throw new Error('COMPILER_IDENTITY entry producer mismatch');
          // The launcher is an ordinary build output shared by the installed entries.
          // Its recorded bytes are checked independently of the raw compiler bytes.
          if(!/^[a-f0-9]{64}$/.test(record.compilerEntrySha256||'')||await fileDigest(file)!==record.compilerEntrySha256)
            throw new Error('COMPILER_IDENTITY entry bytes mismatch');
        }
      }
    }else if(stat)throw new Error('COMPILER_IDENTITY '+name+': stale compiler component');
    if(suffix&&await exists(path.join(sdk,'bin',name)))throw new Error('COMPILER_IDENTITY stale compiler component without executable suffix');
  }
  if(path.resolve(producer)!==path.resolve(sdk,'bin/cjcj-stage1'+suffix)) {
    for(const name of ['cjc','cjc-frontend']) {
      const alias=path.join(path.dirname(producer),name+suffix),stat=await exists(alias);
      console.log('COMPILER_RETAINED_ALIAS_ASSERTION_REACHED '+JSON.stringify({alias,exists:!!stat}));
      if(!stat?.isSymbolicLink()||await fs.readlink(alias)!==path.basename(producer))
        throw Error('COMPILER_RETAINED_ALIAS '+name);
    }
    const execution=record.selection?.compilerExecution;
    if(execution) {
      const prefix=execution.role==='bootstrap-host'?'.host':execution.role==='separate'?'.compiler-exec':'';
      const native=sdkPlatform(execution.platform),runtime=(prefix?prefix+'/':'')+'runtime';
      const recipe=(await fs.readFile(path.join(sdk,'bin/cjcj-stage1'+suffix+'.entry'),'utf8')).trimEnd().split('\n');
      const libraries=recipe.slice(5),wanted=runtime+'/lib/'+native.tuple;
      const linked=await fs.readlink(path.join(sdk,'libexec/runtime'));
      console.log('COMPILER_EXECUTION_ASSERTION_REACHED '+JSON.stringify({role:execution.role,wanted,libraries,linked}));
      if(libraries[0]!==wanted||linked!=='../'+runtime)throw Error('COMPILER_EXECUTION_ROLE');
    }
  }
  console.log('COMPILER_IDENTITY_TARGET_ASSERTION_REACHED '+JSON.stringify({producer,expected,independent:expectedProducerSha256}));
  return record;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  try{
    const {values,positionals}=parseArgs({options:{'expected-producer-sha256':{type:'string'}},allowPositionals:true});
    if(positionals.length!==1)throw new Error('usage: compiler_identity.mjs sdk [--expected-producer-sha256 sha]');
    console.log(JSON.stringify(await verifyCompiler(positionals[0],values['expected-producer-sha256'])));
  }catch(e){console.error(e.message);process.exitCode=1;}
}
