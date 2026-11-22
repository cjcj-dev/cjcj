// The native Java target of interop java/build/build.py installs these files.
import fs from 'node:fs/promises';
import path from 'node:path';
import {privateRoot} from './sdk-flow.mjs';

const tuple='linux_x86_64_cjnative';
export const javaInteropFiles=Object.freeze([
  ...['internal','lang'].flatMap(name=>['cjo','bc'].map(ext=>'modules/'+tuple+'/java.'+name+'.'+ext)),
  ...['internal','lang'].map(name=>'runtime/lib/'+tuple+'/libjava.'+name+'.so'),
  ...['internal','internalFFI','lang'].map(name=>'lib/'+tuple+'/libjava.'+name+'.a'),
  'lib/library-loader.jar',
]);

export async function javaInteropInput(input,{platform,cross,compilerSha256,runtimeCommit}) {
  if(input===undefined)return undefined;
  if(platform!=='linux_x86_64'||cross)throw Error('INSTALL_JAVA_INTEROP_PLATFORM '+platform);
  if(!input || !path.isAbsolute(input.install??'') || !input.repository
    || !/^[0-9a-f]{40}$/.test(input.commit??''))throw Error('INSTALL_JAVA_INTEROP_INPUT');
  if(input.compilerSha256!==compilerSha256||input.runtimeCommit!==runtimeCommit)
    throw Error('INSTALL_JAVA_INTEROP_TARGET');
  const install=await privateRoot(input.install);
  for(const rel of javaInteropFiles) {
    const file=path.join(install,rel);
    const member=await fs.lstat(file).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
    if(!member?.isFile()||await fs.realpath(file)!==file)
      throw Error('INSTALL_JAVA_INTEROP_FILE '+rel);
  }
  return {install,repository:input.repository,commit:input.commit,compilerSha256,runtimeCommit};
}
