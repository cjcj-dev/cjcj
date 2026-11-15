#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {cleanSdkEnvironment} from './sdk-platform.mjs';
const [mode,out] = process.argv.slice(2);
if(!['old','new','build'].includes(mode)||!out)throw Error('mode/output');
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
 } else {
 const selected=mode==='old'?sdk:production+'/install';
 const env=cleanSdkEnvironment(selected,'linux_x86_64',process.env,selected);
 const cases=JSON.parse(fs.readFileSync(source+'/tests/interface_record_gc_abi/original-cases.json'));
 const utils=root+'/cangjie-test-conformance/Conformance/work/bin/utils';
 for(const item of cases){
  const work=out+'/'+item.name;fs.mkdirSync(work);fs.mkdirSync(work+'/temps');
  const argv=[selected+'/bin/cjc','--jobs=1','--import-path',item.importPath,item.test_path,'-L',utils,'-lutils_utils','--import-path',utils,'--output-dir',work,'-o',item.name,'--save-temps',work+'/temps','--dump-chir'];
  const result=await run(item.name+'-compile',argv,{cwd:work,env,required:false});
  if(result.rc===0)await run(item.name+'-run',[work+'/'+item.name],{cwd:work,env,required:false});
 }
 write(out+'/result.json',{mode,commit,rows});
 if(mode==='new'&&rows.some(r=>r.rc!==0||r.signal))process.exitCode=1;
}
