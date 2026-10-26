#!/usr/bin/env zx
// Package only this invocation's successful installation, then consume it again.
import fs from 'node:fs/promises';
import path from 'node:path';
import {capture} from './windows_runtime_capture.mjs';
import {runConsumers} from './windows_runtime_consumers.mjs';
const root=path.resolve(process.env.PLATFORM_CI_ROOT||'.platform-ci');
const install=path.join(root,'runtime-install'),restored=path.join(root,'runtime-unpacked'),archive=path.join(root,'runtime-install.tar');
await fs.mkdir(restored); // never adopt an old unpacked installation
for(const [label,args]of [['package',['tar','-cf',archive,'-C',install,'.']],['unpack',['tar','-xf',archive,'-C',restored]]]) {
 const rc=await capture(label,args);if(rc)process.exit(rc);
}
async function definition(dir) {
 for(const e of await fs.readdir(dir,{withFileTypes:true})) {
  const file=path.join(dir,e.name);if(e.isFile()&&e.name==='windows_x86_64_exports.def')return file;
  if(e.isDirectory()){const found=await definition(file);if(found)return found;}
 }
}
const expected=await definition(restored);if(!expected)throw Error('unpacked registered runtime definition missing');
const entry=path.join(import.meta.dirname,'verify_windows_runtime_exports.mjs');
const result=await $({nothrow:true})`npx --yes zx@8 ${entry} ${restored} --expected-def ${expected} --reference-services`;
const verifierOk=result.ok===true&&!result.signal;
const failedRc=Number.isInteger(result.exitCode)&&result.exitCode>0?result.exitCode:1;
const summary={archive,restored,expected,
 verifier:{rc:result.exitCode,signal:result.signal,ok:result.ok,
  cause:result.cause?{name:result.cause.name,message:result.cause.message,code:result.cause.code,stack:result.cause.stack}:null},
 native:{status:'NOT_RUN'},rc:verifierOk?0:failedRc};
const summaryFile=path.join(root,'unpacked-consumer.json');
await fs.writeFile(summaryFile,JSON.stringify(summary));
if(verifierOk) {
 try {
  summary.rc=await runConsumers(restored,'unpacked');
  summary.native={rc:summary.rc};
 }catch(error) {
  summary.rc=1;summary.native={error:String(error)};
  console.error(error.stack);
 }finally {await fs.writeFile(summaryFile,JSON.stringify(summary));}
}
process.exitCode=summary.rc;
