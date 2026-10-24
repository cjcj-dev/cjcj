#!/usr/bin/env zx
import fs from 'node:fs/promises';
import {selectBuildJobs} from '../build-resources.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs, promisify} from 'node:util';
import {execFile} from 'node:child_process';
import {sdkPlatform, cleanSdkEnvironment} from './sdk-platform.mjs';
import {command, atomicJson} from './sdk-flow.mjs';
const execute = promisify(execFile);
export async function helloInstall({sdk, work, platform, cjpm = true, source:sourceFile, expected='Hello, Cangjie'}) {
  const native=sdkPlatform(platform), records=[];
  sdk=await fs.realpath(sdk);await fs.mkdir(work,{recursive:true});
  const env=cleanSdkEnvironment(sdk,platform);
  delete env.LD_PRELOAD;delete env.LD_AUDIT;delete env.DYLD_INSERT_LIBRARIES;
  const source=sourceFile?await fs.readFile(sourceFile,'utf8'):'main() { println("Hello, Cangjie") }\n', input=path.join(work,'hello.cj'), binary=path.join(work,'hello'+native.exe);
  await fs.writeFile(input,source);
  try {
    await command([sdk+'/bin/cjc'+native.exe,input,'-o',binary],{cwd:work,env,records});
    async function observed(file) {
      const start=performance.now();let r;
      try {r=await execute(file,[],{cwd:work,env});}
      catch(error) {
        records.push({argv:[file],cwd:work,rc:Number.isInteger(error.code)?error.code:null,signal:error.signal??null,
          stdout:error.stdout,stderr:error.stderr,wall:(performance.now()-start)/1000});throw error;
      }
      records.push({argv:[file],cwd:work,rc:0,signal:null,stdout:r.stdout,stderr:r.stderr,wall:(performance.now()-start)/1000});
      console.log('SDK_HELLO_TARGET_ASSERTION_REACHED '+JSON.stringify({file,stdout:r.stdout}));
      if(r.stdout.trim()!==expected)throw new Error('SDK_HELLO_VALUE');
      return {binary:file,stdout:r.stdout,rc:0};
    }
    const compiled=await observed(binary);let packaged;
    if(cjpm) {
      const project=path.join(work,'cjpm');await fs.mkdir(path.join(project,'src'),{recursive:true});
      await fs.writeFile(path.join(project,'src/main.cj'),'package sdk_hello\n'+source);
      await fs.writeFile(path.join(project,'cjpm.toml'),'[package]\nname = "sdk_hello"\nversion = "1.0.0"\ncjc-version = "1.3.0"\noutput-type = "executable"\nsrc-dir = "src"\ntarget-dir = "target"\n');
      await command([sdk+'/tools/bin/cjpm'+native.exe,'build','-j',String(await selectBuildJobs())],{cwd:project,env,records});
      // cjpm's executable package emits main[.exe] beside its package CJO.
      packaged=await observed(path.join(project,'target/release/bin','main'+native.exe));
    }
    const result={compiled,packaged,commands:records};await atomicJson(path.join(work,'hello-result.json'),result);return result;
  } catch(error) {
    await atomicJson(path.join(work,'hello-result.json'),{error:error.message,rc:error.rc??error.code??1,commands:records});throw error;
  }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{const {values}=parseArgs({options:{sdk:{type:'string'},work:{type:'string'},platform:{type:'string'},source:{type:'string'},expected:{type:'string'},'compiler-only':{type:'boolean'}}});
    if(!values.sdk||!values.work||!values.platform)throw new Error('usage: sdk-hello.mjs --sdk INSTALL --work PRIVATE --platform TUPLE');
    await helloInstall({...values,cjpm:!values['compiler-only']});
  }catch(e){console.error(e.stack);process.exitCode=Number.isInteger(e.rc)?e.rc:Number.isInteger(e.code)?e.code:1;}
}
