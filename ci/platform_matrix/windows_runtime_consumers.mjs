#!/usr/bin/env zx
// Compile the runtime owner's native consumers against this installation.
// CMake's selected Exception compile group supplies product headers/defines;
// no Linux toolchain or source-only model substitutes for these Windows runs.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {capture} from './windows_runtime_capture.mjs';

const read=file=>JSON.parse(fs.readFileSync(file,'utf8'));
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):e.isFile()?[path.join(dir,e.name)]:[]);
function one(items,label) {
 if(items.length!==1)throw Error(`${label}: expected one, found ${items.length}`);
 return items[0];
}
function consumerInputs(runtime,build,output) {
 const reply=path.join(build,'.cmake/api/v1/reply');
 const indexes=fs.readdirSync(reply).filter(n=>/^index-.*\.json$/.test(n)).sort();
 if(!indexes.length)throw Error('normal runtime CMake file-api index missing');
 const index=read(path.join(reply,indexes.at(-1)));
 const model=read(path.join(reply,index.reply['client-runtime-exports']['codemodel-v2'].jsonFile));
 if(path.resolve(model.paths.build)!==build||model.configurations.length!==1)throw Error('expected matching single-config runtime build');
 const matches=[];
 for(const item of model.configurations[0].targets) {
  const target=read(path.join(reply,item.jsonFile));
  for(const source of target.sources||[])if(source.path.replaceAll('\\','/').endsWith('/WindowsExceptionTransfer.cpp'))
   matches.push({target:target.name,group:target.compileGroups[source.compileGroupIndex],source:source.path});
 }
 const selected=one(matches,'production WindowsExceptionTransfer compile group');
 if(selected.group.language!=='CXX')throw Error('expected CXX compile group');
 const cache=fs.readFileSync(path.join(build,'CMakeCache.txt'),'utf8');
 const compiler=cache.match(/^CMAKE_CXX_COMPILER:(?:FILEPATH|STRING)=(.+)$/m)?.[1].trim();
 if(!compiler||!path.isAbsolute(compiler)||!fs.existsSync(compiler))throw Error('normal configured CXX compiler missing');
 const flags=path.join(output,'product-compile-flags.rsp');
 fs.writeFileSync(flags,(selected.group.compileCommandFragments||[]).map(x=>x.fragment).join('\n')+'\n');
 const args=['@'+flags];
 for(const {define} of selected.group.defines||[])args.push('-D'+define);
 for(const include of selected.group.includes||[])args.push(include.isSystem?'-isystem':'-I',path.resolve(model.paths.source,include.path));
 // Test-only includes and language mode; retain actual product configuration.
 args.push('-I',path.join(runtime,'tests'),'-I',path.join(runtime,'tests/gc_unit'),'-std=gnu++17','-fexceptions','-fno-rtti');
 fs.writeFileSync(path.join(output,'compiler-inputs.json'),JSON.stringify({compiler,build,selected,args},null,2));
 return {compiler,args};
}

export async function runConsumers(install,phase) {
 if(process.platform!=='win32')throw Error('native installed consumers require Windows');
 if(!['installed','unpacked'].includes(phase))throw Error('phase must be installed or unpacked');
 install=path.resolve(install);
 const root=path.resolve(process.env.PLATFORM_CI_ROOT||'.platform-ci');
 const runtime=path.resolve(process.env.RUNTIME_SOURCE||'runtime-source','runtime');
 const build=path.join(runtime,'CMakebuild');
 const base=path.join(root,'windows-consumers');fs.mkdirSync(base,{recursive:true});
 const output=fs.mkdtempSync(path.join(base,phase+'-')); // no stale EXE/DLL reuse
 const files=walk(install);
 const dll=one(files.filter(f=>path.basename(f).toLowerCase()==='libcangjie-runtime.dll'),'installed runtime DLL');
 const runtimeImport=one(files.filter(f=>/^libcangjie-runtime\.dll\.a$/i.test(path.basename(f))),'installed runtime import library');
 const boundsImport=one(files.filter(f=>/^libboundscheck\.dll\.a$/i.test(path.basename(f))),'installed bounds import library');
 const dependencyDirs=[...new Set(files.filter(f=>/\.dll$/i.test(f)).map(f=>path.dirname(f)))];
 const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>key.toLowerCase()!=='path'));
 const windows=process.env.SystemRoot||'C:/Windows';
 env.PATH=[...dependencyDirs,path.join(windows,'System32'),windows].join(';');
 const {compiler,args}=consumerInputs(runtime,build,output);
 fs.writeFileSync(path.join(output,'inputs.json'),JSON.stringify({phase,install,runtime,dll,runtimeImport,boundsImport,dependencyDirs,runPath:env.PATH},null,2));
 const rows=[];
 async function command(label,argv,options={}) {
  const rc=await capture('consumer-'+label,argv,{cwd:output,...options});
  rows.push({label,argv,rc});fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(rows,null,2));
  return rc;
 }
 let rc=await command('compiler-version',[compiler,'--version']);if(rc)return rc;
 for(const [name,sources]of [
  ['unwind',['windows_n2c_os_unwind.cpp']],
  ['return',['windows_exception_return_os.cpp']],
  ['frames',['windows_exception_frames.cpp','gc_unit/test_unwind_regressions.cpp']],
 ]) {
  const objects=[];
  for(const [i,source]of sources.entries()) {
   const object=path.join(output,`${name}-${i}.obj`);objects.push(object);
   rc=await command('compile',[compiler,...args,'-c',path.join(runtime,'tests',source),'-o',object]);if(rc)return rc;
   if(name==='frames') {
    rc=await command('imports',[process.execPath,path.join(runtime,'tests/windows_exception_imports.mjs'),object,i===0?'entry':'gc']);if(rc)return rc;
   }
  }
  const exe=path.join(output,name+'.exe');
  rc=await command('link',[compiler,...args,'-fuse-ld=lld','-static',...objects,
   ...(name==='frames'?[runtimeImport,boundsImport]:[]),'-lntdll','-o',exe]);if(rc)return rc;
  rc=await command('run',[exe,dll],{env});if(rc)return rc;
 }
 return 0;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const [install=path.resolve(process.env.PLATFORM_CI_ROOT||'.platform-ci','runtime-install'),phase='installed']=process.argv.slice(2);
  process.exitCode=await runConsumers(install,phase);
 }catch(error){console.error(error.stack);process.exitCode=1;}
}
