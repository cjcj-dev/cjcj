#!/usr/bin/env zx
// Linux-only integration apparatus. Windows filesystem/commands and the pinned
// download are explicitly controlled; collector, XML parser, decoder, selector,
// compiler-version check and public callers are the actual product modules.
import {mock} from 'node:test';
import fs from 'node:fs/promises';
import path from 'node:path';
import * as child from 'node:child_process';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';
const [mode,configFile]=process.argv.slice(2),config=JSON.parse(await fs.readFile(configFile,'utf8'));
const physical=value=>typeof value==='string'&&/^[cC]:[\\/]/.test(value)
 ?value.slice(2).replaceAll('\\','/').replace(/\/libllvm-15\.dll$/i,'/libLLVM-15.dll'):value;
const virtual=value=>'C:'+value;
const mapped={...fs};
for(const name of ['readFile','writeFile','appendFile','mkdir','stat','lstat','open','readdir','unlink'])
 mapped[name]=(file,...args)=>fs[name](physical(file),...args);
mapped.rename=(a,b)=>fs.rename(physical(a),physical(b));
mapped.realpath=async file=>{const result=await fs.realpath(physical(file));return physical(file)!==file?virtual(result):result;};
mock.module('node:fs/promises',{defaultExport:mapped,namedExports:mapped});
const paths={...path,isAbsolute:value=>/^[cC]:[\\/]/.test(value)||path.isAbsolute(value),
 resolve:(...args)=>{if(args.some(a=>typeof a==='string'&&/^[cC]:[\\/]/.test(a)))return virtual(path.resolve(...args.map(physical)));return path.resolve(...args);}};
mock.module('node:path',{defaultExport:paths,namedExports:paths});
const options=o=>({...o,cwd:physical(o?.cwd),env:{...o?.env,PATH:config.nativePath}});
const program=p=>p==='python'?config.python:physical(p);
const execFile=(p,args,o,cb)=>child.execFile(program(p),args.map(physical),options(o),cb);
execFile[promisify.custom]=(p,args,o)=>new Promise((resolve,reject)=>execFile(p,args,o,(error,stdout,stderr)=>{
 if(error){Object.assign(error,{stdout,stderr});reject(error);}else resolve({stdout,stderr});
}));
const spawn=(p,args,o)=>child.spawn(program(p),args.map(physical),options(o));
const {default:childDefault,...childNames}=child;
mock.module('node:child_process',{namedExports:{...childNames,execFile,spawn},defaultExport:{...childDefault,execFile,spawn}});
const provenance=await import('../../build/lib/release-component-provenance.mjs');
mock.module(new URL('../../build/lib/release-component-provenance.mjs',import.meta.url).href,
 {namedExports:{...provenance,baseSdkDownload:()=>config.download}});
Object.defineProperty(process,'platform',{value:'win32'});
Object.assign(process.env,config.env);
if(mode==='configure'){
 const exported=Object.fromEntries((await fs.readFile(physical(config.env.GITHUB_ENV),'utf8')).trim().split('\n').map(line=>{
  const at=line.indexOf('=');return[line.slice(0,at),line.slice(at+1)];}));
 Object.assign(process.env,exported);
}
const entry=new URL(mode==='configure'?'../bootstrap/configure-gha-inputs.mjs':'../bootstrap/prepare-native-host.mjs',import.meta.url);
process.argv[1]=entry.pathname;
console.log('SYNTHETIC_WINDOWS_APPARATUS actualPublicEntry='+entry.pathname);
await import(pathToFileURL(entry.pathname));
