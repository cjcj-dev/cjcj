import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {runMsysScript} from './windows_runtime_shell.mjs';
const evidence=process.env.WINDOWS_SHELL_EVIDENCE;
if(!evidence)throw Error('WINDOWS_SHELL_EVIDENCE required');
fs.mkdirSync(evidence,{recursive:true});
test('ordinary shell preserves its own status',async()=>{
 const results=[];
 for(const rc of [0,37]){
  const result=await runMsysScript('/bin/bash','exit '+rc);results.push(result);
  assert.equal(result.exitCode,rc);assert.equal(result.signal,null);assert.equal(result.error,undefined);
 }
 fs.writeFileSync(path.join(evidence,'ordinary-shell-results.json'),JSON.stringify(results));
});
// Linux command fixture executes the public Windows branch and real Bash/stdin
// parser, capture wrapper and build/install sequencing. No PE/runtime is built.
for(const fail of [false,true])test('public Windows shell '+(fail?'preserves build failure':'preserves special paths'),()=>{
 const root=fs.mkdtempSync(path.join(evidence,fail?'failure-':'normal-'));
 // A Linux PATH component cannot contain ':'; retain the Windows backslash
 // sequences here while real drive-letter conversion belongs to MSYS cygpath.
 const special=" node's C\\hosted\\node $(should-not-run) (space)";
 const source=path.join(root,'runtime'+special),toolchain=path.join(root,'tools'+special,'mingw64'),bin=path.join(toolchain,'bin'),out=path.join(root,'output'+special);
 const put=(file,text,mode)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text,{mode});};
 const exe=(file,text)=>put(file,'#!'+process.execPath+'\n'+text,0o755);
 put(source+'/runtime/build.py','explicit command fixture, not runtime source');
 put(source+'/runtime/src/windows_x86_64_exports.def','fixture definition');
 const run=(argv,env=process.env)=>spawnSync(argv[0],argv.slice(1),{env,encoding:'utf8',timeout:30000,maxBuffer:4*1024**2});
 for(const args of [['init','-q'],['add','.'],['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Explicit command fixture']])assert.equal(run(['git','-C',source,...args]).status,0);
 const ref=run(['git','-C',source,'rev-parse','HEAD']).stdout.trim();
 exe(bin+'/cygpath',String.raw`process.stdout.write(process.argv.at(-1)+'\n');`);
 for(const name of ['clang','ninja','llvm-readobj','cmake'])exe(bin+'/'+name,`console.log(${JSON.stringify(name+' explicit command fixture')});`);
 exe(bin+'/python3',String.raw`const fs=require('node:fs'),path=require('node:path');const args=process.argv.slice(2);fs.appendFileSync(process.env.SHELL_CALLS,JSON.stringify({args,cwd:process.cwd()})+'\n');if(args[1]==='build')process.exit(Number(process.env.FIXTURE_BUILD_RC));if(args[1]==='install'){const p=args[args.indexOf('--prefix')+1];fs.mkdirSync(p,{recursive:true});fs.writeFileSync(path.join(p,'libcangjie-runtime.dll'),'non-PE explicit command fixture');}`);
 const bash=root+'/msys bash.mjs';
 exe(bash,`import fs from 'node:fs';import {spawn} from 'node:child_process';fs.writeFileSync(process.env.SHELL_LAUNCH,JSON.stringify({argv:process.argv.slice(2),env:Object.fromEntries(['MSYSTEM','MSYS2_PATH_TYPE','CHERE_INVOKING'].map(k=>[k,process.env[k]]))}));const p=spawn('/bin/bash',['--noprofile','--norc','-s'],{stdio:'inherit'});p.on('close',rc=>process.exit(rc));`);
 const hooks=root+'/host-fixture.mjs';
 put(hooks,`import {registerHooks} from 'node:module';
registerHooks({load(url,context,next){
 if(url.endsWith('/platform_matrix/pick_cc.mjs'))return {format:'module',shortCircuit:true,source:'export async function pickWindowsCC(){return process.env.SHELL_CC;}'};
 if(url.endsWith('/platform_matrix/common.mjs'))return {format:'module',shortCircuit:true,source:\`import {spawnSync} from 'node:child_process'; Object.defineProperty(process,'platform',{value:'win32'}); export async function printCommonVersions(){} export const toCommandPath=x=>x; export function stageBegin(){const tag=async(strings,...values)=>{let argv;if(strings[0].startsWith('git -C '))argv=['git','-C',values[0],'rev-parse',values[1]];else if(strings[0]==='file ')argv=['file',values[0]];else throw Error('unexpected fixture command');const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8'});if(r.status)throw Error(r.stderr);return {stdout:r.stdout,exitCode:r.status};};globalThis.$=(first,...values)=>Array.isArray(first)?tag(first,...values):tag;return {root:process.env.PLATFORM_CI_ROOT};}\`};
 return next(url,context);
}});`);
 const env={...process.env,PATH:bin+':'+process.env.PATH,WINDOWS_SHELL_EVIDENCE:evidence,
  MSYS2_BASH:bash,SHELL_CC:bin+'/clang.exe',SHELL_CALLS:root+'/calls.jsonl',SHELL_LAUNCH:root+'/launch.json',FIXTURE_BUILD_RC:fail?'37':'0',
  PLATFORM_CI_ROOT:out,RUNTIME_SOURCE:source,RUNTIME_REF:ref,RUNTIME_TARGET:'windows-x86_64',RUNTIME_BUILD_TYPE:'release',RUNTIME_VERSION:"1.3.0-fixture's",RUNTIME_BUILD_JOBS:'4',RUNTIME_NATIVE_PAIR:'0',RUNNER_TEMP:root+'/temporary'+special};
 const argv=[process.execPath,'--import',hooks,path.resolve('ci/platform_matrix/build_runtime.mjs')];
 const result=run(argv,env);put(root+'/entry.stdout',result.stdout||'');put(root+'/entry.stderr',result.stderr||'');put(root+'/entry-command.json',JSON.stringify({argv,rc:result.status,signal:result.signal,error:result.error?.message}));
 const records=fs.existsSync(env.SHELL_CALLS)?fs.readFileSync(env.SHELL_CALLS,'utf8').trim().split('\n').map(JSON.parse):[];
 console.log('WINDOWS_SHELL_BUILD_ARGS_ASSERT_REACHED '+(fail?'failure':'normal'));
 assert.ok(records.length,'public Windows entry must reach build.py with literal paths');
 const build=records[0];assert.equal(build.cwd,source+'/runtime');assert.equal(build.args[1],'build');
 assert.equal(build.args[build.args.indexOf('--target-toolchain')+1],toolchain);
 assert.equal(build.args[build.args.indexOf('--prefix')+1],env.RUNNER_TEMP);
 assert.equal(build.args[build.args.indexOf('-v')+1],env.RUNTIME_VERSION);
 console.log('WINDOWS_SHELL_JOBS_ASSERT_REACHED');
 assert.equal(build.args[build.args.indexOf('--jobs')+1],'4','public Windows script must preserve explicit build jobs');
 assert.deepEqual(JSON.parse(fs.readFileSync(env.SHELL_LAUNCH)),{argv:['--login','-s'],env:{MSYSTEM:'MINGW64',MSYS2_PATH_TYPE:'inherit',CHERE_INVOKING:'1'}});
 const command=JSON.parse(fs.readFileSync(out+'/windows-native/runtime-native-command.json'));
 assert.equal(command.rc,fail?37:0);assert.equal(command.signal,null);
 const captures=fs.readdirSync(out+'/windows-native').filter(x=>x.startsWith('build-')).map(x=>JSON.parse(fs.readFileSync(out+'/windows-native/'+x+'/command.json')));
 assert.equal(captures.length,1);assert.equal(captures[0].rc,fail?37:0);
 if(fail){assert.equal(result.status,1);assert.equal(records.length,1,'failed build must not run install');assert.ok(!fs.existsSync(out+'/runtime-install/windows_release_x86_64/SOURCE_SHA'));}
 else {assert.equal(result.status,0,result.stderr);assert.equal(records.length,2);assert.equal(records[1].args[1],'install');assert.equal(records[1].args.at(-1),out+'/runtime-install/windows_release_x86_64');assert.equal(fs.readFileSync(out+'/runtime-install/windows_release_x86_64/SOURCE_SHA','utf8').trim(),ref);}
});
