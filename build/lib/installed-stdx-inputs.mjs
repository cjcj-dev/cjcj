#!/usr/bin/env zx
// Consume the native producer's existing observations after relocation. The
// requested profile is not evidence that the configured/install set was full.
import fs from 'node:fs/promises';
import path from 'node:path';
import {STDX_BUILD_INPUTS} from '../srcbuild/stdx-build-inputs.mjs';
const fail=message=>{throw new Error('INSTALLED_STDX_'+message);};
function relative(value){
 if(typeof value!=='string'||!value||path.posix.isAbsolute(value)||value.includes('\\')||value.split('/').includes('..'))fail('PATH');
 return value;
}
export async function readInstalledStdxInputs({sdk,platform,requireFull=false}){
 const facts=JSON.parse(await fs.readFile(path.join(sdk,STDX_BUILD_INPUTS),'utf8'));
 const {source,build,install,artifacts}=facts;
 if(facts.component!=='stdx'||source?.status!=='resolved'||!source.repository||!/^[0-9a-f]{40}$/.test(source.commit||''))fail('SOURCE');
 if(build?.rc!==0||build.platform!==platform||!Array.isArray(build.argv)||!build.argv.length||install?.rc!==0||!Array.isArray(install.argv)||!install.argv.length
   ||!build.configuration?.values)fail('PRODUCER');
 const values=build.configuration.values;
 if(requireFull){
  for(const key of ['CHIR','SYNTAX','EFFECT_HANDLERS','PLUGIN','ASPECT_CJ'])
   if(values['CANGJIE_BUILD_WITHOUT_'+key]!=='OFF')fail('FULL_CONFIGURATION '+key);
  if(install.prefix!=='stdx')fail('FULL_INSTALL_ROOT');
 }
 const prefix=relative(install.prefix),names=new Set();
 if(!Array.isArray(artifacts)||!artifacts.length)fail('EMPTY_INSTALL');
 const root=await fs.realpath(sdk);
 for(const product of artifacts){
  const name=relative(product.path);
  if(names.has(name))fail('ARTIFACT');
  names.add(name);
  if(prefix!=='.'&&!name.startsWith(prefix+'/'))fail('INSTALL_PREFIX');
  const file=path.join(root,name),real=await fs.realpath(file),stat=await fs.lstat(file);
  if(!real.startsWith(root+path.sep))fail('INSTALL_ESCAPE');
  if(stat.isSymbolicLink()?typeof product.link!=='string'||await fs.readlink(file)!==product.link:!stat.isFile()||product.link!==undefined)fail('INSTALL_LINK');
 }
 return facts;
}
