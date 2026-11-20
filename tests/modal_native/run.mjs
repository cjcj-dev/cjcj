#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {cleanSdkEnvironment} from '../../ci/bootstrap/sdk-platform.mjs';
import {compilerProducer} from '../../ci/bootstrap/compiler_identity.mjs';

const [install, output] = argv._.map(String);
if (![install, output].every(p => p && path.isAbsolute(p))) throw Error('usage: zx run.mjs /installed/sdk /new/output');
const sdk = fs.realpathSync(install), tuple = 'linux_x86_64_cjnative';
const compiler = path.join(sdk, 'bin/cjc');
const runtime = path.join(sdk, 'runtime/lib', tuple);
const llvm = path.join(sdk, 'third_party/llvm/lib');
const env = cleanSdkEnvironment(sdk,'linux_x86_64',{...process.env,PATH:'/usr/bin:/bin'});
fs.mkdirSync(output);
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const producer = fs.existsSync(path.join(sdk,'STAGE-INPUTS.json')) ? await compilerProducer(sdk) : compiler;
const schema=path.join(sdk,'schema/StdxChirFormat.fbs');
const generated=path.join(sdk,'include/flatbuffers/StdxChirFormat_generated.h');
const flatc=path.join(sdk,'third_party/flatbuffers/bin/flatc');
const inputs = new Set([compiler,producer,schema,generated,flatc,path.join(sdk,'include/cangjie/CHIR/IR/AttributeInfo.h'),path.join(runtime,'libcangjie-runtime.so'),path.join(runtime,'libboundscheck.so'),
  path.join(llvm,'libLLVM-15.so'),path.join(sdk,'modules',tuple,'std/std.runtime.cjo'),
  path.join(sdk,'modules',tuple,'std/std.core.cjo'),path.join(sdk,'lib',tuple,'libcangjie-std-core.a')]);
const identity = Object.fromEntries([...inputs].map(p => {
  const file=fs.realpathSync(p);
  if (!file.startsWith(sdk+path.sep)) throw Error('SDK input resolves outside the installation: '+p);
  return [p,{file,sha256:digest(file)}];
}));
fs.writeFileSync(path.join(output,'inputs.json'), JSON.stringify(identity,null,2));
function execute(name, exe, args) {
  const r = spawnSync(exe,args,{env,cwd:output,encoding:'utf8',timeout:300000,maxBuffer:128*1024*1024});
  for (const stream of ['stdout','stderr']) fs.writeFileSync(path.join(output,name+'.'+stream),r[stream]??'');
  fs.writeFileSync(path.join(output,name+'.json'),JSON.stringify({exe,args,rc:r.status,signal:r.signal,error:r.error?.message},null,2));
  return r;
}
const failures = [];
const regenerated=path.join(output,'schema');
fs.mkdirSync(regenerated);
const gen=execute('stdx-schema',flatc,['--no-warnings','-c','-o',regenerated,schema]);
if (gen.status !== 0 || !fs.existsSync(path.join(regenerated,path.basename(generated))) ||
    digest(path.join(regenerated,path.basename(generated))) !== digest(generated)) failures.push('installed stdx schema/header pair');
const abi = execute('stdx-headers','c++',['-std=c++17','-fsyntax-only','-I'+path.join(sdk,'include'),
  '-I'+path.join(sdk,'third_party/flatbuffers/include'),fileURLToPath(new URL('./sdk_chir.cpp',import.meta.url))]);
if (abi.status !== 0) failures.push('installed stdx C++ interface');

for (const name of ['local','ordinary','escape']) {
  const source = fileURLToPath(new URL('./'+name+'.cj',import.meta.url));
  const exe = path.join(output,name);
  const flags = name === 'ordinary' ? [] : ['--experimental','--enable-local-mode'];
  const compile = execute(name+'-compile', compiler, [...flags,'--diagnostic-format=json',source,'-o',exe]);
  if (name === 'escape') {
    const lines = fs.readFileSync(source,'utf8').split('\n');
    let errors = [];
    try { errors = JSON.parse(compile.stderr).Diags.filter(d => d.Severity === 'error'); } catch {}
    if (compile.status !== 1 || fs.existsSync(exe)) failures.push('escape compilation did not reject the program');
    for (const statement of ['return c','return (if (flag) { outer } else { inner }).value']) {
      const line = lines.findIndex(s => s.trim() === statement) + 1;
      if (!line || !errors.some(d => d.DiagKind==='sema_mismatched_types' &&
          d.Location?.File===source && d.Location?.Line===line)) failures.push('missing region diagnostic: '+statement);
    }

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
