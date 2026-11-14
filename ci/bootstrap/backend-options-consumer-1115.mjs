#!/usr/bin/env zx
import fs from 'node:fs';import path from 'node:path';import {spawn} from 'node:child_process';import {createHash} from 'node:crypto';
import {cleanSdkEnvironment} from './sdk-platform.mjs';
const [mode,root,producer]=process.argv.slice(2);
if(!['install','consume'].includes(mode)||![root,producer].every(p=>p&&path.isAbsolute(p)))throw Error('mode root producer');
const source=path.resolve(import.meta.dirname,'../..'),sdk=root+'/install';
const frozen='/root/collect_ten_v2_sol_1113/current-integrated-1114/install';
const app='/root/collect_ten_v2_sol_1113/current-integrated-1114/src-v2/hashmap_count.cj';
const facts=JSON.parse(fs.readFileSync(producer+'/bin/build-inputs.json','utf8'));
fs.mkdirSync(root,{recursive:true});
const identity=p=>({path:p,real:fs.realpathSync(p),sha256:createHash('sha256').update(fs.readFileSync(p)).digest('hex')});
const records=[];const save=()=>fs.writeFileSync(root+'/'+mode+'-commands.json',JSON.stringify(records,null,2));
async function execute(tag,argv,{env=process.env,cwd=root,expected=0}={}) {
 const row={tag,argv,cwd,env:Object.fromEntries(['HOME','PATH','CANGJIE_HOME','LD_LIBRARY_PATH','cjHeapSize'].map(k=>[k,env[k]??null])),start:new Date().toISOString()};records.push(row);save();
 const out=fs.openSync(root+'/'+tag+'.stdout','wx'),err=fs.openSync(root+'/'+tag+'.stderr','wx');
 const p=spawn(argv[0],argv.slice(1),{cwd,env,stdio:['ignore',out,err]});
 const observed=new Map();
 function sample(pid){try {
  const exe=fs.readlinkSync('/proc/'+pid+'/exe'),cmdline=fs.readFileSync('/proc/'+pid+'/cmdline','utf8').split('\0').filter(Boolean);
  if(/(?:cjcj-stage1|\/llc|\/opt|\/ld)$/.test(exe)) {
   const key=pid+':'+exe+':'+JSON.stringify(cmdline);
   observed.set(key,{pid,exe,argv:cmdline,maps:fs.readFileSync('/proc/'+pid+'/maps','utf8').split('\n').filter(l=>/libLLVM|libcangjie-runtime|libboundscheck/.test(l))});
  }
  for(const child of fs.readFileSync('/proc/'+pid+'/task/'+pid+'/children','utf8').trim().split(/\s+/).filter(Boolean))sample(child);
 }catch{}}
 const timer=setInterval(()=>sample(p.pid),10);
 const result=await new Promise((resolve,reject)=>{p.on('error',reject);p.on('exit',(rc,signal)=>resolve({rc,signal}));});
 clearInterval(timer);fs.closeSync(out);fs.closeSync(err);Object.assign(row,result,{end:new Date().toISOString(),observed:[...observed.values()]});save();
 if(result.rc!==expected||result.signal)throw Error('FIRST_FAILURE '+tag+' '+JSON.stringify(result));
 return row;
}
if(mode==='install') {
 const selection=structuredClone(JSON.parse(fs.readFileSync(frozen+'/STAGE-INPUTS.json','utf8')).selection);
 selection.targetComponents.compiler={commit:facts.source,product:producer+'/bin/cjcj-stage1',install:producer,producerFacts:producer+'/bin/build-inputs.json'};
 const config={work:root+'/flow',install:sdk,repos:{},platform:'linux_x86_64',stages:[{id:'install',output:sdk,
  metadata:{platform:'linux_x86_64',compilerFile:'libexec/compiler/cjcj-stage1',compilerCommit:facts.source,selection,visibleOptionsOnly:facts.visibleOptionsOnly,scope:'fixed H1 execution and target inputs; option build configuration regression'},
  copies:[{from:frozen,to:'',exclude:['bin/cjc','bin/cjc-frontend','bin/cjcj-stage1','bin/cjcj-stage1.entry','libexec/compiler','STAGE-INPUTS.json','BUILD-MANIFEST.json','compiler-lineage.json']},
   {from:producer+'/bin/cjcj-stage1',to:'bin/cjcj-stage1'},
   {from:producer+'/bin/build-inputs.json',to:'share/cjcj/backend-options-build-inputs.json'}],
  entries:[{directory:'bin',retain:'libexec/compiler',names:['cjcj-stage1'],libraries:['.compiler-exec/runtime/lib/linux_x86_64_cjnative','.compiler-exec/lib/linux_x86_64_cjnative','.compiler-exec/third_party/llvm/lib','tools/lib']}],
  links:{'bin/cjc':'cjcj-stage1','bin/cjc-frontend':'cjcj-stage1','libexec/compiler/cjc':'cjcj-stage1','libexec/compiler/cjc-frontend':'cjcj-stage1'}}],finalStage:'install'};
 fs.writeFileSync(root+'/install-config.json',JSON.stringify(config,null,2),{flag:'wx'});
 await execute('public-install',[process.execPath,source+'/ci/bootstrap/sdk-flow.mjs','--config',root+'/install-config.json','--no-package']);
} else {
 const env=cleanSdkEnvironment(sdk,'linux_x86_64',{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:root});
 const cg='/sys/fs/cgroup'+fs.readFileSync('/proc/self/cgroup','utf8').trim().split('::').at(-1);
 const resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,fs.readFileSync(cg+'/'+k,'utf8').trim()])),limits=fs.readFileSync('/proc/self/limits','utf8');
 if(resources['memory.swap.max']!=='0'||!limits.match(/Max core file size\s+0\s+0/))throw Error('RESOURCE_CONTRACT');
 const ids=['libexec/compiler/cjcj-stage1','.compiler-exec/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','.compiler-exec/third_party/llvm/lib/libLLVM-15.so','third_party/llvm/lib/libLLVM-15.so','.native-tools/third_party/llvm/bin/llc','runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'];
 fs.writeFileSync(root+'/consumer-inputs.json',JSON.stringify({facts,resources,limits,source:identity(app),identities:ids.map(p=>identity(sdk+'/'+p)),entry:fs.readFileSync(sdk+'/bin/cjcj-stage1.entry','utf8')},null,2));
 await execute('help',[sdk+'/bin/cjc','--help'],{env});
 if(fs.readFileSync(root+'/help.stdout','utf8').includes('--llc-options')===facts.visibleOptionsOnly)throw Error('HELP_VISIBILITY');
 const hello=source+'/ci/bootstrap/fixtures/backend-options-hello.cj';
 await execute('ordinary-compile',[sdk+'/bin/cjc','--static-std','-O2',hello,'-o',root+'/hello'],{env});
 await execute('ordinary-run',[root+'/hello'],{env});
 if(fs.readFileSync(root+'/ordinary-run.stdout','utf8').trim()!=='BACKEND_OPTIONS_ORDINARY_OK')throw Error('ORDINARY_ORACLE');
 if(facts.visibleOptionsOnly) {
  await execute('hidden-rejected',[sdk+'/bin/cjc','--static-std','-O2','--llc-options','-cj-safepoint-poll-max-registers-for-gc-values=0',app,'-o',root+'/rejected'],{env,expected:1});
  if(!fs.readFileSync(root+'/hidden-rejected.stderr','utf8').includes('invalid option'))throw Error('HIDDEN_DIAGNOSTIC');
 } else {
  for(const budget of [null,0,64]) {
   const tag=budget===null?'default-backend':'b'+budget,arm=root+'/'+tag;fs.mkdirSync(arm);
   const argv=[sdk+'/bin/cjc','--static-std','-O2','-V','--save-temps',arm+'/temps',...(budget===null?[]:['--llc-options','-cj-safepoint-poll-max-registers-for-gc-values='+budget]),'--link-option','-Map='+arm+'/link.map',app,'-o',arm+'/hashmap_count'];
   const row=await execute(tag,argv,{env,cwd:arm});
   const llc=row.observed.filter(p=>p.exe.endsWith('/llc'));
   if(!llc.length||budget!==null&&!llc.every(p=>p.argv.includes('-cj-safepoint-poll-max-registers-for-gc-values='+budget)))throw Error('LLC_OBSERVATION '+tag);
   fs.writeFileSync(arm+'/elf.json',JSON.stringify(identity(arm+'/hashmap_count'),null,2));
  }
 }
}
