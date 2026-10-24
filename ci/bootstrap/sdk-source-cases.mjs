import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {bindNativeSource,verifyNativeSource,nativeSourceOptions} from './sdk-source.mjs';
import {fileDigest} from './sdk-flow.mjs';
const parent=process.env.SDK_SOURCE_TEST_ROOT||process.env.SDK_FLOW_TEST_ROOT
  ||(process.env.RELEASE_EVIDENCE_TEST_ROOT&&path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT,'sdk-flow'));
const product=new URL('./sdk-native-stage.mjs',import.meta.url).pathname;
const execute=(args,options={})=>{const p=spawnSync(args[0],args.slice(1),{encoding:'utf8',...options});assert.equal(p.status,0,p.stderr);return p.stdout.trim();};
async function fixture(){
  assert(parent,'SDK_SOURCE_TEST_ROOT required');await fs.mkdir(parent,{recursive:true});
  const root=await fs.mkdtemp(path.join(parent,'source-binding-')),source=root+'/git';await fs.mkdir(source);
  await fs.writeFile(source+'/main.c','int main(void){return 0;}\n');
  execute(['git','init','-q',source]);execute(['git','-C',source,'add','.']);execute(['git','-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','source binding fixture']);
  const commit=execute(['git','-C',source,'rev-parse','HEAD']),tree=execute(['git','-C',source,'rev-parse','HEAD^{tree}']);
  const archive=root+'/source.tar';execute(['git','-C',source,'archive','-o',archive,commit]);
  const extracted=root+'/archive';await fs.mkdir(extracted);execute(['tar','-xf',archive,'-C',extracted]);
  return {root,source,commit,tree,archive,extracted,sha256:await fileDigest(archive)};
}
test('source binding: configured native and direct Git identities agree before execution',async()=>{
  const f=await fixture(),A='a'.repeat(40),repos={std:{root:f.source,commit:f.commit,tree:f.tree}};
  const args=[process.execPath,product,'--source',f.source,'--commit',f.commit];
  assert.deepEqual(bindNativeSource(args,repos),args);
  assert.throws(()=>bindNativeSource([...args.slice(0,-2),'--commit='+A],repos),/NATIVE_SOURCE_COMMIT/);
  assert.throws(()=>bindNativeSource([...args,'--commit='+A],repos),/DUPLICATE/);
  const options={source:f.source,output:f.root+'/out',commit:f.commit};
  assert.equal(await verifyNativeSource(options),f.commit);
  await assert.rejects(verifyNativeSource({...options,commit:A}),/NATIVE_SOURCE_COMMIT/);
});
test('source binding: archive digest and fixed source record form one input',async()=>{
  const f=await fixture(),repo={root:f.extracted,commit:f.commit,tree:f.tree,archive:{file:f.archive,sha256:f.sha256}};
  const args=bindNativeSource([process.execPath,product,'--source',f.extracted],{std:repo});
  const options={...nativeSourceOptions(args),output:f.root+'/out'};
  assert.equal(options.commit,f.commit);assert.equal(options['source-archive'],f.archive);
  assert.equal(await verifyNativeSource(options),f.commit);
  await assert.rejects(verifyNativeSource({...options,'source-archive-sha256':'0'.repeat(64)}),/NATIVE_SOURCE_ARCHIVE_DIGEST/);
  const compressed=f.root+'/source.tar.gz';execute(['git','-C',f.source,'archive','--format=tar.gz','-o',compressed,f.commit]);
  assert.equal(await verifyNativeSource({...options,'source-archive':compressed,'source-archive-sha256':await fileDigest(compressed)}),f.commit);
  await assert.rejects(verifyNativeSource({source:f.extracted,output:f.root+'/out',commit:f.commit}),/NATIVE_SOURCE_UNVERIFIABLE/);
  assert.equal(await verifyNativeSource({source:f.extracted,output:f.root+'/out'}),'unknown');
});
