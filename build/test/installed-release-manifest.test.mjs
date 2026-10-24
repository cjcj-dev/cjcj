#!/usr/bin/env zx
// Ordinary inventory tests only. These finite files are not a runnable SDK.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
import {writeInstalledReleaseManifest,verifyInstalledReleaseManifest,installedReleaseRows,validateReleaseManifestSource} from '../lib/release-manifest.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT;
test('Python archive source keeps actual archive facts without inventing a Git commit',()=>{
 const source={status:'resolved',kind:'archive',url:'https://www.python.org/ftp/python/3.11.17/Python-3.11.17.tar.xz',version:'3.11.17',sha256:'a'.repeat(64)};
 assert.deepEqual(validateReleaseManifestSource(source,'python'),source);
 for(const change of [{url:'file:///unrecorded'},{version:'3.12.1'},{sha256:'wrong'},{status:'unresolved'}])
  assert.throws(()=>validateReleaseManifestSource({...source,...change},'python'));
 assert.throws(()=>validateReleaseManifestSource(source,'cjcj'),/repository/);
});
if(!base)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
async function fixture(){
 await fs.mkdir(base,{recursive:true});const stage=await fs.mkdtemp(path.join(base,'installed-manifest-'));
 const write=async(rel,bytes)=>{await fs.mkdir(path.dirname(stage+'/'+rel),{recursive:true});await fs.writeFile(stage+'/'+rel,bytes);return {path:rel,sha256:await fileDigest(stage+'/'+rel)};};
 const commit='a'.repeat(40),source={status:'resolved',repository:'https://example.invalid/fixed-fixture.git',commit};
 const product=await write('retained/cjc','finite bytes\0CJCJ-COMMIT:'+commit+'\0');
 const entry=await write('bin/cjc','finite public launcher without product stamp');
 const record=await write('compiler-inputs.json',JSON.stringify({commit,compilerSha256:product.sha256}));
 return {stage,write,options:{stage,platform:'linux_x86_64',components:[{component:'compiler',source,artifact:product,entry,build:{fixture:true}}],inputs:{'compiler-inputs.json':record}}};
}
test('native manifest uses retained product and original source, and rejects changed bytes',async()=>{
 const f=await fixture(),{rows}=await writeInstalledReleaseManifest(f.options);
 assert.equal(rows[0].component,'cjcj');assert.equal(rows[0].artifact.path,'retained/cjc');
 assert.equal(rows[0].embedded_stamp,'CJCJ-COMMIT:'+'a'.repeat(40));
 await verifyInstalledReleaseManifest(f.options);
 const file=f.stage+'/retained/cjc',bytes=await fs.readFile(file);await fs.appendFile(file,'cut');
 await assert.rejects(verifyInstalledReleaseManifest(f.options),/INSTALLED_RELEASE_BYTES/);
 await fs.writeFile(file,bytes);await verifyInstalledReleaseManifest(f.options);
 const manifest=f.stage+'/RELEASE-MANIFEST.jsonl',original=await fs.readFile(manifest);
 const forged=structuredClone(rows);forged[0].source.commit='b'.repeat(40);await fs.writeFile(manifest,JSON.stringify(forged[0])+'\n');
 await assert.rejects(verifyInstalledReleaseManifest(f.options),/INSTALLED_RELEASE_FACTS_MISMATCH/);
 await fs.writeFile(manifest,original);await verifyInstalledReleaseManifest(f.options);
});
test('unresolved original facts are recorded without granting release qualification',async()=>{
 const f=await fixture();f.options.components[0].build=undefined;f.options.components[0].source={status:'unresolved',reason:'original producer did not record source'};
 const {rows}=await writeInstalledReleaseManifest(f.options);assert.equal(rows[0].source.status,'unresolved');
 assert.equal(rows[0].source.commit,undefined);
 await assert.rejects(verifyInstalledReleaseManifest(f.options),/source.status is unresolved/);
});
test('native manifest retains exact record and launcher bytes and unique component names',async()=>{
 const f=await fixture();await writeInstalledReleaseManifest(f.options);
 const file=f.stage+'/compiler-inputs.json',bytes=await fs.readFile(file);await fs.appendFile(file,' ');
 await assert.rejects(installedReleaseRows(f.options),/INSTALLED_RELEASE_BYTES compiler-inputs/);
 await fs.writeFile(file,bytes);
 const entry=f.stage+'/bin/cjc',entryBytes=await fs.readFile(entry);await fs.appendFile(entry,'changed');
 await assert.rejects(installedReleaseRows(f.options),/INSTALLED_RELEASE_BYTES bin\/cjc/);
 await fs.writeFile(entry,entryBytes);await verifyInstalledReleaseManifest(f.options);
 await assert.rejects(installedReleaseRows({...f.options,components:[...f.options.components,...f.options.components]}),/INSTALLED_RELEASE_DUPLICATE/);
});

test('native tool release rows preserve original source and actual no-stamp bytes',async()=>{
 const f=await fixture();
 for(const name of ['cjlint','cjprof','cjcompat']) {
  const artifact=await f.write('.target-tools/tools/bin/'+name,'finite native transport bytes without an embedded stamp');
  f.options.components.push({component:name,source:f.options.components[0].source,artifact,build:{fixture:true}});
 }
 const {rows}=await writeInstalledReleaseManifest(f.options);
 for(const name of ['cjlint','cjprof','cjcompat']) {
  const row=rows.find(row=>row.component==='tool-'+name);
  assert(row,'native tool has its existing release component name: '+name);
  assert.equal(row.embedded_stamp,'no-stamp');
  assert.deepEqual(row.source,f.options.components[0].source);
 }
 await verifyInstalledReleaseManifest(f.options);
});
