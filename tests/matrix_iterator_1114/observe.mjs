#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root='/mnt/cjcj-nvme/backport_compiler_astra_1112/matrix-current-1114';
const sdk='/root/collect_ten_v2_sol_1113/current-main-1114/install';
const out=root+'/ir-attempt';fs.mkdirSync(out);for(const x of ['home','tmp','temps'])fs.mkdirSync(out+'/'+x);
const record={start:new Date().toISOString(),steps:[],claims:[],source:process.argv[1],sdk};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const hash=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const original=JSON.parse(fs.readFileSync('/root/collect_ten_v2_sol_1113/current-main-1114/apps/ours/matrix_multiply/run.json'));
const env={...process.env,...original.env,HOME:out+'/home',TMPDIR:out+'/tmp'};
async function run(name,argv){const fd=fs.openSync(out+'/'+name+'.log','wx');const row={name,argv,cwd:out,start:new Date().toISOString()};record.steps.push(row);save();const p=spawn(argv[0],argv.slice(1),{cwd:out,env,stdio:['ignore',fd,fd]});const seen=new Map();const sample=()=>{const todo=[p.pid];for(let n=0;n<todo.length;n++){const pid=todo[n];try{const exe=fs.readlinkSync(`/proc/${pid}/exe`);const cmd=fs.readFileSync(`/proc/${pid}/cmdline`,'utf8').split('\0');const maps=fs.readFileSync(`/proc/${pid}/maps`,'utf8').split('\n').filter(x=>x.includes('.so')).map(x=>x.trim().split(/\s+/).at(-1));seen.set(pid,{pid,exe,cmd,maps:[...new Set(maps)]});for(const task of fs.readdirSync(`/proc/${pid}/task`)){const children=fs.readFileSync(`/proc/${pid}/task/${task}/children`,'utf8').trim().split(/\s+/).filter(Boolean).map(Number);for(const c of children)if(!todo.includes(c))todo.push(c);}}catch{}}};const timer=setInterval(sample,10);Object.assign(row,await new Promise((res,rej)=>{p.on('error',rej);p.on('exit',(rc,signal)=>res({rc,signal}));}),{end:new Date().toISOString(),processes:[...seen.values()]});clearInterval(timer);fs.closeSync(fd);save();if(row.rc!==0||row.signal)throw Error(name+' failed');}
let rc=1;const acquired=[];
try{
 for(const [suffix,cpus]of [['cpu','64-71'],['smt','160-167']]){const key='backport_compiler_astra_1112-matrix-ir-'+suffix;const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'single frozen matrix compile and IR inspection'],{encoding:'utf8',env:{...process.env,MEASURE_OWNER_PID:String(process.pid)}});record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('claim');acquired.push(key);}
 const cg='/sys/fs/cgroup'+fs.readFileSync('/proc/self/cgroup','utf8').trim().split('::').at(-1);record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max','cpu.max'].map(x=>[x,fs.readFileSync(cg+'/'+x,'utf8').trim()]));record.limits=fs.readFileSync('/proc/self/limits','utf8');record.env=env;record.topology=fs.readFileSync('/sys/devices/system/cpu/cpu64/topology/thread_siblings_list','utf8');save();if(record.resources['memory.swap.max']!=='0'||!record.limits.match(/Max core file size\s+0\s+0/))throw Error('resources');
 record.identities={};for(const x of ['libexec/compiler/cjcj-stage1','third_party/llvm/bin/opt','third_party/llvm/bin/llc','third_party/llvm/lib/libLLVM-15.so'])record.identities[x]={real:fs.realpathSync(sdk+'/'+x),sha256:hash(sdk+'/'+x)};
 record.entry=fs.readFileSync(sdk+'/bin/cjcj-stage1.entry','utf8');
 if(record.identities['libexec/compiler/cjcj-stage1'].sha256!=='270d62ec74750bcdc72b76f817b4d412cc8d9694cf70d51b4c5c0e9f2d77e04a'||record.identities['third_party/llvm/lib/libLLVM-15.so'].sha256!=='639981a2f902523edd2a02f52678301d87f11fc7d17c38ab11ec76bf61c5c99f')throw Error('identity');
 const input=root+'/source/tests/matrix_iterator_1114/matrix_multiply.cj';record.input={path:input,sha256:hash(input),text:fs.readFileSync(input,'utf8')};record.sourceEqual=fs.readFileSync(input).equals(fs.readFileSync('/root/collect_ten_v2_sol_1113/current-main-1114/src-v2/matrix_multiply.cj'));if(!record.sourceEqual)throw Error('source');record.stdCore={archive:fs.realpathSync(sdk+'/lib/linux_x86_64_cjnative/libcangjie-std-core.a'),sha256:hash(sdk+'/lib/linux_x86_64_cjnative/libcangjie-std-core.a')};save();
 await run('compile',[sdk+'/bin/cjc','--static-std','-O2','--link-option','-Map='+out+'/link.map','--dump-chir','--save-temps',out+'/temps',input,'-o',out+'/matrix_multiply']);
 const files=fs.readdirSync(out+'/temps',{recursive:true}).map(x=>out+'/temps/'+x).filter(x=>fs.statSync(x).isFile());record.files=files;save();let i=0;
 for(const f of files.filter(x=>x.endsWith('.bc')))await run('dis-'+i++,[sdk+'/third_party/llvm/bin/llvm-dis',f,'-o',f+'.ll']);
 record.finalELF={path:out+'/matrix_multiply',sha256:hash(out+'/matrix_multiply')};save();
 rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}record.rc=rc;record.end=new Date().toISOString();save();}process.exit(rc);
