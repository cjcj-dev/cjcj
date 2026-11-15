#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {cleanSdkEnvironment} from './sdk-platform.mjs';
const [mode,out] = process.argv.slice(2);
if(!['dump','build','controls-old','controls-new','consumer'].includes(mode)||!out)throw Error('mode/output');
fs.mkdirSync(out,{recursive:false});
const root='/mnt/cjcj-data/impl_full_sdk_sol_1108/integrated-llvm-1115';
const sdk=root+'/final/install',src=root+'/sources/interop-5985/java';
const source=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const task=path.dirname(out),production=task+'/build-r1';
const json=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const write=(p,v)=>fs.writeFileSync(p,JSON.stringify(v,null,2));
const commit=execFileSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
const cg='/sys/fs/cgroup'+fs.readFileSync('/proc/self/cgroup','utf8').trim().split('::').at(-1);
const resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,fs.readFileSync(cg+'/'+k,'utf8').trim()]));
const limits=fs.readFileSync('/proc/self/limits','utf8');
write(out+'/resources.json',{resources,limits});
if(resources['memory.swap.max']!=='0'||!limits.match(/Max core file size\s+0\s+0/))throw Error('RESOURCE_CONTRACT');
const rows=[];
async function run(label,argv,{cwd=out,env=process.env,required=true}={}) {
 const row={label,argv,cwd,env,start:new Date().toISOString()};rows.push(row);write(out+'/commands.json',rows);
 const stdout=fs.openSync(out+'/'+label+'.stdout','wx'),stderr=fs.openSync(out+'/'+label+'.stderr','wx');
 const child=spawn(argv[0],argv.slice(1),{cwd,env,stdio:['ignore',stdout,stderr]});row.pid=child.pid;
 Object.assign(row,await new Promise((r,j)=>{child.on('error',j);child.on('close',(rc,signal)=>r({rc,signal}));}),{end:new Date().toISOString()});
 fs.closeSync(stdout);fs.closeSync(stderr);write(out+'/commands.json',rows);
 if(required&&(row.rc!==0||row.signal))throw Error(label+' '+JSON.stringify({rc:row.rc,signal:row.signal}));
 return row;
}
if(mode==='build') {
 const sdkProducer=root+'/stage2-target/install',native=root+'/native/install';
 const old=json(root+'/final-inputs.json'),host=old.selection.bootstrapHost.install;
 const env={...process.env,HOME:'/root',PATH:'/mnt/cjcj-nvme/impl_full_sdk_sol_1108/dependencies/node_modules/.bin:/usr/local/bin:/usr/bin:/bin',
  CC:'/usr/bin/cc',CJPM_CONFIG:out+'/cjpm-cache',TMPDIR:out+'/tmp'};
 fs.mkdirSync(env.TMPDIR);fs.mkdirSync(env.CJPM_CONFIG);
 const disks=Object.fromEntries(['/','/mnt/cjcj-nvme'].map(p=>{const x=fs.statfsSync(p);return [p,x.bavail*x.bsize];}));
 write(out+'/inputs.json',{commit,sdkProducer,native,host,disks,forecastGiB:10});
 if(disks['/mnt/cjcj-nvme']<18*2**30)throw Error('DISK_ADMISSION');
 write(out+'/shim.json',{nativeInstall:native,shimSource:source,commit,build:out+'/shim-build',install:out+'/shim-install'});
 await run('shim',[process.execPath,source+'/ci/bootstrap/native-cjdb.mjs',out+'/shim.json','--shim-only'],{env});
 await run('compiler',[process.execPath,source+'/ci/bootstrap/sdk-native-stage.mjs','--kind','compiler','--phase','stage3',
  '--source',source,'--commit',commit,'--sdk',sdkProducer,'--output',out+'/compiler','--platform','linux_x86_64',
  '--std-input',root+'/std-final/install','--target-dir',out+'/target','--host',host,'--shim-install',out+'/shim-install',
  '--jobs','32','--heap','8GB','--zx','/mnt/cjcj-nvme/impl_full_sdk_sol_1108/dependencies/node_modules/.bin/zx'],{env});
 const selection=structuredClone(old.selection);
 selection.targetComponents.compiler={...selection.targetComponents.compiler,repository:source,commit,
  tree:execFileSync('git',['-C',source,'rev-parse','HEAD^{tree}'],{encoding:'utf8'}).trim(),
  shimInstall:out+'/shim-install',install:out+'/compiler',product:out+'/compiler/bin/cjcj-stage1'};
 write(out+'/install-inputs.json',{work:out+'/install-work',install:out+'/install',archive:out+'/unused.tar.gz',selection});
 await run('install',[process.execPath,source+'/build/cli.mjs','install','--inputs',out+'/install-inputs.json','--no-package'],{env});
 await run('public',[process.execPath,source+'/ci/bootstrap/sdk-verify-install.mjs','--sdk',out+'/install','--work',out+'/public','--platform','linux_x86_64','--compiler-only'],{env});
 write(out+'/result.json',{rc:0,commit,install:out+'/install'});
} else if(mode.startsWith('controls-')) {
 const old=mode==='controls-old',selected=old?sdk:production+'/install';
 const env=cleanSdkEnvironment(selected,'linux_x86_64',process.env,selected);
 const libs=old?'/mnt/cjcj-nvme/impl_full_sdk_sol_1108/integrated-llvm-1115/stage3/compiler':production+'/compiler';
 const inputs=libs+'/share/cjcj/cjo',dirs=fs.readdirSync(inputs,{withFileTypes:true}).filter(x=>x.isDirectory()&&x.name!=='compiler_unittest@cjcj').map(x=>inputs+'/'+x.name);
 const archives=dirs.flatMap(d=>fs.readdirSync(d).filter(x=>x.endsWith('.a')).map(x=>d+'/'+x));
 const app=await run('app-compile',[selected+'/bin/cjc',source+'/tests/interop_generic_lift/main.cj','-O2','--dump-chir','-o',out+'/app'],{env,required:false});
 if(app.rc===0)await run('app-run',[out+'/app'],{env,required:false});
 const args=[selected+'/bin/cjc',source+'/tests/interop_generic_lift/chir_contract.cj','-O0','-o',out+'/contract'];
 for(const d of dirs)args.push('--import-path',d,'-L',d);
 args.push('--link-options=--start-group '+archives.join(' ')+' --end-group '+libs+'/share/cjcj/runtime_shim/cjselfhost_llvmshim.o '+libs+'/share/cjcj/runtime_shim/cjc_runtime_config.o -L'+selected+'/third_party/llvm/lib -lLLVM-15 -lstdc++');
 const contract=await run('contract-compile',args,{env,required:false});
 if(contract.rc===0)await run('contract-run',[out+'/contract'],{env,required:false});
 const identity=json(selected+'/STAGE-INPUTS.json');
 write(out+'/result.json',{mode,harnessCommit:commit,compilerCommit:identity.compilerCommit,compilerSha256:identity.compilerSha256,rows});
 if(!old&&rows.some(r=>r.rc!==0||r.signal))process.exitCode=1;
} else if(mode==='consumer') {
 const selected=production+'/install',interop=task+'/interop-source',prefix=out+'/install';
 const env={...process.env,HOME:'/root',LANG:'C.UTF-8',LC_ALL:'C.UTF-8',PYTHONDONTWRITEBYTECODE:'1',CANGJIE_HOME:selected,
  JAVA_HOME:'/mnt/cjcj-nvme/impl_full_sdk_sol_1108/dependencies/java/jdk',TMPDIR:out,
  PATH:selected+'/bin:/mnt/cjcj-nvme/impl_full_sdk_sol_1108/dependencies/java/jdk/bin:/usr/lib/llvm-15/bin:/usr/local/bin:/usr/bin:/bin'};
 for(const k of ['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT','CANGJIE_PATH','cjHeapSize','LIBRARY_PATH','CPATH'])delete env[k];
 const ref=execFileSync('git',['-C',interop,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
 if(ref!=='5985a72fd7b366219a830bf6dd2b4300010d3e37')throw Error('INTEROP_SOURCE');
 await run('target-lib',['/usr/bin/python3','-B','build/build.py','build','-t','release','--target-lib','linux_x86_64_cjnative','--target','x86_64-linux-gnu'],{cwd:interop+'/java',env});
 await run('target-install',['/usr/bin/python3','-B','build/build.py','install','--target','linux_x86_64','--prefix',prefix],{cwd:interop+'/java',env});
 const {prepare}=await import('../cangjie-test/adapt.mjs');
 const adapted=await prepare('/mnt/cjcj-data/impl_full_sdk_sol_1108/mainline-test-1111',out+'/consumer-adapt');
 const config=fs.readFileSync(interop+'/java/test/LLT/interop_test.cfg','utf8').replace('compiler = cjc -j4','compiler = cjc -j4 --import-path='+prefix+'/modules/linux_x86_64_cjnative -L'+prefix+'/lib/linux_x86_64_cjnative -L'+prefix+'/runtime/lib/linux_x86_64_cjnative').replace('${CANGJIE_HOME}/lib/library-loader.jar',prefix+'/lib/library-loader.jar');
 fs.writeFileSync(out+'/interop_test.cfg',config);
 const runEnv={...env,LD_LIBRARY_PATH:[prefix+'/runtime/lib/linux_x86_64_cjnative',selected+'/runtime/lib/linux_x86_64_cjnative',selected+'/lib/linux_x86_64_cjnative',selected+'/tools/lib'].join(':')};
 await run('simple',['/usr/bin/python3','-B',adapted.framework+'/main.py','--test_cfg',out+'/interop_test.cfg','-j','1','--timeout=180','--fail_exit','--keep_temp','--progress=silent','--json_output',out+'/consumer-results.json','--output',out+'/consumer-results.txt','--temp_dir',out+'/consumer-temp','--log_dir',out+'/consumer-logs',interop+'/java/test/LLT/java/1-simple/1-simple.info'],{cwd:adapted.framework,env:runEnv});
 const tests=json(out+'/consumer-results.json').flatMap(x=>x.tests);
 if(tests.length!==1||tests[0].result!=='PASS')throw Error('ORIGINAL_SIMPLE_NOT_PASSED');
 const identity=json(selected+'/STAGE-INPUTS.json');
 write(out+'/result.json',{rc:0,harnessCommit:commit,compilerCommit:identity.compilerCommit,compilerSha256:identity.compilerSha256,ref,selected,prefix,tests});
} else {
const args=['-Woff','unused','-Woff','parser','-Woff','deprecated','--import-path='+src+'/dist',
 '--output-dir='+out,'--int-overflow=wrapping','--disable-reflection','--link-options','-z relro',
 '--link-options','-z now','--target=x86_64-linux-gnu','--strip-all','-O2','--output-type=staticlib',
 '--dump-chir',...fs.readdirSync(src+'/src/interoplib/javalib').filter(x=>x.endsWith('.cj')).sort().map(x=>src+'/src/interoplib/javalib/'+x)];
const env={...process.env,CANGJIE_HOME:sdk,PATH:sdk+'/bin:/usr/local/bin:/usr/bin:/bin',TMPDIR:out};
for(const k of ['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT','CANGJIE_PATH','cjHeapSize'])delete env[k];
const record={mode,argv:[sdk+'/bin/cjc',...args],cwd:out,env,start:new Date().toISOString()};
fs.writeFileSync(out+'/command.json',JSON.stringify(record,null,2));
const stdout=fs.openSync(out+'/stdout','wx'),stderr=fs.openSync(out+'/stderr','wx');
const p=spawn(record.argv[0],args,{cwd:out,env,stdio:['ignore',stdout,stderr]});record.pid=p.pid;
Object.assign(record,await new Promise((r,j)=>{p.on('error',j);p.on('close',(rc,signal)=>r({rc,signal}));}),{end:new Date().toISOString()});
fs.closeSync(stdout);fs.closeSync(stderr);fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
console.log(JSON.stringify({rc:record.rc,signal:record.signal}));process.exitCode=record.rc??1;
}
