#!/usr/bin/env zx
// CPU policy for the upstream-suite runner; Python retains its Linux lifetime hooks.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root='/sys/fs/cgroup';
const fail=message=>{throw Error('CPU_ENVELOPE: '+message);};
export function parseCpus(text) {
  const cpus=[];
  for(const item of text.trim().split(',')) {
    if(!/^\d+(?:-\d+)?$/.test(item))fail('invalid affinity');
    const [first,last=first]=item.split('-').map(Number);
    if(last<first||last-first>1048576)fail('invalid affinity range');
    for(let n=first;n<=last;n++)cpus.push(n);
  }
  return [...new Set(cpus)].sort((a,b)=>a-b);
}
export function limit(affinity, quotas) {
  if(!affinity.length)fail('empty affinity');
  let quota=affinity.length*100000,period=100000;
  for(const text of quotas) {
    const [q,p]=text.trim().split(/\s+/);
    if(!/^[1-9]\d*$/.test(p))fail('invalid quota period');
    if(q==='max')continue;
    if(!/^[1-9]\d*$/.test(q)||![Number(q),Number(p)].every(Number.isSafeInteger))fail('invalid quota');
    if(BigInt(q)*BigInt(period)<BigInt(quota)*BigInt(p)){quota=Number(q);period=Number(p);}
  }
  return {affinity,quota,period};
}
function cgroup() {
  const line=fs.readFileSync('/proc/self/cgroup','utf8').split('\n').find(s=>s.startsWith('0::'));
  if(!line)fail('cgroup v2 required');
  return path.join(root,line.slice(3));
}
function quotas(directory) {
  const result=[];
  for(let dir=directory;;dir=path.dirname(dir)) {
    const file=path.join(dir,'cpu.max');
    if(fs.existsSync(file))result.push(fs.readFileSync(file,'utf8'));
    if(dir===root)break;
    if(!dir.startsWith(root+'/'))fail('cgroup escaped mount');
  }
  return result;
}
export function current() {
  const directory=cgroup(),text=fs.readFileSync('/proc/self/status','utf8').match(/^Cpus_allowed_list:\s*(.+)$/m)?.[1];
  if(!text)fail('process affinity unavailable');
  return {cgroup:directory,...limit(parseCpus(text),quotas(directory))};
}
export function validate(request, parent) {
  if(!Array.isArray(request.affinity)||!request.affinity.length||new Set(request.affinity).size!==request.affinity.length||
     !request.affinity.every(cpu=>Number.isSafeInteger(cpu)&&parent.affinity.includes(cpu))||
     ![request.quota,request.period].every(n=>Number.isSafeInteger(n)&&n>0)||
     BigInt(request.quota)*BigInt(parent.period)>BigInt(parent.quota)*BigInt(request.period)||
     BigInt(request.quota)>BigInt(request.affinity.length)*BigInt(request.period))fail('request exceeds parent affinity/quota');
  return request;
}
export function plan() {
  const parent=current();
  const unit='cangjie-test-'+process.ppid+'-'+crypto.createHash('sha256').update(process.cwd()).digest('hex').slice(0,8);
  return {unit,parent,...limit(parent.affinity,[`${parent.quota} ${parent.period}`])};
}
export function options(request) {
  if(!/^cangjie-test-\d+-[a-f0-9]{8}$/.test(request.unit||''))fail('invalid unit');
  validate(request,current());
  // systemd's CPUQuota is a percentage; never round a fractional allowance up.
  const percentage=Number(BigInt(request.quota)*100000000n/BigInt(request.period))/1000000;
  return ['AllowedCPUs='+request.affinity.join(','),'CPUQuota='+percentage+'%',
    'CPUQuotaPeriodSec='+request.period/1000000+'s'];
}
export function verify(request) {
  const actual=current();
  if(path.basename(actual.cgroup)!==request.unit+'.scope')fail('scope identity mismatch');
  validate(request,request.parent);
  const parentNow=limit(request.parent.affinity,quotas(request.parent.cgroup));
  validate(actual,request);validate(actual,parentNow);
  const own=fs.readFileSync(path.join(actual.cgroup,'cpu.max'),'utf8').trim();
  if(own.startsWith('max '))fail('scope quota must be finite');
  return {cgroup:actual.cgroup,cpu_max:own,affinity:actual.affinity,parent:request.parent};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const [mode,input]=process.argv.slice(2);
    const value=mode==='plan'?plan():mode==='options'?options(JSON.parse(input)):
      mode==='verify'?verify(JSON.parse(process.env.CANGJIE_TEST_ENVELOPE||'null')):fail('expected plan, options or verify');
    console.log(JSON.stringify(value));
  }catch(error){console.error(error.message);process.exitCode=1;}
}
