#!/usr/bin/env zx
// CPython's own PCbuild and PC/layout produce the development installation.
// The JSON below records that production; it is not an SDK qualification.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {command,atomicJson,readJson,fileDigest,inventory,privateRoot,withProcessCancellation} from './sdk-flow.mjs';
const capture=promisify(execFile);
export const WINDOWS_PYTHON_SOURCE=Object.freeze({version:'3.11.17',
  url:'https://www.python.org/ftp/python/3.11.17/Python-3.11.17.tar.xz',
  sha256:'bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599'});

export function windowsPythonEnvironment(base,tools) {
  // sdk-flow.command merges process.env again. Undefined values must survive
  // this overlay so Node removes them when spawning; deletion would restore
  // inherited selectors. Windows environment names are case-insensitive.
  const env={...base};
  const cleared=new Set(['PYTHONHOME','PYTHONPATH','PYTHON_HEXVERSION','VIRTUAL_ENV',
    'HOST_PYTHON','ORG','EXTERNALS_DIR','PCBUILD','PYTHON','MSBUILD','REGEN',
    'USETESTMARKER','INCLUDETKINTER','INCLUDECTYPES','INCLUDESSL','INCLUDELIBFFI','INCLUDEEXTERNALS']);
  const selected={PYTHON:tools.bootstrapPython,MSBUILD:tools.msbuild,
    PYTHONDONTWRITEBYTECODE:'1',IncludeTkinter:'false',IncludeCTypes:'true',
    IncludeSSL:'true',IncludeLibffi:'true',IncludeExternals:'true'};
  const values=Object.fromEntries(Object.entries(selected).map(([name,value])=>[name.toUpperCase(),value]));
  for(const name of Object.keys(env))if(cleared.has(name.toUpperCase())||name.toUpperCase() in values)
    env[name]=values[name.toUpperCase()];
  return {...env,...selected};
}

export function windowsPythonBuildArgs(jobs) {
  if(!Number.isSafeInteger(jobs)||jobs<1)throw Error('PYTHON_JOBS');
  // A command line MSBuild property overrides pythoncore.vcxproj's KillPython.
  // -M removes the unbounded default /m before applying the admitted job count.
  return ['call','PCbuild\\build.bat','-p','x64','-c','Release','-e','--no-tkinter','-M',
    '/m:'+jobs,'/p:KillPython=false','/bl:..\\pcbuild.binlog'];
}
export function windowsPythonLayoutArgs({source,build,install,temp}) {
  return ['-B',path.join(source,'PC/layout'),'--source',source,'--build',build,
    '--arch','amd64','--copy',install,'--temp',temp,'--include-dev','--include-stable'];
}
export async function windowsPythonInstallation(install) {
  const required=['python.exe','pythonw.exe','python311.dll','python3.dll','include/Python.h',
    'include/pyconfig.h','libs/python311.lib','Lib/os.py','Lib/ssl.py','Lib/ctypes/__init__.py',
    'DLLs/_ssl.pyd','DLLs/_ctypes.pyd','LICENSE.txt'];
  const top=await fs.readdir(install);
  const crt=top.filter(name=>/^vcruntime.*\.dll$/i.test(name));
  if(!crt.length)throw Error('PYTHON_DEVELOPMENT_INSTALL vcruntime');
  for(const rel of [...required,...crt]) {
    const stat=await fs.lstat(path.join(install,rel)).catch(()=>null);
    if(!stat?.isFile()||!stat.size)throw Error('PYTHON_DEVELOPMENT_INSTALL '+rel);
  }
  const files=await inventory(install);
  const dlls=top.filter(name=>/\.dll$/i.test(name)).sort();
  return {files,entries:['python.exe','pythonw.exe',...dlls,'include','libs','DLLs','Lib','LICENSE.txt']};
}
function samePath(a,b) {return path.resolve(a).toLowerCase()===path.resolve(b).toLowerCase();}
async function installedProbe({install,run,output,env}) {
  const script=`import ctypes,json,os,ssl,sys,sysconfig
assert sys.platform=='win32' and sys.maxsize>2**32
assert sys.version_info[:3]==(3,11,17)
root=os.path.realpath(sys.argv[1]); assert os.path.normcase(os.path.realpath(sys.prefix))==os.path.normcase(root)
assert os.path.normcase(os.path.realpath(sys.executable))==os.path.normcase(os.path.join(root,'python.exe'))
assert os.path.normcase(os.path.realpath(sysconfig.get_path('include')))==os.path.normcase(os.path.join(root,'include'))
for name in ('_ssl','_ctypes'):
 m=__import__(name); assert os.path.normcase(os.path.realpath(m.__file__)).startswith(os.path.normcase(root+os.sep))
facts=dict(executable=sys.executable,version=sys.version,include=sysconfig.get_path('include'),library=os.path.join(root,'libs','python311.lib'),suffix=sysconfig.get_config_var('EXT_SUFFIX'),configure=sysconfig.get_config_var('CONFIG_ARGS'),openssl=ssl.OPENSSL_VERSION)
with open(sys.argv[2],'w',encoding='utf-8') as f: json.dump(facts,f)
print('WINDOWS_PYTHON_INSTALLED_IMPORTS_REACHED',flush=True)`;
  await run([path.join(install,'python.exe'),'-I','-B','-c',script,install,output],{env});
  return readJson(output);
}

export function windowsPythonJobs(requested) {
  const available=os.availableParallelism(),jobs=requested??available;
  if(!Number.isSafeInteger(jobs)||jobs<1)throw Error('WINDOWS_PYTHON_NATIVE_CAPACITY');
  return jobs;
}

export async function nativeWindowsPython(config) {
  // No target override: Linux fixture tests never enter the Windows producer.
  if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_PYTHON_NATIVE_HOST_REQUIRED');
  const jobs=windowsPythonJobs(config.jobs);
  if(!config.work||!config.archive||!config.tools?.bootstrapPython||!config.tools?.msbuild)
    throw Error('WINDOWS_PYTHON_INPUTS');
  const mode=config.mode??'build';
  if(!['build','resume','reuse'].includes(mode))throw Error('WINDOWS_PYTHON_MODE');
  const work=await privateRoot(config.work),source=path.join(work,'source'),build=path.join(source,'PCbuild/amd64');
  const install=path.join(work,'install'),stateFile=path.join(work,'producer-commands.json');
  const archive=await fs.realpath(config.archive);
  if(await fileDigest(archive)!==WINDOWS_PYTHON_SOURCE.sha256)throw Error('WINDOWS_PYTHON_ARCHIVE');
  const tools={tar:config.tools.tar||'tar',cmd:config.tools.cmd||process.env.ComSpec||'cmd.exe',
    bootstrapPython:await fs.realpath(config.tools.bootstrapPython),msbuild:await fs.realpath(config.tools.msbuild)};
  // The upstream batch scripts parse these paths through cmd.exe. Reject shell
  // expansion characters instead of turning a source/tool path into commands.
  for(const value of [work,tools.bootstrapPython,tools.msbuild])
    if(/["%!\r\n&|<>^]/.test(value))throw Error('WINDOWS_PYTHON_BATCH_PATH');
  const env=windowsPythonEnvironment(process.env,tools);
  const sourceInput={...WINDOWS_PYTHON_SOURCE,archive};
  let state;
  if(mode==='build') {
    await fs.mkdir(work,{recursive:true});
    if((await fs.readdir(work)).length)throw Error('WINDOWS_PYTHON_EXISTING_WORK_USE_RESUME');
    state={source:sourceInput,work,tools,commands:[],attempts:[],materialized:false};
  } else {
    state=await readJson(stateFile);
    if(state.source.sha256!==sourceInput.sha256||state.source.version!==sourceInput.version||!samePath(state.work,work))
      throw Error('WINDOWS_PYTHON_RESUME_INPUTS');
    for(const name of ['bootstrapPython','msbuild'])if(!samePath(state.tools[name],tools[name]))throw Error('WINDOWS_PYTHON_RESUME_TOOLS');
  }
  const attempt={mode,jobs,started:new Date().toISOString(),commandStart:state.commands.length};
  state.attempts.push(attempt);
  const run=async(argv,options={})=>{
    try{return await command(argv,{cwd:source,env,records:state.commands,...options});}
    finally{await atomicJson(stateFile,state);}
  };
  await atomicJson(stateFile,state);
  try {
    if(mode==='reuse') {
      const record=await readJson(path.join(install,'PYTHON-BUILD-INPUTS.json'));
      if(record.rc!==0||record.target!=='windows_x86_64'||record.source.sha256!==sourceInput.sha256)
        throw Error('WINDOWS_PYTHON_REUSE_INPUTS');
      for(const [rel,row]of Object.entries(record.files))if(row.type!=='file'||await fileDigest(path.join(install,rel))!==row.sha256)
        throw Error('WINDOWS_PYTHON_REUSE_BYTES '+rel);
      for(const row of Object.values(record.originals||{}))if(await fileDigest(path.join(install,row.path))!==row.sha256)
        throw Error('WINDOWS_PYTHON_REUSE_ORIGINAL');
      await installedProbe({install,run,output:path.join(work,'reuse-probe.json'),env});
      const recordPath=path.join(install,'PYTHON-BUILD-INPUTS.json');
      attempt.rc=0;return {python:install,pythonInputs:{record:recordPath,sha256:await fileDigest(recordPath)}};
    }
    if(!state.materialized) {
      // Preserve a failed extraction rather than overlaying another tree on it.
      const pending=await fs.mkdtemp(path.join(work,'source.pending-'));
      await run([tools.tar,'-xf',archive,'--strip-components=1','-C',pending],{cwd:work});
      await fs.rename(pending,source);state.materialized=true;await atomicJson(stateFile,state);
    }
    await run([tools.bootstrapPython,'-I','-B','-c','import sys; assert sys.version_info >= (3,8); print(sys.version)']);
    // Fetch once explicitly so get_externals' own rc is retained, then the
    // ordinary build -e handles cached/remaining dependencies itself.
    await run([tools.cmd,'/d','/s','/c','call PCbuild\\get_externals.bat --no-tkinter']);
    await run([tools.cmd,'/d','/s','/c',windowsPythonBuildArgs(jobs).join(' ')]);
    const builtPython=path.join(build,'python.exe');
    await run([builtPython,'-I','-B','-c','import sys; assert sys.version_info[:3]==(3,11,17); print(sys.version)']);
    const pendingInstall=await fs.mkdtemp(path.join(work,'install.pending-'));
    await run([builtPython,...windowsPythonLayoutArgs({source,build,install:pendingInstall,temp:path.join(work,'layout-temp')})]);
    const selected=await installedProbe({install:pendingInstall,run,output:path.join(work,'installed-probe.json'),env});
    const layout=await windowsPythonInstallation(pendingInstall);
    const producerRoot=fileURLToPath(new URL('../..',import.meta.url));
    const producerCommit=(await capture('git',['-C',producerRoot,'rev-parse','HEAD'])).stdout.trim();
    if(!/^[a-f0-9]{40}$/.test(producerCommit))throw Error('PYTHON_PRODUCER_SOURCE');
    const record={rc:0,source:sourceInput,host:'windows_x86_64',target:'windows_x86_64',jobs,
      producer:{repository:producerRoot,commit:producerCommit,scriptSha256:await fileDigest(fileURLToPath(import.meta.url))},
      tools:{bootstrapPython:{file:tools.bootstrapPython,sha256:await fileDigest(tools.bootstrapPython)},
        msbuild:{file:tools.msbuild,sha256:await fileDigest(tools.msbuild)}},
      configuration:{buildArgs:windowsPythonBuildArgs(jobs),layoutArgs:windowsPythonLayoutArgs({source,build,install:pendingInstall,temp:path.join(work,'layout-temp')})},
      files:layout.files,installation:{entries:layout.entries},observed:selected,
      externalInputs:await inventory(path.join(source,'externals')),commands:state.commands};
    // Carry actual binary build log and probe alongside the ordinary inputs.
    const originals=path.join(pendingInstall,'share/cjcj/build-inputs/python');
    await fs.mkdir(originals,{recursive:true});
    for(const name of ['pcbuild.binlog','installed-probe.json'])await fs.copyFile(path.join(work,name),path.join(originals,name));
    record.originals=Object.fromEntries(await Promise.all(['pcbuild.binlog','installed-probe.json'].map(async name=>
      [name,{path:'share/cjcj/build-inputs/python/'+name,sha256:await fileDigest(path.join(originals,name))}])));
    // Preserve earlier installations and failed attempts; never overwrite them.
    if(await fs.stat(install).catch(()=>null))await fs.rename(install,path.join(work,'install.previous-'+Date.now()));
    await fs.rename(pendingInstall,install);
    record.observed=await installedProbe({install,run,output:path.join(work,'relocated-probe.json'),env});
    const relocatedOriginal='share/cjcj/build-inputs/python/relocated-probe.json';
    await fs.copyFile(path.join(work,'relocated-probe.json'),path.join(install,relocatedOriginal));
    record.originals.relocatedProbe={path:relocatedOriginal,sha256:await fileDigest(path.join(install,relocatedOriginal))};
    const recordPath=path.join(install,'PYTHON-BUILD-INPUTS.json');
    await atomicJson(recordPath,record);
    attempt.rc=0;
    return {python:install,pythonInputs:{record:recordPath,sha256:await fileDigest(recordPath)}};
  } catch(error) {attempt.rc=error.rc??1;attempt.error=error.message;throw error;}
  finally {attempt.ended=new Date().toISOString();await atomicJson(stateFile,state);}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{console.log(JSON.stringify(await withProcessCancellation(async()=>nativeWindowsPython(await readJson(process.argv[2])))));}
  catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
