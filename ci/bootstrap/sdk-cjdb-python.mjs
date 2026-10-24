#!/usr/bin/env zx
// Verify the actual child configuration and relocated installation after native install.
import fs from 'node:fs/promises';
import path from 'node:path';
import {sdkPlatform} from './sdk-platform.mjs';
import {fileDigest, reject, readJson} from './sdk-io.mjs';
import {relative} from './sdk-flow.mjs';
import {readWindowsPythonInstallation} from './native-python-install.mjs';

export async function pythonConfiguration(pythonRoot, platform, execute, executable, installed=false) {
  const native=sdkPlatform(platform), delimiter=native.os==='win32'?';':':';
  const interpreter=executable || path.join(pythonRoot,native.os==='win32'?'python.exe':'bin/python3.11');
  const env={...process.env,PYTHONDONTWRITEBYTECODE:'1',
    [native.loader]:[pythonRoot,path.join(pythonRoot,'lib'),process.env[native.loader]].filter(Boolean).join(delimiter)};
  const unixLibrary=installed?'os.path.join(sys.prefix,"lib",sysconfig.get_config_var("LDLIBRARY"))'
    :'os.path.join(sysconfig.get_config_var("LIBDIR"),sysconfig.get_config_var("LDLIBRARY"))';
  const {stdout}=await execute(interpreter,['-B','-c',
    `import json,sys,sysconfig,os; lib=os.path.join(sys.prefix,"libs","python311.lib") if os.name=="nt" else ${unixLibrary}; print(json.dumps(dict(executable=sys.executable,version=sys.version,include=sysconfig.get_path("include"),library=lib,suffix=sysconfig.get_config_var("EXT_SUFFIX"),configure=sysconfig.get_config_var("CONFIG_ARGS"))))`],{env});
  const selected=JSON.parse(stdout);
  if(!selected.version.startsWith('3.11.'))reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','Python 3.11 required');
  for(const name of ['executable','include','library'])await fs.stat(selected[name]);
  return selected;
}

// Native filesystem paths use the host separator; producer records and SDK
// inventories use POSIX paths. Check native roots before normalizing, then keep
// the existing installation-relative guard (including parent traversal).
export function pythonSourceRecordPath(value, nativePath=path) {
  if (nativePath.isAbsolute(value) || /^[a-z]:/i.test(value))
    throw new Error('INSTALL_PATH '+value);
  return relative(value.split(nativePath.sep).join('/'));
}

// The original producer record is data, not permission to use an installation.
// Bind its source to the exact Python files that the existing native checks use.
export async function pythonSourceInputs({record, sha256, root, nativeRoot, platform, selected}) {
  if(!record)return {source:{status:'unresolved',reason:'original Python producer inputs not supplied'}};
  const recordHash=await fileDigest(record);
  if(sha256&&recordHash!==sha256)throw new Error('PYTHON_SOURCE_RECORD_BYTES');
  const facts=await readJson(record),source=facts.source;
  if(facts.rc!==0||facts.target!==platform||!source?.url||!/^https?:\/\//.test(source.url)
    ||!/^3\.11\.\d+$/.test(source.version||'')||!/^[0-9a-f]{64}$/.test(source.sha256||'')
    ||selected.version.split(/\s/)[0]!==source.version)
    throw new Error('PYTHON_SOURCE_INPUTS');
  root=await fs.realpath(root);
  nativeRoot=await fs.realpath(nativeRoot);
  const interpreter=path.relative(root,await fs.realpath(selected.executable)),library=path.relative(root,await fs.realpath(selected.library));
  const header=path.relative(root,await fs.realpath(path.join(selected.include,'Python.h')));
  const products=[];
  for(const nativeRelative of [interpreter,header,library]){
    const rel=pythonSourceRecordPath(nativeRelative);
    // An installed symlink must still resolve inside the actual native prefix.
    pythonSourceRecordPath(path.relative(nativeRoot,await fs.realpath(path.join(nativeRoot,rel))));
    const expected=facts.files?.[rel]?.sha256;
    if(!/^[0-9a-f]{64}$/.test(expected||''))throw new Error('PYTHON_SOURCE_PRODUCT '+rel);
    const actual=await fileDigest(path.join(root,rel)),installed=nativeRoot===root?actual:await fileDigest(path.join(nativeRoot,rel));
    console.log('PYTHON_SOURCE_PRODUCT_ASSERTION_REACHED '+JSON.stringify({rel,expected,actual,installed}));
    if(actual!==expected||installed!==expected)throw new Error('PYTHON_SOURCE_PRODUCT_BYTES '+rel);
    products.push({path:path.posix.join('third_party/llvm',rel),sha256:installed});
  }
  const installation=platform==='windows_x86_64'&&facts.installation
    ? await readWindowsPythonInstallation(nativeRoot,{sha256:recordHash}):null;
  return {...(installation?{installation:{record:{path:'third_party/llvm/'+installation.record.path,sha256:installation.record.sha256},
    entries:installation.entries,artifacts:installation.artifacts.map(row=>({...row,path:'third_party/llvm/'+row.path}))}}:{}),source:{status:'resolved',kind:'archive',url:source.url,version:source.version,sha256:source.sha256},
    build:{producer:facts.producer,configuration:{configure:selected.configure??null,host:facts.host,target:facts.target},
      originalInputs:{path:record,sha256:recordHash}},artifacts:products};
}
export async function verifyCjdbPythonConfiguration(pythonRoot, lldbBuild, execute, platform='linux_x86_64', executable) {
  const selected=await pythonConfiguration(pythonRoot,platform,execute,executable);
  const cache = await fs.readFile(path.join(lldbBuild, 'CMakeCache.txt'), 'utf8');
  const value = name => cache.match(new RegExp(`^${name}:[^=]+=([^\\n]*)$`, 'm'))?.[1];
  const actual = {executable:value('_Python3_EXECUTABLE') || value('Python3_EXECUTABLE'),
    include:value('_Python3_INCLUDE_DIR') || value('Python3_INCLUDE_DIR'),
    library:value('_Python3_LIBRARY_RELEASE') || value('Python3_LIBRARY'),
    suffix:value('LLDB_PYTHON_EXT_SUFFIX')};
  // Print before rejecting, so a cut cannot hide the reached target invariant.
  console.log(JSON.stringify({assertion:'CJDB_PYTHON_IDENTITY', selected, actual}));
  for (const name of ['executable','include','library']) {
    if (!actual[name] || await fs.realpath(actual[name]) !== await fs.realpath(selected[name]))
      reject('CJDB_PYTHON_IDENTITY','llvm-cjdb',`${name}: ${actual[name]} != ${selected[name]}`);
  }
  if (actual.suffix !== selected.suffix) reject('CJDB_PYTHON_IDENTITY','llvm-cjdb',`suffix: ${actual.suffix} != ${selected.suffix}`);
  return {selected, actual, cacheSha256:await fileDigest(path.join(lldbBuild,'CMakeCache.txt'))};
}

// A consumer has the installed Python and the original producer facts, not the
// producer's old prefix or CMake build directory. Check the original configure
// relationship as recorded, then run and check the transported installation.
export async function verifyRelocatedCjdbPython({install,original,python,platform,execute}) {
  const configured=original.python.configured;
  for(const key of ['executable','include','library','suffix'])
    if(!configured.selected?.[key]||!configured.actual?.[key]
      ||key==='suffix'&&configured.actual[key]!==configured.selected[key])
      reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','original configured '+key);
  const originalRecord=original.pythonInstallationInput?.sha256||original.pythonSource?.build?.originalInputs?.sha256;
  if(!originalRecord)
    reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','original Python source inputs missing');
  const root=path.join(install,'third_party/llvm');
  const selected=await pythonConfiguration(root,platform,execute,undefined,true);
  if(selected.version!==configured.selected.version||selected.suffix!==configured.selected.suffix)
    reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','installed Python version/ABI differs');
  const pythonSource=await pythonSourceInputs({...python,sha256:originalRecord,root,nativeRoot:root,platform,selected});
  const pythonInstallation=await verifyCjdbPythonInstallation(root,root,execute,platform,selected.executable);
  return {pythonConfiguration:{original:configured,selected},pythonSource,pythonInstallation};
}

export async function verifyCjdbPythonInstallation(pythonRoot, nativeRoot, execute, platform='linux_x86_64', executable) {
  pythonRoot=await fs.realpath(pythonRoot);nativeRoot=await fs.realpath(nativeRoot);
  const native=sdkPlatform(platform),delimiter=native.os==='win32'?';':':';
  const relativeInterpreter=path.relative(pythonRoot,executable || path.join(pythonRoot,native.os==='win32'?'python.exe':'bin/python3.11'));
  if(relativeInterpreter.startsWith('..'+path.sep)||path.isAbsolute(relativeInterpreter))reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','interpreter escaped original Python prefix');
  const interpreter=path.join(nativeRoot,relativeInterpreter);
  if (nativeRoot!==pythonRoot && await fileDigest(interpreter) !== await fileDigest(path.join(pythonRoot,relativeInterpreter)))
    reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','exported interpreter bytes differ');
  const script = `import json,sys,os,sysconfig,importlib
import lldb
binding=importlib.import_module('lldb._lldb')
lldb.SBDebugger.Initialize()
debugger=lldb.SBDebugger.Create()
valid=debugger.IsValid()
if sys.platform=='linux':
 maps=sorted(set(line.split()[-1] for line in open('/proc/self/maps') if '/' in line))
elif sys.platform=='darwin':
 import ctypes
 dyld=ctypes.CDLL(None)
 dyld._dyld_image_count.restype=ctypes.c_uint32
 dyld._dyld_get_image_name.argtypes=[ctypes.c_uint32]
 dyld._dyld_get_image_name.restype=ctypes.c_char_p
 maps=[os.fsdecode(dyld._dyld_get_image_name(i)) for i in range(dyld._dyld_image_count())]
else:
 import ctypes
 from ctypes import wintypes
 psapi=ctypes.WinDLL('psapi')
 kernel=ctypes.WinDLL('kernel32')
 kernel.GetCurrentProcess.restype=wintypes.HANDLE
 process=kernel.GetCurrentProcess()
 modules=(wintypes.HMODULE*4096)()
 needed=wintypes.DWORD()
 psapi.EnumProcessModules.argtypes=[wintypes.HANDLE,ctypes.POINTER(wintypes.HMODULE),wintypes.DWORD,ctypes.POINTER(wintypes.DWORD)]
 psapi.GetModuleFileNameExW.argtypes=[wintypes.HANDLE,wintypes.HMODULE,wintypes.LPWSTR,wintypes.DWORD]
 if not psapi.EnumProcessModules(process,modules,ctypes.sizeof(modules),ctypes.byref(needed)): raise OSError('EnumProcessModules')
 maps=[]
 for i in range(needed.value//ctypes.sizeof(wintypes.HMODULE)):
  name=ctypes.create_unicode_buffer(32768)
  if not psapi.GetModuleFileNameExW(process,modules[i],name,len(name)): raise OSError('GetModuleFileNameExW')
  maps.append(name.value)
result=dict(executable=sys.executable,version=sys.version,suffix=sysconfig.get_config_var('EXT_SUFFIX'),lldb=lldb.__file__,binding=binding.__file__,valid=valid,maps=maps)
print(json.dumps(result),flush=True)
assert valid, 'CJDB_PYTHON_DEBUGGER_VALID'
lldb.SBDebugger.Destroy(debugger)
lldb.SBDebugger.Terminate()
`;
  const env = {...process.env, PYTHONDONTWRITEBYTECODE:'1', PYTHONHOME:nativeRoot,
    PYTHONPATH:path.join(nativeRoot,'lib/python3.11/site-packages'),
    [native.loader]:[nativeRoot,path.join(nativeRoot,'bin'),path.join(nativeRoot,'lib'),path.resolve(nativeRoot,'../../tools/lib'),process.env[native.loader]].filter(Boolean).join(delimiter)};
  const {stdout,stderr} = await execute(interpreter,['-B','-c',script],{env});
  const observed = JSON.parse(stdout.trim());
  console.log(JSON.stringify({assertion:'CJDB_PYTHON_IMPORT',observed,stderr}));
  for (const name of ['lldb','binding']) if (!path.resolve(observed[name]).startsWith(nativeRoot+path.sep))
    reject('CJDB_PYTHON_IMPORT','llvm-cjdb',`${name} escaped exported install`);
  if (!observed.binding.endsWith(observed.suffix)) reject('CJDB_PYTHON_IMPORT','llvm-cjdb','binding ABI differs');
  const pythonPattern=native.os==='win32'?/^python311\.dll$/i:native.os==='darwin'?/^libpython3\.11.*\.dylib$/:/^libpython3\.11\.so/;
  const lldbPattern=native.os==='win32'?/^(?:lib)?lldb\.dll$/i:native.os==='darwin'?/^liblldb.*\.dylib$/:/^liblldb\.so/;
  const libraries=observed.maps.filter(file=>pythonPattern.test(path.basename(file))||lldbPattern.test(path.basename(file)));
  for(const pattern of [pythonPattern,lldbPattern]) {
    const files=libraries.filter(file=>pattern.test(path.basename(file)));
    if(!files.length||files.some(file=>!path.resolve(file).startsWith(nativeRoot+path.sep)))
      reject('CJDB_PYTHON_IMPORT','llvm-cjdb',`loaded library identity ${pattern}`);
  }
  const loaded={};for(const file of libraries)loaded[file]=await fileDigest(file);
  const lldbLibrary=libraries.find(file=>lldbPattern.test(path.basename(file)));
  const tool=native.os==='linux'?'/usr/bin/readelf':native.os==='darwin'?'/usr/bin/otool':'dumpbin';
  const args=native.os==='linux'?['-d',lldbLibrary]:native.os==='darwin'?['-L',lldbLibrary]:['/dependents',lldbLibrary];
  const needed=(await execute(tool,args)).stdout;
  const dependency=native.os==='linux'?/\[libpython3\.11\.so\.1\.0\]/:native.os==='darwin'?/libpython3\.11[^\s]*\.dylib/:/python311\.dll/i;
  const pythonDependencies=needed.match(/(?:libpython[^\s\]\/]*|python\d+\.dll)/gi)||[];
  const wrongPython=pythonDependencies.some(name=>native.os==='win32'?!/^python311\.dll$/i.test(name):!/^libpython3\.11(?:\.|$)/.test(name));
  if(!dependency.test(needed)||wrongPython)reject('CJDB_PYTHON_IMPORT','llvm-cjdb','liblldb Python ABI dependency differs');
  return {observed,loaded,needed,dependencyTool:tool,stderr,interpreterSha256:await fileDigest(interpreter)};
}
