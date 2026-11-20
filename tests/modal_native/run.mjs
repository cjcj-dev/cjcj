#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const [install, output] = argv._.map(String);
if (![install, output].every(p => p && path.isAbsolute(p))) throw Error('usage: zx run.mjs /installed/sdk /new/output');
const sdk = fs.realpathSync(install), tuple = 'linux_x86_64_cjnative';
const compiler = path.join(sdk, 'bin/cjc');
const runtime = path.join(sdk, 'runtime/lib', tuple);
const llvm = path.join(sdk, 'third_party/llvm/lib');
const env = {...process.env, CANGJIE_HOME:sdk, LD_LIBRARY_PATH:[runtime, llvm, path.join(sdk,'tools/lib')].join(':'),
  PATH:[path.join(sdk, 'bin'), path.join(sdk, 'tools/bin'), '/usr/bin', '/bin'].join(':')};
delete env.LD_PRELOAD;
delete env.LD_AUDIT;
fs.mkdirSync(output);
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const identity = Object.fromEntries([compiler, path.join(runtime,'libcangjie-runtime.so'),path.join(runtime,'libboundscheck.so'),
  path.join(llvm,'libLLVM-15.so')].map(p => [p,{file:fs.realpathSync(p),sha256:digest(p)}]));
fs.writeFileSync(path.join(output,'inputs.json'), JSON.stringify(identity,null,2));
function execute(name, exe, args) {
  const r = spawnSync(exe,args,{env,cwd:output,encoding:'utf8',timeout:300000,maxBuffer:128*1024*1024});
  for (const stream of ['stdout','stderr']) fs.writeFileSync(path.join(output,name+'.'+stream),r[stream]??'');
  fs.writeFileSync(path.join(output,name+'.json'),JSON.stringify({exe,args,rc:r.status,signal:r.signal,error:r.error?.message},null,2));
  return r;
}
const failures = [];
for (const name of ['local','ordinary','escape']) {
  const source = fileURLToPath(new URL('./'+name+'.cj',import.meta.url));
  const exe = path.join(output,name);
  const flags = name === 'ordinary' ? [] : ['--experimental','--enable-local-mode'];
  const compile = execute(name+'-compile', compiler, [...flags,'--diagnostic-format=json',source,'-o',exe]);
  if (name === 'escape') {
    const line = fs.readFileSync(source,'utf8').split('\n').findIndex(s => s.trim()==='return c')+1;
    let errors = [];
    try { errors = JSON.parse(compile.stderr).Diags.filter(d => d.Severity === 'error'); } catch {}
    if (compile.status !== 1 || fs.existsSync(exe) || !errors.some(d => d.DiagKind==='sema_mismatched_types' &&
        d.Location?.File===source && d.Location?.Line===line)) failures.push('escape diagnostic at the returned local');

    continue;
  }
  if (compile.status !== 0 || !fs.existsSync(exe)) { failures.push(name+' compile');continue; }
  fs.writeFileSync(exe+'.sha256',digest(exe)+'\n');
  const run = execute(name+'-run',exe,[]);
  const result = new RegExp('^'+name+' before=(\\d+) active=(\\d+) after=(\\d+) payload=(\\d+)\\s*$','m').exec(run.stdout??'');
  if (!result) { failures.push(name+' missing public observation'); continue; }
  const [before,active,after,payload] = result.slice(1).map(BigInt);
  if (run.status !== 0 || before !== after || payload !== 73n || (name==='local' ? active<=before : active!==before))
    failures.push(name+' runtime rc='+run.status+' '+result[0].trim());
}
if (failures.length) throw Error(failures.join('; '));
