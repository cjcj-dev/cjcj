// Real installed-SDK successor to the package/verify portion of the command
// parity gate. Manual registered gate: no opaque compiler or runtime fixture.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';

const configFile=process.env.SOURCE_PARITY_INSTALLED_CONFIG;
assert(configFile,'SOURCE_PARITY_INSTALLED_CONFIG must name prepared private native SDK options');
const options=JSON.parse(fs.readFileSync(configFile,'utf8'));
assert(options.workspace && options.officialSdkRoot && options.consumerSdk);
const config=buildConfig(options);
assert(!config.target.spec.crossCompile,'this gate requires native installed consumption');
const sdk=path.join(config.softwareDir,'cangjie');
assert.equal(fs.realpathSync(options.consumerSdk),fs.realpathSync(sdk),'package the same installed directory');
assert.notEqual(fs.realpathSync(sdk),fs.realpathSync(options.officialSdkRoot),'reference is not the candidate');
const evidence=fs.mkdtempSync(path.join(config.workspace,'installed-parity-'));
const env={...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:sdk};
delete env.CANGJIE_BUILD_DRY_RUN;
const common=['--workspace',config.workspace,'--build-root',config.buildRoot,
 '--target',config.target.spec.key,'--build-type',config.buildType,
 '--cangjie-version',config.cangjieVersion,'--stdx-version',String(config.stdxVersion),
 '--official-sdk-root',options.officialSdkRoot];
if(options.hostProfile)common.push('--host-profile',options.hostProfile);
function run(name,exe,args){
 const r=spawnSync(exe,args,{env,encoding:'utf8',maxBuffer:64*1024*1024});
 fs.writeFileSync(path.join(evidence,name+'.json'),JSON.stringify({exe,args,rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr}));
 assert.equal(r.status,0,name+'\n'+r.stdout+'\n'+r.stderr);return r;
}
const cli=new URL('../cli.mjs',import.meta.url).pathname;
// packageInstall invokes ABI/path checks, real hello/cjpm/macros, then the
// unpacked consumer with the original installation parked and restored.
run('public-package',process.execPath,[cli,...common,'package']);
const archive=path.join(config.softwareDir,`cangjie-sdk-${config.target.spec.sdkName}-${config.cangjieVersion}.tar.gz`);
const stdx=path.join(config.softwareDir,`cangjie-stdx-${config.target.spec.sdkName}-${config.cangjieVersion}.${config.stdxVersion}.tar.gz`);
assert.equal(config.target.spec.archiveFormat,'tar.gz');
assert.equal(run('sdk-root','tar',['-tf',archive]).stdout.split('\n')[0],'cangjie/');
assert.equal(run('stdx-root','tar',['-tf',stdx]).stdout.split('\n')[0],config.target.stdxTargetSubdir()+'/');
const unpacked=archive+'.unpacked/cangjie';
for(const rel of ['bin/cjc','bin/cjc-frontend','tools/bin/cjpm','tools/bin/cjfmt','tools/bin/hle','tools/bin/LSPServer','tools/bin/cjcov','tools/bin/cjtrace-recover',
 'tools/bin/cjlint','tools/bin/cjprof','tools/bin/cjcompat',
 'tools/check_sdk_usable.mjs','tools/verifier_artifact_gate.mjs']) {
 assert.deepEqual(fs.readFileSync(path.join(sdk,rel)),fs.readFileSync(path.join(unpacked,rel)),'unpacked installed bytes: '+rel);
}
assert(!fs.existsSync(path.join(unpacked,'tools/dtsparser/drop.cj')));
run('public-verify',process.execPath,[cli,...common,'verify']);
console.log('INSTALLED_PACKAGE_VERIFY_REACHED '+evidence);
