// Resolve locations after artifact transport. Build facts stay in their original
// BUILD-INPUTS.json; the existing native readers validate actual payloads/pairs.
import path from 'node:path';
import fs from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {privateRoot, readJson, relative, command} from './sdk-flow.mjs';
const capture=promisify(execFile);

// Actions ZIP transport does not retain executable modes. The optional normal
// installation tar restores them before the existing host and SDK readers run.
export async function unpackNativeInstallations(root) {
  const archive=path.join(root,'native-inputs.tar'),payload=path.join(root,'.native-inputs');
  const exists=file=>fs.lstat(file).then(()=>true,error=>{if(error.code==='ENOENT')return false;throw error;});
  if(!await exists(archive)||await exists(payload))return;
  const {stdout}=await capture('tar',['-tf',archive]);
  for(const name of stdout.trim().split('\n'))
    if(!name.startsWith('.native-inputs/')||name.split('/').includes('..'))throw Error('NATIVE_INSTALLATION_ARCHIVE_PATH');
  await fs.mkdir(payload);
  await command(['tar','-xf',archive,'--strip-components=1','-C',payload]);
}

export async function nativeInstallationLocations(root, locations, env=process.env) {
  const member=value=>path.join(root,relative(value));
  const result={};
  for(const name of ['llvm','runtime','ast']) {
    const row=locations.installations?.[name];
    if(row)result[name]={...row,install:member(row.install),buildResult:member(row.buildResult),
      ...(row.verification?.python?.record&&!path.isAbsolute(row.verification.python.record)
        ?{verification:{...row.verification,python:{...row.verification.python,record:member(row.verification.python.record)}}}:{}),
      ...(row.sourceRoot?{sourceRoot:member(row.sourceRoot)}:{})};
  }
  if(env.CJCJ_NATIVE_CJDB_INSTALL) {
    const install=await privateRoot(env.CJCJ_NATIVE_CJDB_INSTALL);
    const buildResult=path.join(install,'BUILD-INPUTS.json');
    const facts=await readJson(buildResult);
    if(facts.platform!==locations.platform||!facts.configuration)throw Error('NATIVE_CJDB_INSTALL_PLATFORM');
    // N and AST are installed by the same normal CMake invocation. No separate
    // component artifact or synthetic success/configuration is substituted.
    const pythonRecord=facts.pythonInstallationInput?.record||'share/cjcj/build-inputs/python-original.json';
    relative(pythonRecord);
    const python={record:path.join(install,pythonRecord),sha256:facts.pythonInstallationInput?.sha256||facts.pythonSource?.build?.originalInputs?.sha256};
    for(const name of ['llvm','ast'])result[name]={install,buildResult,configuration:facts.configuration,
      ...(name==='llvm'?{verification:{python}}:{})};
  }
  return result;
}
