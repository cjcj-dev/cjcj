#!/usr/bin/env zx
// Verify the actual child configuration and relocated installation before seal.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest, reject} from './sdk-manifest.mjs';

export async function verifyCjdbPythonConfiguration(pythonRoot, lldbBuild, execute) {
  const interpreter = path.join(pythonRoot, 'bin/python3.11');
  const {stdout} = await execute(interpreter, ['-B', '-c',
    'import json,sys,sysconfig; print(json.dumps(dict(executable=sys.executable,version=sys.version,include=sysconfig.get_path("include"),library=sys.prefix+"/lib/"+sysconfig.get_config_var("LDLIBRARY"),suffix=sysconfig.get_config_var("EXT_SUFFIX"))))'],
  {env: {...process.env, PYTHONDONTWRITEBYTECODE:'1', LD_LIBRARY_PATH:path.join(pythonRoot,'lib')}});
  const selected = JSON.parse(stdout);
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

export async function verifyCjdbPythonInstallation(pythonRoot, nativeRoot, execute) {
  const interpreter = path.join(nativeRoot,'bin/python3.11');
  if (await fileDigest(interpreter) !== await fileDigest(path.join(pythonRoot,'bin/python3.11')))
    reject('CJDB_PYTHON_IDENTITY','llvm-cjdb','exported interpreter bytes differ');
  const script = `import json,sys,os,sysconfig,importlib
import lldb
binding=importlib.import_module('lldb._lldb')
lldb.SBDebugger.Initialize()
debugger=lldb.SBDebugger.Create()
valid=debugger.IsValid()
maps=sorted(set(line.split()[-1] for line in open('/proc/self/maps') if '/' in line))
result=dict(executable=sys.executable,version=sys.version,suffix=sysconfig.get_config_var('EXT_SUFFIX'),lldb=lldb.__file__,binding=binding.__file__,valid=valid,maps=maps)
print(json.dumps(result),flush=True)
assert valid, 'CJDB_PYTHON_DEBUGGER_VALID'
lldb.SBDebugger.Destroy(debugger)
lldb.SBDebugger.Terminate()
`;
  const env = {...process.env, PYTHONDONTWRITEBYTECODE:'1', PYTHONHOME:nativeRoot,
    PYTHONPATH:path.join(nativeRoot,'lib/python3.11/site-packages'),
    LD_LIBRARY_PATH:[path.join(nativeRoot,'lib'),path.resolve(nativeRoot,'../../tools/lib')].join(':')};
  const {stdout,stderr} = await execute(interpreter,['-B','-c',script],{env});
  const observed = JSON.parse(stdout.trim());
  console.log(JSON.stringify({assertion:'CJDB_PYTHON_IMPORT',observed,stderr}));
  for (const name of ['lldb','binding']) if (!path.resolve(observed[name]).startsWith(`${nativeRoot}/`))
    reject('CJDB_PYTHON_IMPORT','llvm-cjdb',`${name} escaped exported install`);
  if (!observed.binding.endsWith(observed.suffix)) reject('CJDB_PYTHON_IMPORT','llvm-cjdb','binding ABI differs');
  const libraries = observed.maps.filter(file => /\/(?:libpython|liblldb|ld-linux)/.test(file));
  for (const pattern of [/\/libpython3\.11\.so/, /\/liblldb\.so/]) {
    const files = libraries.filter(file=>pattern.test(file));
    if (!files.length || files.some(file=>!file.startsWith(`${nativeRoot}/`)))
      reject('CJDB_PYTHON_IMPORT','llvm-cjdb',`loaded library identity ${pattern}`);
  }
  const loaded = {};
  for (const file of libraries) loaded[file] = await fileDigest(file);
  const lldbLibrary = libraries.find(file=>/\/liblldb\.so/.test(file));
  const needed = (await execute('/usr/bin/readelf',['-d',lldbLibrary])).stdout;
  if (!needed.includes('[libpython3.11.so.1.0]') || /\[libpython(?!3\.11\.so\.1\.0)/.test(needed))
    reject('CJDB_PYTHON_IMPORT','llvm-cjdb','liblldb NEEDED Python ABI differs');
  return {observed,loaded,needed,readelfSha256:await fileDigest('/usr/bin/readelf'),stderr,interpreterSha256:await fileDigest(interpreter)};
}
