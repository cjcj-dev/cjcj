// Consume the original native CMake installation after transport or relocation.
import fs from 'node:fs/promises';
import path from 'node:path';
import {sdkPlatform} from './sdk-platform.mjs';
import {fileDigest,readJson,relative} from './sdk-flow.mjs';

export async function readInstalledNativeAst({install,buildResult,facts,platform,commit,llvmCommit}) {
  facts??=await readJson(buildResult);
  const ast=facts.astInstallation,native=sdkPlatform(platform);
  if(!ast||ast.platform!==platform||facts.platform!==platform||ast.source?.commit!==commit
    ||facts.commits?.compiler!==commit||llvmCommit&&facts.commits?.llvm!==llvmCommit)
    throw Error('NATIVE_AST_SOURCE_PAIR');
  const library='lib/'+native.tuple+'/libcangjie-ast-support.a';
  const members=[library,'schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h',
    'third_party/flatbuffers/bin/flatc'+native.exe];
  if(ast.library!==library||!ast.files||JSON.stringify(Object.keys(ast.files).sort())!==JSON.stringify([...members].sort()))
    throw Error('NATIVE_AST_INSTALL_SHAPE');
  const root=await fs.realpath(install);
  async function retained(row,name,bytes){
    relative(name);
    const actual=await fs.realpath(path.join(root,name));
    if(!actual.startsWith(root+path.sep))throw Error('NATIVE_AST_INSTALL_ESCAPE '+name);
    const stat=await fs.lstat(path.join(root,name));
    if(!stat.isFile()||!stat.size||bytes!==undefined&&stat.size!==bytes
      ||!/^[a-f0-9]{64}$/.test(row?.sha256||'')||await fileDigest(actual)!==row.sha256)
      throw Error('NATIVE_AST_INSTALL_BYTES '+name);
    return actual;
  }
  for(const name of members)await retained(ast.files[name],name,ast.files[name].bytes);
  if(ast.build?.target!=='cangjie-ast-support'||ast.build.configuration?.stdSupport!=='ON')
    throw Error('NATIVE_AST_BUILD_FACTS');
  return ast;
}
