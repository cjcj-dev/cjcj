// Fixed-tuple qualification only; no successful native-build receipt is minted.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {qualificationRecipe, prepareQualification, exportQualification, verifyQualificationCertificate, verifyInstalledQualification} from './sdk-cjdb-qualification.mjs';
import {readJson, inventory, atomicJson, buildIdentities} from './sdk-manifest.mjs';
const request=await readJson(process.env.CJDB_REQUEST), out=process.env.CJDB_QUALIFICATION_EVIDENCE;
await fs.mkdir(out,{recursive:true});
const component=request.component,directory=request.directory;
qualificationRecipe(component);
assert.deepEqual(request.identity,buildIdentities(request.plan).get(component.id));
assert.equal(directory,request.identity.directory);
await atomicJson(path.join(out,'request.json'),request);
for(const [name,change] of [['old',c=>{c.source.commit='7ed574d4ba6ff1ebeceeb339ab4795e0141e4a60';}],['wrong-sha',c=>{c.source.commit='0'.repeat(40);}],['wrong-tree',c=>{c.source.tree='0'.repeat(40);}]]){
 const c=structuredClone(component);change(c);assert.throws(()=>qualificationRecipe(c),/CJDB_QUALIFICATION_SCOPE/);console.log(`TARGET_TUPLE_REJECT ${name}`);
}
const build=path.join(directory,'build/compiler'),compiler=path.join(directory,'source-inputs/compiler');
const roots={llvm:path.join(directory,'source-inputs/llvm'),compiler,bounds:path.join(compiler,'third_party/boundscheck'),build,demangler:path.join(build,'cangjie-demangler')};
const p=await prepareQualification(request,roots,path.join(out,'qualification'));
const records=[];
async function hook(name){const r=spawnSync(component.config.tools.cmake.path,['-P',p.hook],{encoding:'utf8'});records.push({name,argv:[component.config.tools.cmake.path,'-P',p.hook],rc:r.status,signal:r.signal});await fs.writeFile(path.join(out,name+'.log'),r.stdout+r.stderr);await atomicJson(path.join(out,'commands.json'),records);return r;}
let r=await hook('normal');assert.equal(r.status,0,r.stderr);console.log('TARGET_NEW_TUPLE_PRECONFIGURE');
const byte=path.join(roots.llvm,'utils/boundscheck/include/securec.h'),original=await fs.readFile(byte);
try{await fs.appendFile(byte,'\n/* controlled new-tuple fault */\n');r=await hook('generated-byte-cut');assert.equal(r.status,1);assert.match(r.stderr,/CJDB_GENERATED_BYTES/);console.log('TARGET_GENERATED_BYTE_REJECT');}finally{await fs.writeFile(byte,original);}
r=await hook('restored');assert.equal(r.status,0,r.stderr);
const artifacts=path.join(out,'dependency-capsule'),certificate=await exportQualification(p.contractFile,artifacts),files=await inventory(artifacts);
assert.equal(verifyQualificationCertificate(component,request.identity.buildId,certificate,files,directory),certificate);
assert.throws(()=>verifyQualificationCertificate(component,request.identity.buildId+'-wrong',certificate,files,directory),/CJDB_QUALIFICATION_RECEIPT/);
assert.equal(verifyQualificationCertificate(component,request.identity.buildId,certificate,files,directory),certificate);
const projection={buildId:request.identity.buildId,directory,files,execution:{generatedInputs:certificate},scope:'qualification-only-not-native-receipt'};
const manifest={components:{[component.id]:{receiptJson:JSON.stringify(projection)}},files:Object.fromEntries(Object.entries(files).map(([rel,row])=>[rel,{...row,component:component.id,buildId:request.identity.buildId}]))};
await verifyInstalledQualification(artifacts,{components:[component]},manifest);
const wrong=structuredClone(manifest);wrong.files['native-inputs/qualification.json'].buildId+='-wrong';
await assert.rejects(verifyInstalledQualification(artifacts,{components:[component]},wrong),/CJDB_QUALIFICATION_INSTALL/);
await verifyInstalledQualification(artifacts,{components:[component]},manifest);
await atomicJson(path.join(out,'qualification-only-projection.json'),manifest);
console.log('TARGET_CERTIFICATE_INSTALL_NORMAL_REJECT_RESTORED');
