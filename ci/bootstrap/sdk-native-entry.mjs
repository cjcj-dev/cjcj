#!/usr/bin/env zx
// Five native runners exercise the same target -> install -> entry -> archive path.
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectBuildJobs} from '../build-resources.mjs';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {buildFlow, atomicJson} from './sdk-flow.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
const execute=promisify(execFile), entry=fileURLToPath(import.meta.url);
export async function nativeEntry(platform, work) {
  const native=sdkPlatform(platform);
  if(process.platform!==native.os||process.arch!==native.arch)throw new Error('NATIVE_ENTRY_RUNNER');
  work=path.resolve(work);
  const source=path.join(work,'source'),install=path.join(work,'install');
  await fs.mkdir(source,{recursive:true});
  await fs.writeFile(path.join(source,'value.cpp'),'extern "C" int native_value() { return 42; }\n');
  await fs.writeFile(path.join(source,'main.cpp'),'#include <iostream>\nextern "C" int native_value(); int main() { std::cout << native_value() << "\\n"; }\n');
  await fs.writeFile(path.join(source,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.16)
project(native_entry_fixture LANGUAGES CXX)
add_library(native_value SHARED value.cpp)
set_target_properties(native_value PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
add_executable(native-read main.cpp)
target_link_libraries(native-read PRIVATE native_value)
install(TARGETS native_value RUNTIME DESTINATION lib LIBRARY DESTINATION lib ARCHIVE DESTINATION lib)
install(TARGETS native-read RUNTIME DESTINATION bin)
`);
  const launcher=process.env.CMAKE_CXX_COMPILER_LAUNCHER;
  const config={work,install,platform,repos:{},finalStage:'native',tools:{launcher},stages:[{id:'native',output:install,commands:[
    {argv:['cmake','-G','Ninja','-S',source,'-B','${build}','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_INSTALL_PREFIX=${build}/native-install',
      ...(launcher?['-DCMAKE_CXX_COMPILER_LAUNCHER='+launcher]:[])]},
    {argv:['cmake','--build','${build}','--parallel',String(await selectBuildJobs())]},
    {argv:['cmake','--install','${build}']}],
    copies:['bin','lib'].map(dir=>({from:'${build}/native-install/'+dir,to:dir})),
    entries:[{directory:'bin',retain:'libexec/native',names:['native-read'+native.exe],libraries:['lib']}]}],
    test:{required:['bin/native-read'+native.exe],commands:[{argv:[process.execPath,entry,'verify','${install}/bin/native-read'+native.exe]}]},
    archiveFormat:native.os==='win32'?'zip':'tar.gz',archive:path.join(work,native.os==='win32'?'sdk.zip':'sdk.tar.gz')};
  await atomicJson(path.join(work,'build-targets.json'),config);
  return buildFlow(config);
}
if(process.argv[1]&&path.resolve(process.argv[1])===entry){
  try {
    if(process.argv[2]==='verify') {
      const result=await execute(process.argv[3],[],{env:{...process.env,LD_LIBRARY_PATH:'/invalid',DYLD_LIBRARY_PATH:'/invalid'}});
      console.log('NATIVE_ENTRY_VALUE_ASSERTION_REACHED '+JSON.stringify({binary:process.argv[3],stdout:result.stdout}));
      if(result.stdout.trim()!=='42')throw new Error('NATIVE_ENTRY_VALUE');
    } else await nativeEntry(process.argv[2],process.argv[3]);
  }catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
