#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {copyOutputs, privateRoot} from './sdk-flow.mjs';
import {verifyCjdbPythonConfiguration, verifyCjdbPythonInstallation} from './sdk-cjdb-python.mjs';

async function fixture(t) {
  const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'cjdb-paths-')));
  t.after(() => fs.rm(root, {recursive:true, force:true}));
  return root;
}

test('Windows copy merges the Python directory and preserves conflicting files', async t => {
  const root = await fixture(t), src = path.join(root,'python','Lib'), dest = path.join(root,'native');
  const lib = path.join(dest,'lib');
  await fs.mkdir(src,{recursive:true}); await fs.mkdir(lib,{recursive:true});
  await fs.writeFile(path.join(lib,'llvm.txt'),'LLVM');
  await fs.writeFile(path.join(src,'os.py'),'Python');
  // On POSIX model only the casing returned by realpath; copy, lstat and
  // collision checks use the real shared directory. NTFS uses Lib directly.
  let to = 'Lib';
  if (process.platform !== 'win32') {
    to = 'lib';
    const realpath = fs.realpath;
    t.mock.method(fs,'realpath',async file => file === lib ? path.join(dest,'Lib') : realpath(file));
    await assert.rejects(privateRoot(lib,'linux'), /INSTALL_LINK/);
    await assert.rejects(privateRoot(lib,'darwin'), /INSTALL_LINK/);
    const descriptor = Object.getOwnPropertyDescriptor(process,'platform');
    Object.defineProperty(process,'platform',{value:'win32'});
    t.after(() => Object.defineProperty(process,'platform',descriptor));
  }
  await assert.doesNotReject(copyOutputs(dest,[{from:src,to}]));
  assert.equal(await fs.readFile(path.join(lib,'os.py'),'utf8'),'Python');
  await assert.rejects(copyOutputs(dest,[{from:path.join(src,'os.py'),to:to+'/llvm.txt'}]),/INSTALL_CONFLICT/);
  await assert.rejects(copyOutputs(dest,[{from:src,to:to+'/llvm.txt'}]),/INSTALL_CONFLICT/);
  assert.equal(await fs.readFile(path.join(lib,'llvm.txt'),'utf8'),'LLVM');
});

test('Windows private root rejects junctions, including an ancestor of an existing or missing child', async t => {
  const root = await fixture(t), real = path.join(root,'lib'), link = path.join(root,process.platform==='win32'?'alias':'Lib');
  await fs.mkdir(path.join(real,'child'),{recursive:true});
  await fs.symlink(real,link,'junction');
  for (const name of [link,path.join(link,'child'),path.join(link,'missing')])
    await assert.rejects(privateRoot(name,'win32'),/INSTALL_LINK/);
});

test('LLDB cache accepts only the same Windows Python paths after resolving them', async t => {
  const root = await fixture(t), selected = {suffix:'.pyd',version:'3.11.17'};
  const cache = [], keys = ['executable','include','library'];
  const aliases = new Map(), realpath = fs.realpath;
  for (const [i,key] of keys.entries()) {
    const file = selected[key] = path.join(root,key);
    await fs.writeFile(file,key);
    aliases.set(file,'D:\\Python\\'+key);
    aliases.set(file+'.cache','d:/PYTHON/'+key);
    cache.push(['Python3_EXECUTABLE','Python3_INCLUDE_DIR','Python3_LIBRARY'][i]+':FILEPATH='+file+'.cache');
  }
  t.mock.method(fs,'realpath',file => aliases.get(file) ?? realpath(file));
  await fs.writeFile(path.join(root,'CMakeCache.txt'),[...cache,'LLDB_PYTHON_EXT_SUFFIX:STRING=.pyd',''].join('\r\n'));
  const run = platform => verifyCjdbPythonConfiguration(root,root,async () => ({stdout:JSON.stringify(selected)}),platform);
  await assert.doesNotReject(run('windows_x86_64'));
  await assert.rejects(run('linux_x86_64'),/CJDB_PYTHON_IDENTITY.*executable/);
  aliases.set(selected.library+'.cache','D:/Python-other/library');
  await assert.rejects(run('windows_x86_64'),/CJDB_PYTHON_IDENTITY.*library/);
});

test('Windows Python accepts mixed-case module paths and rejects every escaped image', async t => {
  const root = await fixture(t), native = 'D:\\Sdk\\Llvm', seen = 'd:/SDK/LLVM/Lib';
  const suffix = '.cp311-win_amd64.pyd', lldb = seen+'/__init__.py', binding = seen+'/_lldb'+suffix.toUpperCase();
  const py = 'd:/sdk/llvm/PYTHON311.DLL', outside = 'D:/SDK/LLVM-old';
  // Only the host filesystem spelling is simulated. Use real module bytes for
  // the verifier's digest and keep the observed and canonical names distinct.
  const host = new Map(), canonical = new Map();
  for (const [file,name] of [[lldb,'__init__.py'],[binding,'_lldb'+suffix],[py,'python311.dll'],[path.join(native,'python.exe'),'python.exe']]) {
    const local = path.join(root,name); await fs.writeFile(local,name);
    host.set(file,local); canonical.set(file,native+'\\'+name);
  }
  const readFile = fs.readFile, realpath = fs.realpath;
  t.mock.method(fs,'readFile',(file,...args) => readFile(host.get(file) ?? file,...args));
  t.mock.method(fs,'realpath',file => file === root ? native : canonical.get(file) ?? realpath(file));
  const run = (overrides={}) => verifyCjdbPythonInstallation(root,root,async command => command==='dumpbin'
    ? {stdout:'python311.dll'} : {stdout:JSON.stringify({suffix,lldb,binding,maps:[py,binding],...overrides}),stderr:''},'windows_x86_64');
  await assert.doesNotReject(run());
  await assert.rejects(run({lldb:outside+'/__init__.py'}),/lldb escaped exported install/);
  await assert.rejects(run({binding:seen+'/../../LLVM-old/_lldb'+suffix}),/binding escaped exported install/);
  await assert.rejects(run({maps:[py,binding,'E:/Sdk/Llvm/python311.dll']}),/loaded library identity/);
  canonical.set(py,outside+'/python311.dll');
  await assert.rejects(run(),/loaded library identity/);
});
