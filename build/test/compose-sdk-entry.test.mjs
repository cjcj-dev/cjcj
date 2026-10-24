import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
const entry=new URL('../../ci/srcbuild/steps/compose-sdk.mjs',import.meta.url).pathname;
// Actual CLI preparation refusals. Complete stage3/source/run/installed package
// guarantees remain in the registered real installed gate and platform producer
// gates; these fixtures never manufacture STAGE/BUILD facts for a C program.
for(const mode of ['local','github','github-missing-run'])test(`compose public entry requires the native configuration and actual installed stage (${mode})`,async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'compose-entry-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const workspace=path.join(root,'workspace'),env={...process.env,CANGJIE_WORKSPACE:workspace,SOURCE_SDK_VERSION:'finite',CJCJ_SRCBUILD_TARGET:'linux-x64'};
 for(const name of Object.keys(env))if(name.startsWith('GITHUB_')||name==='CJCJ_SDK_TARGETS')delete env[name];
 if(mode!=='local')Object.assign(env,{GITHUB_ACTIONS:'true',GITHUB_REPOSITORY:'cjcj-dev/cjcj',GITHUB_SERVER_URL:'https://github.com',GITHUB_RUN_ID:'finite',GITHUB_RUN_ATTEMPT:'1'});
 if(mode==='github-missing-run')delete env.GITHUB_RUN_ID;
 const run=()=>spawnSync('npx',['--yes','zx@8',entry],{cwd:root,env,encoding:'utf8'});
 const first=run();assert.equal(first.status,1);assert.match(first.stderr,/ENOENT.*build-targets\.json/);
 await fs.mkdir(workspace);await fs.writeFile(path.join(workspace,'build-targets.json'),JSON.stringify({work:root+'/native-work',stages:[]}));
 const installed=run();assert.equal(installed.status,1);assert.match(installed.stderr,/ENOENT.*STAGE-INPUTS\.json/);
 assert.doesNotMatch(installed.stdout,/NATIVE_RELEASE_ARCHIVE|SDK_COLOUR_ABI_ASSERT_PASS/);
 await assert.rejects(fs.stat(path.join(workspace,'software/final-compiler')),{code:'ENOENT'});
 console.log('COMPOSE_REAL_INPUT_REQUIRED '+JSON.stringify({mode,first:{rc:first.status,stderr:first.stderr},installed:{rc:installed.status,stderr:installed.stderr}}));
});
