// Record completed native producer inputs and the installed pair. Source commit
// and embedded archive stamp are distinct facts; neither is regenerated here.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify,isDeepStrictEqual} from 'node:util';
import {atomicJson,fileDigest,readJson} from '../../ci/bootstrap/sdk-flow.mjs';
import {embeddedStamp} from './toolchain-identity.mjs';

const execute=promisify(execFile);
export const RUNTIME_INPUTS='RUNTIME-INPUTS.json';
const sha40=value=>/^[0-9a-f]{40}$/.test(value||'');
function relative(value){
  if(typeof value!=='string'||!value||path.isAbsolute(value)||value.includes('\\')||value.split('/').includes('..'))
    throw new Error('RUNTIME_INPUT_PATH');
  return value;
}
// The Git object location may be a private mirror. The source identity survives
// moving that mirror; consumers compare it without reopening the producer path.
export async function runtimeSourceRepository(repository) {
  if(!repository)throw new Error('RUNTIME_SOURCE_REPOSITORY_REQUIRED');
  try { return (await execute('git',['-C',repository,'config','--get','remote.origin.url'])).stdout.trim(); }
  catch(error) { if(error.code!==1)throw error; return path.resolve(repository); }
}
export async function recordRuntimeInputs({repository,sourceRepository,commit,install,artifacts,configuration,work}) {
  if(!sha40(commit)||!repository||!configuration)throw new Error('RUNTIME_SOURCE_INPUTS_REQUIRED');
  sourceRepository??=await runtimeSourceRepository(repository);
  const object=(await execute('git',['-C',repository,'rev-parse','--verify',commit+'^{commit}'])).stdout.trim();
  if(object!==commit)throw new Error('RUNTIME_SOURCE_OBJECT');
  // Observe the completed producer's pair. A source archive stamp is not a Git
  // revision and must never be regenerated from today's source to relabel it.
  let stamp;
  const products=[];
  for(const name of artifacts){
    const file=path.join(install,relative(name)),values=embeddedStamp(await fs.readFile(file),'CJRT-COMMIT');
    if(values.length!==1||!(/^[0-9a-f]{40}$/.test(values[0])||/^src-[0-9a-f]{64}$/.test(values[0])))
      throw new Error('RUNTIME_PAIR_STAMP');
    if(sha40(values[0])&&values[0]!==commit)throw new Error('RUNTIME_SOURCE_OBJECT_STAMP');
    const current='CJRT-COMMIT:'+values[0];
    if(stamp&&stamp!==current)throw new Error('RUNTIME_SOURCE_PAIR_STAMP');
    stamp=current;products.push({path:name,sha256:await fileDigest(file)});
  }
  if(products.length<2||new Set(products.map(row=>row.path)).size!==products.length)throw new Error('RUNTIME_PAIR_REQUIRED');
  const facts={source:{status:'resolved',repository:sourceRepository,commit},embedded_stamp:stamp,
    build:{configuration},artifacts:products};
  await atomicJson(path.join(work,RUNTIME_INPUTS),facts);
  return facts;
}
export async function runtimeInputsForArtifact(stage,artifact,{repository,commit,stamp,configuration}) {
  const facts=await readJson(path.join(stage,RUNTIME_INPUTS));
  const rel=relative(artifact.path);
  if(facts.source?.status!=='resolved'||facts.source.repository!==repository||facts.source.commit!==commit
    ||facts.embedded_stamp!==stamp||!facts.build?.configuration
    ||(configuration!==undefined&&!isDeepStrictEqual(facts.build.configuration,configuration)))
    throw new Error('RUNTIME_SOURCE_INPUT_BINDING');
  const row=facts.artifacts?.find(value=>value.path===rel);
  if(!row||row.sha256!==artifact.sha256||await fileDigest(path.join(stage,rel))!==row.sha256)
    throw new Error('RUNTIME_SOURCE_ARTIFACT_BINDING');
  // The paired archive/shared library must still agree, even when only the
  // canonical shared library is listed by release-manifest.
  if(facts.artifacts.length<2||new Set(facts.artifacts.map(row=>row.path)).size!==facts.artifacts.length)throw new Error('RUNTIME_PAIR_REQUIRED');
  for(const product of facts.artifacts){
    const file=path.join(stage,relative(product.path));
    if(await fileDigest(file)!==product.sha256)throw new Error('RUNTIME_SOURCE_PAIR_BYTES');
    const values=embeddedStamp(await fs.readFile(file),'CJRT-COMMIT');
    if(values.length!==1||'CJRT-COMMIT:'+values[0]!==stamp)throw new Error('RUNTIME_SOURCE_PAIR_STAMP');
  }
  return facts;
}
