import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileDigest} from './sdk-io.mjs';
import {pythonSourceInputs,pythonSourceRecordPath} from './sdk-cjdb-python.mjs';

// Controlled bytes test source-to-installed-byte binding; these are not Python
// executables and do not replace the actual native Python/LLDB consumer gate.
async function fixture(){
 const work=await fs.mkdtemp(path.join(os.tmpdir(),'python-source-')),root=work+'/producer',nativeRoot=work+'/relocated/third_party/llvm';
 const files={};
 for(const rel of ['bin/python3.11','include/python3.11/Python.h','lib/libpython3.11.so.1.0']){
  for(const base of [root,nativeRoot]){await fs.mkdir(path.dirname(base+'/'+rel),{recursive:true});await fs.writeFile(base+'/'+rel,'controlled '+rel);}
  files[rel]={sha256:await fileDigest(root+'/'+rel)};
 }
 await fs.symlink('libpython3.11.so.1.0',root+'/lib/libpython3.11.so');
 const record=work+'/original.json',facts={rc:0,host:'linux_x86_64',target:'linux_x86_64',
  source:{url:'https://example.invalid/Python-3.11.17.tar.xz',version:'3.11.17',sha256:'a'.repeat(64)},files,
  producer:{repository:'controlled original producer',commit:'b'.repeat(40)}};
 await fs.writeFile(record,JSON.stringify(facts));
 const selected={executable:root+'/bin/python3.11',include:root+'/include/python3.11',library:root+'/lib/libpython3.11.so',
  version:'3.11.17 (controlled)',configure:"'--enable-shared' '--with-ensurepip=no'"};
 return {work,facts,request:{record,sha256:await fileDigest(record),root,nativeRoot,platform:'linux_x86_64',selected}};
}
test('original Python archive source follows exact relocated interpreter/header/library bytes',async()=>{
 const {request,facts}=await fixture(),got=await pythonSourceInputs(request);
 assert.equal(got.source.status,'resolved');assert.equal(got.source.sha256,facts.source.sha256);
 assert.equal(got.build.configuration.configure,request.selected.configure);
 assert.equal(got.artifacts.length,3);assert(got.artifacts.every(x=>x.path.startsWith('third_party/llvm/')));
 assert.equal(got.artifacts[2].path,'third_party/llvm/lib/libpython3.11.so.1.0');
});
test('missing original Python inputs stay unresolved, including a matching version',async()=>{
 const {request}=await fixture();assert.equal((await pythonSourceInputs({...request,record:undefined})).source.status,'unresolved');
});
test('changed producer record, version and installed bytes reject; restoration recovers',async()=>{
 const {request}=await fixture(),record=await fs.readFile(request.record),file=request.nativeRoot+'/lib/libpython3.11.so.1.0',bytes=await fs.readFile(file);
 await fs.appendFile(request.record,' ');await assert.rejects(pythonSourceInputs(request),/PYTHON_SOURCE_RECORD_BYTES/);
 await fs.writeFile(request.record,record);
 await assert.rejects(pythonSourceInputs({...request,selected:{...request.selected,version:'3.11.16 (different)'}}),/PYTHON_SOURCE_INPUTS/);
 await fs.appendFile(file,'changed');await assert.rejects(pythonSourceInputs(request),/PYTHON_SOURCE_PRODUCT_BYTES/);
 await fs.writeFile(file,bytes);assert.equal((await pythonSourceInputs(request)).source.status,'resolved');
});

test('Windows native relative paths normalize before record lookup',()=>{
 const root=String.raw`C:\work\python311`;
 for(const rel of ['python.exe','include/Python.h','libs/python311.lib','include/nested/Python.h']) {
  const native=path.win32.relative(root,path.win32.join(root,rel));
  console.log('PYTHON_WINDOWS_RECORD_PATH_ASSERTION_REACHED '+native);
  assert.equal(pythonSourceRecordPath(native,path.win32),rel);
 }
});
test('native record paths reject drive, absolute, UNC and parent escapes',()=>{
 for(const value of ['C:/python.exe','C:python.exe','/python.exe',String.raw`\\server\share\Python.h`,
   String.raw`\Python.h`,'../Python.h',String.raw`..\Python.h`,'include/../Python.h','include/./Python.h'])
  assert.throws(()=>pythonSourceRecordPath(value,path.win32),/INSTALL_PATH/);
 assert.throws(()=>pythonSourceRecordPath(String.raw`include\Python.h`,path.posix),/INSTALL_PATH/);
 assert.equal(pythonSourceRecordPath('include/nested/Python.h',path.posix),'include/nested/Python.h');
});
test('source and installed realpath escapes reject, missing entity remains an error',async()=>{
 const {request,work}=await fixture();
 const outside=work+'/Python.h';await fs.writeFile(outside,'outside header');
 const include=work+'/outside';await fs.mkdir(include);await fs.symlink(outside,include+'/Python.h');
 await assert.rejects(pythonSourceInputs({...request,selected:{...request.selected,include}}),/INSTALL_PATH/);
 const installed=request.nativeRoot+'/include/python3.11/Python.h',bytes=await fs.readFile(installed);
 await fs.rename(installed,installed+'.saved');await fs.symlink(outside,installed);
 await assert.rejects(pythonSourceInputs(request),/INSTALL_PATH/);
 await fs.unlink(installed);await assert.rejects(pythonSourceInputs(request),/ENOENT/);
 await fs.rename(installed+'.saved',installed);assert.deepEqual(await fs.readFile(installed),bytes);
 assert.equal((await pythonSourceInputs(request)).source.status,'resolved');
});
