#!/usr/bin/env zx
// Finite package-boundary inputs, never a Cangjie SDK or producer attestation.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {archiveInstall} from '../../ci/bootstrap/sdk-flow.mjs';
export function finiteNativeLayout(root,sdk) {
 const write=(rel,body)=>{const f=path.join(sdk,rel);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,body);};
 for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead']) {
  write('tools/bin/'+name,'installed launcher '+name);write('tools/bin/'+name+'.entry','finite recipe, not executable');
  const privateDir={LSPServer:'lsp',cjlint:'cjlint',cjhead:'cjhead'}[name];
  write('.target-tools/tools/'+(privateDir?privateDir+'/':'')+'bin/'+name,'source-built '+name);
 }
 for(const rel of ['tools/config/cangjie-format.toml','tools/config/cangjie-repo.toml',
  'tools/dtsparser/analysis.js','tools/dtsparser/DEPENDENCIES.json','tools/bin/node'])write(rel,'finite payload');
 fs.mkdirSync(path.join(sdk,'bin'),{recursive:true});fs.mkdirSync(path.join(sdk,'runtime/lib/linux_x86_64_cjnative'),{recursive:true});
 fs.writeFileSync(root+'/finite-compiler.c','int main(void){return 0;}\n');
 fs.writeFileSync(root+'/finite-runtime.c','int finite_runtime(void){return 0;}\n');
 for(const args of [[root+'/finite-compiler.c','-o',sdk+'/bin/cjc'],
  ['-shared','-fPIC',root+'/finite-runtime.c','-o',sdk+'/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so']]) {
  const r=spawnSync('cc',args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
 }
 // No STAGE-INPUTS/BUILD-MANIFEST: the actual SDK consumer must reject this.
}
export async function publicPackage(config,overlay={}) {
 const args=[new URL('../cli.mjs',import.meta.url).pathname,'--workspace',config.workspace,'--build-root',config.buildRoot,
  '--target',config.target.spec.key,'--build-type',config.buildType,'--cangjie-version',config.cangjieVersion,
  '--stdx-version',String(config.stdxVersion),'--official-sdk-root',config.officialSdkRoot,'package'];
 const env={...process.env,...overlay};delete env.CANGJIE_BUILD_DRY_RUN;
 if(config.consumerSdk)env.CJCJ_SRCBUILD_CONSUMER_SDK=config.consumerSdk;else delete env.CJCJ_SRCBUILD_CONSUMER_SDK;
 const r=spawnSync(process.execPath,args,{env,encoding:'utf8'});
 console.log('FINITE_PUBLIC_PACKAGE '+JSON.stringify({argv:[process.execPath,...args],rc:r.status,signal:r.signal,stderr:r.stderr}));
 if(r.error)throw r.error;
 if(r.status!==0){const e=Error(r.stderr);e.rc=r.status;e.stage=/\[([^\]]+)\]/.exec(r.stderr)?.[1];throw e;}
 throw Error('finite fixture unexpectedly qualified as a complete SDK');
}
export async function rejectsMissingStage(config) {
 await assert.rejects(publicPackage(config),e=>e.rc===1&&/ENOENT.*STAGE-INPUTS\.json/.test(e.message));
}
export async function archiveFiniteLayout(config) {
 // Exercise the production archive/relocation primitive with only file-layout
 // checks. Positive SDK hello/macros and full provenance remain NOT_RUN here.
 const install=path.join(config.softwareDir,'cangjie'),archive=path.join(config.softwareDir,'finite-layout.tar.gz');
 return (await archiveInstall({install,archive,test:{required:['tools/bin/cjpm']},vars:{},records:[]})).archive;
}
