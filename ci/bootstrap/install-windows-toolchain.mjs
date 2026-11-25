#!/usr/bin/env zx
// Install the selected official MSVCRT package; native-cjdb runs its compiler
// and installed-runtime probe before building N. This is not that qualification.
import fs from 'node:fs/promises';
import {constants,createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {download} from '../../build/lib/archive.mjs';
import {command,privateRoot} from './sdk-flow.mjs';
export const WINDOWS_TOOLCHAIN=Object.freeze({
 directory:'llvm-mingw-20261020-msvcrt-x86_64',
 url:'https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/llvm-mingw-20261020-msvcrt-x86_64.zip',
 sha256:'52a3e3f584a74c3cde8ceb0c6960549683178e03b36818cb02b7ed109a68ff67',bytes:172961237});
export async function installWindowsToolchain({work,archive,env=process.env}) {
 if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_TOOLCHAIN_NATIVE_REQUIRED');
 work=await privateRoot(work);await fs.mkdir(work,{recursive:true});
 archive=archive?path.resolve(archive):path.join(work,WINDOWS_TOOLCHAIN.directory+'.zip');
 const attempt=await fs.mkdtemp(path.join(work,'install-')),records=[];
 const staged=path.join(attempt,WINDOWS_TOOLCHAIN.directory);
 try{
  if(!await fs.stat(archive).catch(e=>{if(e.code==='ENOENT')return null;throw e;}))await download(WINDOWS_TOOLCHAIN.url,archive);
  const digest=createHash('sha256');for await(const chunk of createReadStream(archive))digest.update(chunk);
  if((await fs.stat(archive)).size!==WINDOWS_TOOLCHAIN.bytes||digest.digest('hex')!==WINDOWS_TOOLCHAIN.sha256)
   throw Error('WINDOWS_TOOLCHAIN_ARCHIVE');
  // MSYS2 prepends GNU tar for source archives; ZIP extraction uses Windows'
  // native bsdtar explicitly so PATH cannot select the incompatible tool.
  const system=env.SystemRoot||env.SYSTEMROOT;if(!system)throw Error('WINDOWS_TOOLCHAIN_SYSTEMROOT');
  await command([path.join(system,'System32/tar.exe'),'-xf',archive,'-C',attempt],{env,records});
  await privateRoot(staged);
  for(const member of ['bin/clang.exe','bin/clang++.exe','bin/llvm-readobj.exe','x86_64-w64-mingw32/bin/libc++.dll','x86_64-w64-mingw32/bin/libunwind.dll'])
   if(!(await fs.stat(path.join(staged,member))).isFile())throw Error('WINDOWS_TOOLCHAIN_PACKAGE_LAYOUT '+member);
 }finally{await fs.writeFile(path.join(attempt,'commands.json'),JSON.stringify(records,null,2)+'\n');}
 if(!env.GITHUB_ENV||!env.GITHUB_PATH)throw Error('WINDOWS_TOOLCHAIN_JOB_ENV_REQUIRED');
 const root=await privateRoot(path.join(work,WINDOWS_TOOLCHAIN.directory));
 if(await fs.lstat(root).catch(e=>{if(e.code!=='ENOENT')throw e;}))throw Error('WINDOWS_TOOLCHAIN_EXISTS '+root);
 // The runner creates both command files. Open both before publishing, so a
 // missing command file cannot leave a new install or a partial job export.
 const exports=[];
 try{
  for(const [file,line] of [[env.GITHUB_PATH,path.join(root,'bin')],[env.GITHUB_ENV,'CJCJ_WINDOWS_TOOLCHAIN='+root]]){
   // Windows append-only handles cannot truncate. Keep write access and use
   // the original EOF for both positioned writes and rollback.
   const handle=await fs.open(file,constants.O_WRONLY);
   const output={handle,line};exports.push(output);
   const stat=await handle.stat();
   if(!stat.isFile())throw Error('WINDOWS_TOOLCHAIN_JOB_ENV_REQUIRED');
   output.size=stat.size;
  }
  await fs.rename(staged,root);
  try{
   for(const output of exports){
    const buf=Buffer.from(output.line+'\n');
    output.started=true;
    for(let offset=0;offset<buf.length;){
     const {bytesWritten}=await output.handle.write(buf,offset,buf.length-offset,output.size+offset);
     if(bytesWritten===0)throw Error('WINDOWS_TOOLCHAIN_EMPTY_WRITE');
     offset+=bytesWritten;
    }
   }
  }catch(e){
   const reportRollback=err=>console.error('WINDOWS_TOOLCHAIN_ROLLBACK',err);
   for(const output of exports)if(output.started)await output.handle.truncate(output.size).catch(reportRollback);
   await fs.rename(root,staged).catch(reportRollback);
   throw e;
  }
 }catch(e){
  await Promise.allSettled(exports.map(output=>output.handle.close()));
  throw e;
 }
 await Promise.all(exports.map(output=>output.handle.close()));
 console.log('WINDOWS_TOOLCHAIN_INSTALLED '+root);return root;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const [work,archive]=process.argv.slice(2);await installWindowsToolchain({work,archive});}
 catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
