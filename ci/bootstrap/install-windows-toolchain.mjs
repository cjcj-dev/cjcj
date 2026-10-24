#!/usr/bin/env zx
// Install the selected official MSVCRT package; native-cjdb runs its compiler
// and installed-runtime probe before building N. This is not that qualification.
import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {download} from '../../build/lib/archive.mjs';
import {command,privateRoot} from './sdk-flow.mjs';
export const WINDOWS_TOOLCHAIN=Object.freeze({
 directory:'llvm-mingw-20220906-msvcrt-x86_64',
 url:'https://github.com/mstorsjo/llvm-mingw/releases/download/20220906/llvm-mingw-20220906-msvcrt-x86_64.zip',
 sha256:'1b63120c346ff78a4e3dba77101a535434a62122d3b44021438a77bdf1b4679a',bytes:124197419});
export async function installWindowsToolchain({work,archive,env=process.env}) {
 if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_TOOLCHAIN_NATIVE_REQUIRED');
 work=await privateRoot(work);await fs.mkdir(work,{recursive:true});
 archive=archive?path.resolve(archive):path.join(work,WINDOWS_TOOLCHAIN.directory+'.zip');
 if(!await fs.stat(archive).catch(e=>{if(e.code==='ENOENT')return null;throw e;}))await download(WINDOWS_TOOLCHAIN.url,archive);
 const digest=createHash('sha256');for await(const chunk of createReadStream(archive))digest.update(chunk);
 if((await fs.stat(archive)).size!==WINDOWS_TOOLCHAIN.bytes||digest.digest('hex')!==WINDOWS_TOOLCHAIN.sha256)
  throw Error('WINDOWS_TOOLCHAIN_ARCHIVE');
 const attempt=await fs.mkdtemp(path.join(work,'install-')),records=[];
 try{
  // MSYS2 prepends GNU tar for source archives; ZIP extraction uses Windows'
  // native bsdtar explicitly so PATH cannot select the incompatible tool.
  const system=env.SystemRoot||env.SYSTEMROOT;if(!system)throw Error('WINDOWS_TOOLCHAIN_SYSTEMROOT');
  await command([path.join(system,'System32/tar.exe'),'-xf',archive,'-C',attempt],{env,records});
  const root=path.join(attempt,WINDOWS_TOOLCHAIN.directory);
  for(const member of ['bin/clang.exe','bin/clang++.exe','bin/llvm-readobj.exe','x86_64-w64-mingw32/bin/libc++.dll','x86_64-w64-mingw32/bin/libunwind.dll'])
   if(!(await fs.stat(path.join(root,member))).isFile())throw Error('WINDOWS_TOOLCHAIN_PACKAGE_LAYOUT '+member);
  if(!env.GITHUB_ENV||!env.GITHUB_PATH)throw Error('WINDOWS_TOOLCHAIN_JOB_ENV_REQUIRED');
  await fs.appendFile(env.GITHUB_PATH,path.join(root,'bin')+'\n');
  await fs.appendFile(env.GITHUB_ENV,'CJCJ_WINDOWS_TOOLCHAIN='+root+'\n');
  console.log('WINDOWS_TOOLCHAIN_INSTALLED '+root);return root;
 }finally{await fs.writeFile(path.join(attempt,'commands.json'),JSON.stringify(records,null,2)+'\n');}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const [work,archive]=process.argv.slice(2);await installWindowsToolchain({work,archive});}
 catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
