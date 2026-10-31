import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.env.CROSS_TYPE_EVIDENCE;
if(!root||!process.env.ZX)throw Error('CROSS_TYPE_INPUTS');
await fs.mkdir(root,{recursive:true});
// Command fixture: the public entry's source check, configured build type,
// normal install invocation and artifact placement execute. No Windows binary
// or runtime is built, and no fixture result supplies a production tuple.
for(const buildType of ['release','debug','relwithdebinfo'])test('public cross runtime preserves '+buildType+' installation directory',async()=>{
 const dir=root+'/'+buildType,repo=dir+'/repo',bin=dir+'/bin';
 await fs.mkdir(repo+'/runtime',{recursive:true});await fs.mkdir(bin,{recursive:true});
 await fs.writeFile(bin+'/sudo','#!'+process.execPath+'\n// explicit dependency installation command fixture\nprocess.exit(0);\n',{mode:0o755});
 await fs.writeFile(repo+'/runtime/build.py',String.raw`import sys,os,json,pathlib
args=sys.argv[1:];p=pathlib.Path
with open(os.environ['BUILD_TYPE_COMMANDS'],'a') as f:f.write(json.dumps(args)+'\n')
if args[0]=='install':
 root=p(args[args.index('--prefix')+1]);root.mkdir(parents=True,exist_ok=True)
 (root/'libcangjie-runtime.dll').write_text('explicit nonexecutable Windows runtime fixture')
`);
 await fs.mkdir(repo+'/runtime/src');await fs.writeFile(repo+'/runtime/src/windows_x86_64_exports.def','fixture exports\n');
 const commands=[];
 const run=(label,argv,env=process.env)=>{const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',env,timeout:60000,maxBuffer:4*1024**2});commands.push({label,argv,rc:r.status,signal:r.signal});return r;};
 for(const args of [['init','-q'],['add','.'],['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Finite build type fixture']])assert.equal(run('git',['git','-C',repo,...args]).status,0);
 const sha=run('head',['git','-C',repo,'rev-parse','HEAD']).stdout.trim();
 const toolchain=dir+'/toolchain';await fs.mkdir(toolchain);
 const artifact=dir+'/artifacts';
 const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,PLATFORM_CI_ROOT:artifact,RUNTIME_SOURCE:repo,CJCJ_NATIVE_RUNTIME_REF:sha,RUNTIME_TARGET:'windows-x86_64',RUNTIME_TOOLCHAIN:toolchain,
  RUNTIME_BUILD_TYPE:buildType,RUNTIME_VERSION:'1.3.0-fixture',RUNTIME_NATIVE_PAIR:'0',GITHUB_STEP_SUMMARY:'',BUILD_TYPE_COMMANDS:dir+'/children.jsonl',PYTHONDONTWRITEBYTECODE:'1'};
 const r=run('public',[process.env.ZX,path.resolve('ci/platform_matrix/build_runtime.mjs')],env);
 await fs.writeFile(dir+'/public.stdout',r.stdout||'');await fs.writeFile(dir+'/public.stderr',r.stderr||'');await fs.writeFile(dir+'/commands.json',JSON.stringify(commands,null,2));
 assert.equal(r.status,0,r.stderr);
 const calls=(await fs.readFile(env.BUILD_TYPE_COMMANDS,'utf8')).trim().split('\n').map(x=>JSON.parse(x));
 const build=calls.find(x=>x[0]==='build'),install=calls.find(x=>x[0]==='install');
 console.log('CROSS_BUILD_TYPE_INSTALL_ASSERTION_REACHED '+buildType);
 assert.equal(build[build.indexOf('--build-type')+1],buildType);
 const expected=artifact+'/runtime-install/windows_'+buildType+'_x86_64';
 assert.equal(install[install.indexOf('--prefix')+1],expected);
 assert.equal((await fs.readFile(expected+'/SOURCE_SHA','utf8')).trim(),sha);
 await fs.access(expected+'/windows_x86_64_exports.def');
});
