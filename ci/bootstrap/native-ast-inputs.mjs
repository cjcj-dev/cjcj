// Ordinary native CMake installation facts carried by the existing BUILD-INPUTS.
// No flattening, new receipt, or declaration of SDK/AST qualification.
import fs from 'node:fs/promises';
import path from 'node:path';
import {sdkPlatform} from './sdk-platform.mjs';
import {fileDigest} from './sdk-flow.mjs';

export async function nativeAstInstallation({compiler, build, install, platform, source, commands, cmakeCommand='cmake'}) {
  const native=sdkPlatform(platform);
  const cacheFile=path.join(build,'CMakeCache.txt'),manifestFile=path.join(build,'install_manifest.txt');
  const cache=await fs.readFile(cacheFile,'utf8');
  const value=name=>new RegExp('^'+name+':[^=]+=(.*)$','m').exec(cache)?.[1]?.trim();
  const normalized=file=>native.os==='win32'?path.resolve(file).replaceAll('\\','/').toLowerCase():path.resolve(file);
  const same=(left,right)=>normalized(left)===normalized(right);
  if(!value('CMAKE_HOME_DIRECTORY')||!same(value('CMAKE_HOME_DIRECTORY'),compiler)
    ||!value('CMAKE_INSTALL_PREFIX')||!same(value('CMAKE_INSTALL_PREFIX'),install)
    ||value('CANGJIE_BUILD_STD_SUPPORT')!=='ON')throw Error('NATIVE_AST_CMAKE_CONFIGURATION');
  if(!source||!same(source.root,compiler)||!/^[0-9a-f]{40}$/.test(source.commit))throw Error('NATIVE_AST_SOURCE');
  const succeeded=row=>row?.rc===0&&!row.signal&&!row.error&&!row.cancelled;
  const at=(argv,flag)=>argv[argv.indexOf(flag)+1];
  const cmake=row=>native.os==='win32'
    ? (row.argv?.[0]||'').toLowerCase()===cmakeCommand.toLowerCase()
    : row.argv?.[0]===cmakeCommand;
  const configure=commands.findIndex(row=>cmake(row)&&succeeded(row)&&row.argv.includes('-S')&&row.argv.includes('-B')
    &&same(at(row.argv,'-S'),compiler)&&same(at(row.argv,'-B'),build));
  const built=commands.findIndex((row,i)=>i>configure&&cmake(row)&&succeeded(row)&&row.argv.includes('--build')
    &&same(at(row.argv,'--build'),build)&&row.argv.includes('--target')&&row.argv.includes('cangjie-ast-support'));
  const installed=commands.findIndex((row,i)=>i>built&&cmake(row)&&succeeded(row)&&row.argv.includes('--install')
    &&same(at(row.argv,'--install'),build));
  if(configure<0||built<0||installed<0)throw Error('NATIVE_AST_PRODUCER_COMMANDS');
  const manifest=(await fs.readFile(manifestFile,'utf8')).split(/\r?\n/).filter(Boolean);
  const installedFiles=new Set(manifest.map(normalized));
  const library='lib/'+native.tuple+'/libcangjie-ast-support.a';
  const members=[library,'schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h',
    'third_party/flatbuffers/bin/flatc'+native.exe];
  const files={};
  for(const relative of members){
    const file=path.join(install,relative);
    if(!installedFiles.has(normalized(file)))throw Error('NATIVE_AST_NOT_INSTALLED '+relative);
    const stat=await fs.lstat(file);
    if(!stat.isFile()||!stat.size)throw Error('NATIVE_AST_INSTALL_FILE '+relative);
    files[relative]={bytes:stat.size,sha256:await fileDigest(file)};
  }
  return {source,platform,library,files,
    build:{target:'cangjie-ast-support',configuration:{buildType:value('CMAKE_BUILD_TYPE'),
      generator:value('CMAKE_GENERATOR'),stdSupport:value('CANGJIE_BUILD_STD_SUPPORT')},
      originalLocations:{source:compiler,build,install},
      commandIndexes:{configure,build:built,install:installed}}};
}
