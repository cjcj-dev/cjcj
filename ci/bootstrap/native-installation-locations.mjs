// Resolve locations after artifact transport. Build facts stay in their original
// BUILD-INPUTS.json; the existing native readers validate actual payloads/pairs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest, privateRoot, readJson, relative} from './sdk-flow.mjs';

// nativeN builds its C API probe with this runner's tools, identified by path
// and digest (sdk-native-capi.mjs nativeCapiProbe: cmake, clang++, ninja). The
// producing runner's tools are not this runner's, so they are frozen here.
export const NATIVE_VERIFIER_TOOLS = Object.freeze(['cmake', 'clang++', 'ninja']);
export async function nativeVerifierTools(env = process.env) {
  const exe = process.platform === 'win32' ? '.exe' : '';
  const dirs = String(env.PATH ?? env.Path ?? '').split(path.delimiter).filter(Boolean);
  const tools = {};
  for (const name of NATIVE_VERIFIER_TOOLS) for (const dir of dirs) {
    const file = path.join(dir, name + exe);
    const stat = await fs.stat(file).catch(error => { if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return null; throw error; });
    if (stat?.isFile()) { tools[name] = {path: file, sha256: await fileDigest(file)}; break; }
  }
  return tools;
}

export async function nativeInstallationLocations(root, locations, env=process.env) {
  const member=value=>path.join(root,relative(value));
  const result={};
  for(const name of ['llvm','runtime','ast']) {
    const row=locations.installations?.[name];
    if(row)result[name]={...row,install:member(row.install),buildResult:member(row.buildResult),
      ...(row.sourceRoot?{sourceRoot:member(row.sourceRoot)}:{})};
  }
  if(locations.installations?.shim)result.shim={install:member(locations.installations.shim.install)};
  if(env.CJCJ_NATIVE_CJDB_INSTALL || (result.llvm && result.llvm.install===result.ast?.install)) {
    const install=await privateRoot(env.CJCJ_NATIVE_CJDB_INSTALL || result.llvm.install);
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
  if (result.llvm && !result.llvm.verification?.tools)
    result.llvm = {...result.llvm, verification: {...result.llvm.verification, tools: await nativeVerifierTools(env)}};
  return result;
}
