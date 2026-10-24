// Finite native compiler adapter fixture: C produces 42, never a C3 compiler.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const parent=process.env.SDK_NATIVE_INSTALLED_TEST_ROOT;
if(!parent)throw new Error('SDK_NATIVE_INSTALLED_TEST_ROOT required');
test('native compiler build/install, source restoration and repeated publication use the public flow',async()=>{
 const root=parent+'/compiler-adapter',source=root+'/source',sdk=root+'/sdk',output=root+'/output';
 const write=async(file,body,mode)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,body);if(mode)await fs.chmod(file,mode);};
 const run=(exe,args,extra={})=>{const p=spawnSync(exe,args,{encoding:'utf8',maxBuffer:16*1024*1024,...extra});return p;};
 await write(source+'/cjpm.toml','compile-option = "-O1"\n');
 await write(source+'/.gitignore','target/\nruntime_shim/*.o\n');
 await write(source+'/runtime_shim/build_shim.mjs',`import fs from 'node:fs/promises';await fs.writeFile('runtime_shim/cjselfhost_llvmshim.o','fixture shim');await fs.writeFile('runtime_shim/cjc_runtime_config.o','fixture config');`);
 await write(source+'/main.c','#include <stdio.h>\nint main(void){puts("42");return 0;}\n');
 const compile=run('cc',[source+'/main.c','-o',root+'/parent']);assert.equal(compile.status,0,compile.stderr);
 await write(sdk+'/STAGE-INPUTS.json',JSON.stringify({compilerFile:'bin/parent'}));await fs.mkdir(sdk+'/bin',{recursive:true});await fs.copyFile(root+'/parent',sdk+'/bin/parent');
 await write(sdk+'/PROVENANCE.txt','finite C fixture; not production std\n');await write(sdk+'/lib/linux_x86_64_cjnative/libcangjie-std-core.a','finite fixture identity\n');
 await write(sdk+'/tools/bin/cjpm',`#!${process.execPath}\nconst fs=require('fs'),cp=require('child_process');fs.appendFileSync(${JSON.stringify(root+'/calls')},'build\\n');if(process.env.SDK_COMPILER_FIXTURE_FAIL)process.exit(7);fs.mkdirSync('target/release/bin',{recursive:true});cp.execFileSync('cc',['main.c','-o','target/release/bin/cjcj::cjc']);`,0o755);
 for(const args of [['init','-q',source],['-C',source,'add','.'],['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: finite native compiler adapter']]){const p=run('git',args);assert.equal(p.status,0,p.stderr);}
 const commit=run('git',['-C',source,'rev-parse','HEAD']).stdout.trim(),tree=run('git',['-C',source,'rev-parse','HEAD^{tree}']).stdout.trim();
 const config={work:root+'/work',install:output,repos:{compiler:{root:source,commit,tree}},stages:[{id:'compiler',output,commands:[{argv:[process.execPath,new URL('./sdk-native-stage.mjs',import.meta.url).pathname,'--kind','compiler','--source','${repo.compiler}','--sdk',sdk,'--runtime',sdk,'--output','${output}','--platform','linux_x86_64','--commit',commit,'--phase','stage2','--zx',process.execPath]}]}],finalStage:'compiler',test:{commands:[{argv:['${install}/bin/cjcj-stage1']}]}};
 const file=root+'/targets.json';await write(file,JSON.stringify(config));
 const results=[];
 for(const [name,args,env,expected] of [['first',[],{},0],['failed',['--from','compiler'],{SDK_COMPILER_FIXTURE_FAIL:'1'},7],['restored',['--from','compiler'],{},0]]){
  const p=run(process.execPath,[new URL('./sdk-build.mjs',import.meta.url).pathname,'--config',file,'--no-package',...args],{env:{...process.env,...env}});
  await write(root+'/'+name+'.stdout',p.stdout||'');await write(root+'/'+name+'.stderr',p.stderr||'');results.push({name,rc:p.status,signal:p.signal});await write(root+'/results.json',JSON.stringify(results));
  assert.equal(p.status,expected,p.stderr);assert.equal(await fs.readFile(source+'/cjpm.toml','utf8'),'compile-option = "-O1"\n');
  assert.equal(run('git',['-C',source,'status','--porcelain','--untracked-files=no']).stdout,'');
  if(expected===0){const value=run(output+'/bin/cjcj-stage1',[]);assert.equal(value.status,0);assert.equal(value.stdout.trim(),'42');}
 }
 assert.equal((await fs.readFile(root+'/calls','utf8')).trim().split('\n').length,3);
 assert((await fs.readdir(root)).some(n=>n.startsWith('output.previous-')));
});
