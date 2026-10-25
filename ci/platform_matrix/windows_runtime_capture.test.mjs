#!/usr/bin/env zx
// Finite process/evidence test only: these bytes are not Windows products.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const entry=fileURLToPath(new URL('./windows_runtime_capture.mjs',import.meta.url));
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir();
for(const rc of [0,7])test('native linker evidence survives its own rc '+rc+' and a later deletion',()=>{
 const root=fs.mkdtempSync(path.join(base,'windows-capture-')),build=path.join(root,'build'),out=path.join(root,'evidence');fs.mkdirSync(build);
 const child=path.join(root,'finite-link.mjs');fs.writeFileSync(child,`import fs from 'node:fs';\nfs.writeFileSync('fixture.dll','not PE: finite bytes');fs.writeFileSync('fixture.dll.a','finite import');fs.writeFileSync('windows_x86_64_exports.raw.def','EXPORTS\\nfixture @7 DATA\\n');console.log('finite output');console.error('finite stderr');process.exitCode=${rc};\n`);
 const result=spawnSync(process.execPath,[entry,'run','link','--',process.execPath,child],{cwd:build,encoding:'utf8',env:{...process.env,WINDOWS_RUNTIME_EVIDENCE:out,WINDOWS_RUNTIME_BUILD_ROOT:build}});
 fs.writeFileSync(path.join(root,'stdout'),result.stdout);fs.writeFileSync(path.join(root,'stderr'),result.stderr);
 assert.equal(result.status,rc,result.stderr);
 const recordDir=path.join(out,fs.readdirSync(out)[0]),record=JSON.parse(fs.readFileSync(path.join(recordDir,'command.json')));
 assert.equal(record.rc,rc);assert.equal(record.signal,null);assert.deepEqual(record.argv,[process.execPath,child]);
 fs.unlinkSync(path.join(build,'fixture.dll')); // models make deleting a linked target after POST_BUILD fails
 console.log('LINK_SNAPSHOT_TARGET rc='+rc);
 assert.ok(fs.existsSync(path.join(recordDir,'products/fixture.dll')), 'linked DLL snapshot must survive post-build deletion');
 assert.equal(fs.readFileSync(path.join(recordDir,'products/fixture.dll'),'utf8'),'not PE: finite bytes');
 assert.equal(fs.readFileSync(path.join(recordDir,'products/windows_x86_64_exports.raw.def'),'utf8'),'EXPORTS\nfixture @7 DATA\n');
 assert.equal(record.products.length,3);assert.match(fs.readFileSync(path.join(recordDir,'stderr.log'),'utf8'),/finite stderr/);
});
test('a failed executable launch records null child rc without inventing a successful link',()=>{
 const out=fs.mkdtempSync(path.join(base,'windows-capture-exec-'));
 const result=spawnSync(process.execPath,[entry,'run','build','--',path.join(out,'absent-executable')],{encoding:'utf8',env:{...process.env,WINDOWS_RUNTIME_EVIDENCE:out}});
 assert.equal(result.status,1);const dir=fs.readdirSync(out).find(s=>s.startsWith('build-'));
 const record=JSON.parse(fs.readFileSync(path.join(out,dir,'command.json')));assert.equal(record.rc,null);assert.match(record.error,/ENOENT/);
});

for(const captureRc of [0,9])test('always collector retains the selected archive objects after finite capture rc '+captureRc,()=>{
 const root=fs.mkdtempSync(path.join(base,'windows-objects-')),source=path.join(root,'runtime-source');
 const build=path.join(source,'runtime/CMakebuild'),out=path.join(root,'evidence');
 const selected=path.join(build,'src/Heap/CMakeFiles/Heap.dir/z/zReferenceProcessor.cpp.obj');
 const write=(file,text)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);};
 write(selected,'finite selected bytes, not COFF');
 write(path.join(build,'unselected.obj'),'unselected finite bytes');
 write(path.join(build,'fixture.dll'),'finite bytes, not PE');
 write(path.join(build,'windows_x86_64_exports.raw.def'),'EXPORTS\nfixture @7 DATA\n');
 write(path.join(build,'CMakeCache.txt'),'WINDOWS_EXPORT_READOBJ:FILEPATH='+process.execPath+'\n');
 write(path.join(build,'.cmake/api/v1/reply/index-fixture.json'),'finite graph input');
 write(path.join(source,'runtime/build/capture_windows_runtime_definitions.mjs'),`
import fs from 'node:fs';
const [build,source,revision,output,readobj]=process.argv.slice(2);
fs.mkdirSync(output+'.commands',{recursive:true});
fs.writeFileSync(output+'.commands/link-object-plan.json',JSON.stringify({objects:[{object:${JSON.stringify(selected)},target:'Heap-fixture'}]}));
fs.writeFileSync(output+'.commands/object-0.log','finite reader output, not COFF');
if(${captureRc}===0)fs.writeFileSync(output,JSON.stringify({fixture:true,readobj}));
console.log('FINITE_CAPTURE_REACHED');process.exitCode=${captureRc};
`);
 const r=spawnSync(process.execPath,[entry,'collect'],{encoding:'utf8',env:{...process.env,
  WINDOWS_RUNTIME_EVIDENCE:out,RUNTIME_SOURCE:source,PLATFORM_CI_ROOT:root,WINDOWS_RUNTIME_TOOLCHAIN:path.join(root,'unused-toolchain'),WINDOWS_RUNTIME_BUILD_OUTCOME:'failure'}});
 write(path.join(root,'collector.stdout'),r.stdout);write(path.join(root,'collector.stderr'),r.stderr);
 const products=JSON.parse(fs.readFileSync(path.join(out,'products.json')));
 const command=JSON.parse(fs.readFileSync(path.join(out,'runtime-definitions-command.json')));
 assert.equal(command.rc,captureRc);assert.equal(command.argv.at(-1),process.execPath);
 assert.equal(products.readobj.configured,process.execPath);
 assert.equal(products.runtimeDefinitions.produced,captureRc===0);
 console.log('SELECTED_ARCHIVE_OBJECT_RETENTION_TARGET rc='+captureRc);
 const retained=path.join(out,'selected-objects',path.relative(build,selected));
 assert(fs.existsSync(retained),'runtime-selected Heap object must survive in always evidence');
 assert.equal(fs.readFileSync(retained,'utf8'),'finite selected bytes, not COFF');
 // Check the retained product before the aggregate collector status so a
 // missing object is diagnosed at its own invariant in both reader branches.
 assert.equal(r.status,captureRc===0?0:1,r.stderr);
 assert.equal(products.runtimeDefinitions.selectedObjects.length,1);
 assert(!fs.existsSync(path.join(out,'selected-objects/unselected.obj')));
 assert.equal(fs.readFileSync(path.join(out,'cmake-file-api/reply/index-fixture.json'),'utf8'),'finite graph input');
 assert.equal(fs.readFileSync(path.join(out,'build-products/windows_x86_64_exports.raw.def'),'utf8'),'EXPORTS\nfixture @7 DATA\n');
});
