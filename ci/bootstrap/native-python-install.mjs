#!/usr/bin/env zx
// Carry the Windows producer's complete layout and unedited observations into N.
import fs from 'node:fs/promises';
import path from 'node:path';
import {copyOutputs,fileDigest,readJson,relative} from './sdk-flow.mjs';
export const PYTHON_BUILD_INPUTS='PYTHON-BUILD-INPUTS.json';
const sha=value=>/^[a-f0-9]{64}$/.test(value||'');
export async function readWindowsPythonInstallation(root,{record=path.join(root,PYTHON_BUILD_INPUTS),sha256}={}) {
 const hash=await fileDigest(record);
 if(sha256&&hash!==sha256)throw Error('PYTHON_INSTALL_RECORD_BYTES');
 const facts=await readJson(record);
 if(facts.rc!==0||facts.target!=='windows_x86_64'||facts.host!=='windows_x86_64'
   ||facts.source?.version!=='3.11.17'||!sha(facts.source?.sha256)
   ||!Array.isArray(facts.commands)||!facts.commands.length||facts.commands.at(-1)?.rc!==0)throw Error('PYTHON_INSTALL_PRODUCER');
 const entries=facts.installation?.entries;
 if(!Array.isArray(entries)||new Set(entries).size!==entries.length
   ||['python.exe','pythonw.exe','python311.dll','python3.dll','include','libs','DLLs','Lib','LICENSE.txt'].some(name=>!entries.includes(name))
   ||!entries.some(name=>/^vcruntime.*\.dll$/i.test(name)))throw Error('PYTHON_INSTALL_ENTRIES');
 for(const entry of entries){relative(entry);if(entry.includes('/'))throw Error('PYTHON_INSTALL_ENTRIES');await fs.stat(path.join(root,entry));}
 for(const rel of ['python.exe','pythonw.exe','python311.dll','python3.dll','include/Python.h','include/pyconfig.h','libs/python311.lib',
   'Lib/os.py','Lib/ssl.py','Lib/ctypes/__init__.py','DLLs/_ssl.pyd','DLLs/_ctypes.pyd','LICENSE.txt',...entries.filter(name=>/^vcruntime.*\.dll$/i.test(name))])
   if(facts.files?.[rel]?.type!=='file')throw Error('PYTHON_INSTALL_REQUIRED '+rel);
 const products=[];const realRoot=await fs.realpath(root);
 async function check(rel,row){
  relative(rel);
  if(!sha(row?.sha256))throw Error('PYTHON_INSTALL_ARTIFACT '+rel);
  const file=path.join(root,rel),real=await fs.realpath(file);
  if(!real.startsWith(realRoot+path.sep)||await fileDigest(file)!==row.sha256)throw Error('PYTHON_INSTALL_BYTES '+rel);
  products.push({path:rel,sha256:row.sha256});
 }
 for(const [rel,row]of Object.entries(facts.files??{})){
  if(row.type==='directory')continue;
  if(row.type!=='file')throw Error('PYTHON_INSTALL_FILE_TYPE '+rel);
  await check(rel,row);
 }
 // LLVM/LLDB may add files to the native prefix. Preserve and check every
 // original Python file without attributing those later products to Python.
 for(const rel of Object.keys(facts.files??{}))if(!entries.includes(rel.split('/')[0]))throw Error('PYTHON_INSTALL_UNCOPIED '+rel);
 if(!facts.originals||!Object.keys(facts.originals).length)throw Error('PYTHON_INSTALL_ORIGINALS');
 for(const row of Object.values(facts.originals))await check(row.path,row);
 return {facts,record:{path:PYTHON_BUILD_INPUTS,sha256:hash},entries,artifacts:products};
}
export async function copyWindowsPythonInstallation({root,nativeRoot,inputs}) {
 if(!inputs?.record||!inputs.sha256)throw Error('PYTHON_INSTALL_INPUTS');
 const original=await readWindowsPythonInstallation(root,inputs);
 await copyOutputs(nativeRoot,[...original.entries.map(rel=>({from:path.join(root,rel),to:rel,owner:'Python'})),
  {from:inputs.record,to:PYTHON_BUILD_INPUTS,owner:'Python original inputs'},
  ...Object.values(original.facts.originals).map(row=>({from:path.join(root,row.path),to:row.path,owner:'Python original output'}))]);
 const installed=await readWindowsPythonInstallation(nativeRoot,{sha256:original.record.sha256});
 return {record:'third_party/llvm/'+installed.record.path,sha256:installed.record.sha256};
}
