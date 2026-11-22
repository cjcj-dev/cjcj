#!/usr/bin/env zx
// Stage 3 SDK is an installed product. The package job restores this root
// without shipping the Java checkout, JDK or native producer cache.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {javaInteropInput} from '../bootstrap/sdk-java-interop.mjs';
import {readJson,privateRoot,fileDigest} from '../bootstrap/sdk-flow.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';
const exec=promisify(execFile);
async function check(sdk) {
  const facts=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
  const {JAVA_INTEROP_REF:commit,JAVA_INTEROP_SRC_URL:repository}=readSourcePins().source;
  if(!['stage3','source-build'].includes(facts.phase)||facts.platform!=='linux_x86_64'||
    facts.javaInterop?.commit!==commit||facts.javaInterop?.repository!==repository)throw Error('STAGE_SDK_JAVA_SOURCE');
  await javaInteropInput({...facts.javaInterop,install:sdk},{platform:facts.platform,cross:false,
    compilerSha256:await fileDigest(path.join(sdk,'libexec/compiler/cjcj-stage1')),runtimeCommit:facts.runtimeCommit});
}
export async function stageSdkHandoff(mode,root,dir) {
  const sdk=await privateRoot(root),archive=path.join(dir,'stage3-sdk.tar');
  if(path.basename(sdk)!=='cangjie')throw Error('STAGE_SDK_ROOT');
  if(mode==='pack'){
    await check(sdk);
    await fs.mkdir(dir,{recursive:true});
    await exec('tar',['-cf',archive,'-C',path.dirname(sdk),'cangjie']);
  }else if(mode==='restore'){
    if(await fs.lstat(sdk).catch(e=>{if(e.code!=='ENOENT')throw e;}))throw Error('STAGE_SDK_DESTINATION_EXISTS');
  }else throw Error('STAGE_SDK_HANDOFF_MODE');
  const hash=createHash('sha256');
  for await(const chunk of createReadStream(archive))hash.update(chunk);
  const sha256=hash.digest('hex');
  if(mode==='restore'){
    if((await fs.readFile(archive+'.sha256','utf8')).trim()!==sha256)throw Error('STAGE_SDK_ARCHIVE_HASH');
    await fs.mkdir(path.dirname(sdk),{recursive:true});
    const temp=await fs.mkdtemp(sdk+'.restore-');
    await exec('tar',['-xf',archive,'-C',temp]);
    await check(path.join(temp,'cangjie'));
    await fs.rename(path.join(temp,'cangjie'),sdk);await fs.rmdir(temp);
  }else await fs.writeFile(archive+'.sha256',sha256+'\n');
  console.log('STAGE_SDK_HANDOFF '+JSON.stringify({mode,sdk,archive,sha256}));
  return sha256;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))
  await stageSdkHandoff(...process.argv.slice(2));
