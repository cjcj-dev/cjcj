#!/usr/bin/env zx
// Configure the real fixed std CMake producer graph. No target compiler is run
// and no Windows/Mach-O/stdlib payload is fabricated by this finite contract gate.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {stdInstallFiles} from './sdk-platform.mjs';
const work=process.env.SDK_STD_SHAPE_WORK,module=process.env.SDK_STD_CMAKE_MODULE;
if(!work||!module)throw new Error('SDK_STD_SHAPE_WORK/SDK_STD_CMAKE_MODULE required');
await fs.mkdir(work,{recursive:true});
const results=[];
for(const [platform,system,processor]of [
 ['linux_x86_64','Linux','x86_64'],['linux_aarch64','Linux','aarch64'],
 ['darwin_x86_64','Darwin','x86_64'],['darwin_aarch64','Darwin','arm64'],
 ['windows_x86_64','Windows','x86_64']].filter(row=>!process.env.SDK_STD_SHAPE_PLATFORM||row[0]===process.env.SDK_STD_SHAPE_PLATFORM)){
 const root=path.join(work,platform),source=path.join(root,'source'),build=path.join(root,'build');
 await fs.mkdir(source+'/cj',{recursive:true});
 await fs.writeFile(source+'/cj/core.cj','package std.core\n'); // Configure input only, never compiled.
 await fs.writeFile(source+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(StdInstallGraph NONE)
set(CANGJIE_CODEGEN_CJNATIVE_BACKEND ON)
set(CANGJIE_SANITIZER_SUPPORT_ENABLED OFF)
set(CANGJIE_SHARED_JOBSERVER OFF)
set(IOS OFF)
set(DARWIN OFF)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(DARWIN ON)
endif()
set(TARGET_TRIPLE_DIRECTORY_PREFIX "${platform}")
include("${module.replaceAll('\\','/')}")
add_cangjie_library(stdcore IS_STDLIB IS_CJNATIVE_BACKEND IS_PACKAGE MODULE_NAME std PACKAGE_NAME core SOURCE_DIR "\${CMAKE_CURRENT_SOURCE_DIR}/cj")
if(TARGET stdcore_bc)
  file(WRITE "\${CMAKE_BINARY_DIR}/has-bc" "yes")
else()
  file(WRITE "\${CMAKE_BINARY_DIR}/has-bc" "no")
endif()
`);
 const argv=['cmake','-S',source,'-B',build,'-G','Ninja','-DCMAKE_BUILD_TYPE=RelWithDebInfo',
  '-DCMAKE_SYSTEM_NAME='+system,'-DCMAKE_SYSTEM_PROCESSOR='+processor];
 const log=await fs.open(root+'/configure.log','wx'),started=new Date().toISOString();
 const child=spawn(argv[0],argv.slice(1),{stdio:['ignore',log.fd,log.fd]});
 const result=await new Promise(resolve=>{child.once('error',error=>resolve({rc:null,error:error.message}));child.once('close',(rc,signal)=>resolve({rc,signal}));});
 await log.close();results.push({platform,argv,started,ended:new Date().toISOString(),...result});
 await fs.writeFile(work+'/commands.json',JSON.stringify(results,null,2));assert.equal(result.rc,0,root+'/configure.log');
 const install=await fs.readFile(build+'/cmake_install.cmake','utf8'),fromProducer=[];
 for(const row of install.matchAll(/file\(INSTALL DESTINATION "\$\{CMAKE_INSTALL_PREFIX\}\/([^"]+)" TYPE FILE FILES\s+([\s\S]*?)\)/g)){
  for(const file of row[2].matchAll(/"([^"]+\.(?:cjo|bc))"/g))fromProducer.push(row[1]+'/'+path.basename(file[1]));
 }
 assert(fromProducer.some(x=>x.endsWith('/std.core.cjo')),'actual producer install graph must be reached');
 const consumer=stdInstallFiles(platform),moduleFiles=consumer.filter(x=>/\.(cjo|bc)$/.test(x));
 const observed={platform,fromProducer:fromProducer.sort(),fromConsumer:moduleFiles.sort(),allRequired:consumer,
  ltoTarget:(await fs.readFile(build+'/has-bc','utf8'))==='yes',scope:'configuration graph only; native production NOT_RUN'};
 await fs.writeFile(root+'/contract.json',JSON.stringify(observed,null,2));
 console.log('STD_INSTALL_PRODUCER_CONTRACT_REACHED '+JSON.stringify(observed));
 assert.deepEqual(observed.fromConsumer,observed.fromProducer,'SDK shape must consume the actual std installation graph: '+platform);
 assert.equal(observed.ltoTarget,consumer.some(x=>x.endsWith('.bc')),'LTO target and required bitcode must agree');
}
