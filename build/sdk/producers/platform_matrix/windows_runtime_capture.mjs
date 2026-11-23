#!/usr/bin/env zx
// Native command/output evidence, not an input certification or build bypass.
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=()=>path.resolve(process.env.WINDOWS_RUNTIME_EVIDENCE||'.platform-ci/windows-native');
const fact=file=>({file:path.resolve(file),bytes:fs.statSync(file).size,sha256:createHash('sha256').update(fs.readFileSync(file)).digest('hex')});
function walk(dir) {
 if(!fs.existsSync(dir))return [];
 return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):e.isFile()?[path.join(dir,e.name)]:[]);
}
function copyFiles(base,destination,select) {
 const files=[];
 for(const file of walk(base).filter(select)) {
  const to=path.join(destination,path.relative(base,file));fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(file,to);
  files.push({...fact(to),source:path.resolve(file)});
 }
 return files;
}
export async function capture(label,argv,options={}) {
 if(!/^[a-z-]+$/.test(label)||!argv.length)throw Error('native command label/argv required');
 const dir=fs.mkdtempSync((fs.mkdirSync(root(),{recursive:true}),path.join(root(),label+'-')));
 const record={label,argv,cwd:options.cwd||process.cwd(),started:new Date().toISOString()};
 if(options.env)record.path=Object.entries(options.env).find(([key])=>key.toLowerCase()==='path')?.[1];
 fs.writeFileSync(path.join(dir,'command.json'),JSON.stringify(record,null,2));
 for(const [i,arg]of argv.entries())if(arg.startsWith('@')&&fs.existsSync(arg.slice(1)))fs.copyFileSync(arg.slice(1),path.join(dir,'response-'+i+'.txt'));
 const stdout=fs.openSync(path.join(dir,'stdout.log'),'w'),stderr=fs.openSync(path.join(dir,'stderr.log'),'w');
 const child=spawn(argv[0],argv.slice(1),{cwd:record.cwd,env:options.env||process.env,stdio:['inherit','pipe','pipe'],windowsHide:true});
 child.stdout.on('data',b=>{fs.writeSync(stdout,b);process.stdout.write(b);});child.stderr.on('data',b=>{fs.writeSync(stderr,b);process.stderr.write(b);});
 const interrupt=()=>child.kill('SIGINT'),terminate=()=>child.kill('SIGTERM');process.on('SIGINT',interrupt);process.on('SIGTERM',terminate);
 const result=await new Promise(resolve=>{let error;child.once('error',e=>{error=String(e);});child.once('close',(rc,signal)=>resolve({rc:error?null:rc,signal,error}));});
 process.removeListener('SIGINT',interrupt);process.removeListener('SIGTERM',terminate);fs.closeSync(stdout);fs.closeSync(stderr);
 Object.assign(record,result,{ended:new Date().toISOString()});
 // Save the link result before CMake executes POST_BUILD (which may fail and
 // cause make to delete the target). Never infer a linker rc from build.py.
 try {
  if(label==='link'&&process.env.WINDOWS_RUNTIME_BUILD_ROOT)record.products=copyFiles(process.env.WINDOWS_RUNTIME_BUILD_ROOT,path.join(dir,'products'),
   f=>/\.(?:dll|a|lib|def)$/i.test(f));
 }catch(error){record.captureError=String(error);}
 fs.writeFileSync(path.join(dir,'command.json'),JSON.stringify(record,null,2));
 return result.rc===0&&record.captureError?1:result.rc??1;
}
function inspect(dir,label,argv) {
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:64*1024**2});
 fs.writeFileSync(path.join(dir,label+'.stdout'),r.stdout||'');fs.writeFileSync(path.join(dir,label+'.stderr'),r.stderr||'');
 const record={argv,rc:r.status,signal:r.signal,error:r.error?.message};fs.writeFileSync(path.join(dir,label+'.json'),JSON.stringify(record));return r;
}
export function collect() {
 const dir=root();fs.mkdirSync(dir,{recursive:true});
 const source=path.resolve(process.env.RUNTIME_SOURCE||'runtime-source'),build=path.join(source,'runtime/CMakebuild');
 const install=path.resolve(process.env.PLATFORM_CI_ROOT||'.platform-ci','runtime-install');
 const sources={};for(const [label,repository]of [['entry',process.cwd()],['runtime',source]])sources[label]=inspect(dir,label+'-commit',['git','-C',repository,'rev-parse','HEAD']).stdout?.trim();
 const manifest={sources,requestedRuntime:process.env.CJCJ_NATIVE_RUNTIME_REF,buildOutcome:process.env.WINDOWS_RUNTIME_BUILD_OUTCOME||'unknown',
  callerAudit:{compiler:process.env.COMPILER_CALLER_REF,llvm:process.env.LLVM_CALLER_REF,role:'source-only audit by runtime owner; not fetched or executed by this producer'},files:[]};
 manifest.files.push(...copyFiles(build,path.join(dir,'build-products'),f=>/\.(?:dll|a|lib|def|rsp)$/i.test(f)||/\b(?:link\.txt|build\.make|CMakeCache\.txt|install_manifest\.txt|compile_commands\.json)$/.test(f)));
 manifest.files.push(...copyFiles(install,path.join(dir,'installed'),()=>true));
 // Preserve the actual configure graph even if planning/COFF reading fails.
 manifest.files.push(...copyFiles(path.join(build,'.cmake/api/v1'),path.join(dir,'cmake-file-api'),()=>true));
 for(const member of ['windows_x86_64_exports.def','windows_export_references.json','windows_retired_exports.def']) {
  const file=path.join(source,'runtime/src',member);if(fs.existsSync(file)){const to=path.join(dir,member);fs.copyFileSync(file,to);manifest.files.push({...fact(to),source:file});}
 }
 const toolchain=process.env.WINDOWS_RUNTIME_TOOLCHAIN||'C:/msys64/mingw64';
 const cacheFile=path.join(build,'CMakeCache.txt');
 const cache=fs.existsSync(cacheFile)?fs.readFileSync(cacheFile,'utf8'):'';
 const cachedReadobj=cache.match(/^WINDOWS_EXPORT_READOBJ:FILEPATH=(.+)$/m)?.[1].trim();
 const readobj=cachedReadobj||path.join(toolchain,'bin/llvm-readobj.exe');
 manifest.readobj={configured:cachedReadobj??null,selected:readobj};
 for(const [name,args]of [['clang',['--version']],['ld.lld',['--version']],['llvm-readobj',['--version']],['cmake',['--version']],['python3',['--version']],['objdump',['--version']]])
  inspect(dir,'tool-'+name,[name==='llvm-readobj'?readobj:path.join(toolchain,'bin',name+'.exe'),...args]);
 inspect(dir,'pacman-packages',['C:/msys64/usr/bin/pacman.exe','-Q']);
 const dlls=walk(dir).filter(f=>/\.dll$/i.test(f)),objdump=process.env.OBJDUMP||path.join(toolchain,'bin/objdump.exe');
 manifest.dlls=[];
 for(const [i,dll]of dlls.entries()) {
  const result=inspect(dir,'pe-'+i,[objdump,'-p',dll]);
  const coff=inspect(dir,'coff-'+i,[readobj,'--coff-exports',dll]);
  const imports=[...(result.stdout||'').matchAll(/^\s*DLL Name:\s*(\S+)/gim)].map(m=>m[1]);
  const row={...fact(dll),objdumpRc:result.status,readobjRc:coff.status,imports,dependencies:[]};
  for(const name of imports) {
   const found=[path.join(path.dirname(dll),name),...walk(build).filter(f=>path.basename(f).toLowerCase()===name.toLowerCase()),path.join(toolchain,'bin',name)]
    .find(f=>fs.existsSync(f));
   if(found){const to=path.join(dir,'dependencies',String(i),name);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(found,to);row.dependencies.push({...fact(to),source:found});}
   else {
    const system=path.join(process.env.SystemRoot||'C:/Windows','System32',name);
    row.dependencies.push(fs.existsSync(system)?{...fact(system),kind:'Windows system dependency; not redistributed'}:{name,status:'unresolved'});
   }
  }
  manifest.dlls.push(row);
 }
 // The runtime owner consumes actual selected Windows translation units, not
 // source-only Unix definitions or a second compilation. Capture even when a
 // later registration check rejected the successfully linked runtime.
 const linked=manifest.files.some(f=>f.file.endsWith('windows_x86_64_exports.raw.def'))&&dlls.length>0;
 manifest.runtimeDefinitions={status:'NOT_RUN',reason:'normal runtime link not reached'};
 if(linked&&cachedReadobj&&path.isAbsolute(cachedReadobj)&&!cachedReadobj.endsWith('-NOTFOUND')) {
  const output=path.join(dir,'runtime-definitions.json');
  const result=inspect(dir,'runtime-definitions-command',[process.execPath,
   path.join(source,'runtime/build/capture_windows_runtime_definitions.mjs'),build,
   path.join(source,'runtime/src'),sources.runtime||'',output,readobj]);
  manifest.runtimeDefinitions={rc:result.status,signal:result.signal,error:result.error?.message,
   runtime:sources.runtime,output,produced:fs.existsSync(output)};
  // The runtime producer owns selection. Retain exactly its selected objects,
  // including Heap/archive inputs, without an independent symbol allow-list.
  const planFile=output+'.commands/link-object-plan.json';
  try {
   const plan=JSON.parse(fs.readFileSync(planFile,'utf8'));
   if(!Array.isArray(plan.objects)||!plan.objects.length)throw Error('runtime link-object plan has no selected objects');
   const failures=[];manifest.runtimeDefinitions.selectedObjects=[];
   for(const row of plan.objects)try {
    const relative=path.relative(build,row.object);
    if(!relative||relative==='..'||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw Error('selected object outside normal build: '+row.object);
    const target=path.join(dir,'selected-objects',relative);fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(row.object,target);
    manifest.runtimeDefinitions.selectedObjects.push({...fact(target),source:row.object,target:row.target});
   }catch(error){failures.push(String(error));}
   if(failures.length)throw Error(failures.join('\n'));
  }catch(error){manifest.runtimeDefinitions.retentionError=String(error);}
 } else if(linked)manifest.runtimeDefinitions={status:'NOT_RUN',error:'normal CMake WINDOWS_EXPORT_READOBJ absolute path is missing'};
 fs.writeFileSync(path.join(dir,'products.json'),JSON.stringify(manifest,null,2));
 if(linked&&(manifest.runtimeDefinitions.rc!==0||!manifest.runtimeDefinitions.produced||manifest.runtimeDefinitions.retentionError))throw Error('native Windows runtime definition capture failed; original command evidence retained');
 if(manifest.buildOutcome==='success'&&(!manifest.files.some(f=>f.file.endsWith('windows_x86_64_exports.raw.def'))||!dlls.length))throw Error('successful native build missing raw/DLL evidence');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  if(process.argv[2]==='run'){if(process.argv[4]!=='--')throw Error('run LABEL -- COMMAND required');process.exitCode=await capture(process.argv[3],process.argv.slice(5));}
  else if(process.argv[2]==='collect')collect();else throw Error('run or collect required');
 }catch(error){console.error(error.stack);process.exitCode=1;}
}
