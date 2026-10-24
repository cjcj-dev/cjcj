// Resolve locations after artifact transport. Build facts stay in their original
// BUILD-INPUTS.json; the existing native readers validate actual payloads/pairs.
import path from 'node:path';
import {privateRoot, readJson, relative} from './sdk-flow.mjs';

export async function nativeInstallationLocations(root, locations, env=process.env) {
  const member=value=>path.join(root,relative(value));
  const result={};
  for(const name of ['llvm','runtime','ast']) {
    const row=locations.installations?.[name];
    if(row)result[name]={...row,install:member(row.install),buildResult:member(row.buildResult),
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
