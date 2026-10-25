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
