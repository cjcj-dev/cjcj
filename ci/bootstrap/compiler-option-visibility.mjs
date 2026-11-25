import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

// The upstream CMake switch defaults to ON. This is a build input, never an
// environment variable read by the installed compiler.
export function visibleOptionsOnly(value = true) {
  if(value === true || value === 'true')return true;
  if(value === false || value === 'false')return false;
  throw Error('COMPILER_VISIBLE_OPTIONS_ONLY_EXPECTED_BOOLEAN');
}

export async function configureOptionVisibility(source, selected) {
  const enabled=visibleOptionsOnly(selected);
  const file=path.join(source,'packages/option/cjpm.toml');
  const before=await fs.readFile(file,'utf8');
  const entries=[...before.matchAll(/^[\t ]*compile-option\s*=\s*"([^"\n]*)"[^\n]*$/gm)];
  const section=before.match(/^\[package\][\t ]*\r?\n([\s\S]*?)(?=^\[|(?![\s\S]))/m);
  const flag=/--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=(true|false)(?=\s|$)/g;
  const matches=entries.length===1&&section&&entries[0].index>=section.index&&entries[0].index<section.index+section[0].length
    ?[...entries[0][1].matchAll(flag)]:[];
  if(matches.length!==1||before.split('CANGJIE_VISIBLE_OPTIONS_ONLY').length!==2) {
    // Only frozen pre-switch implementations are known to hardcode true.
    // Compare the actual source bytes, not HEAD or producer metadata. Unknown
    // legacy source must opt into the normal manifest configuration explicitly.
    if(enabled&&!before.includes('CANGJIE_VISIBLE_OPTIONS_ONLY')&&await knownLegacyTrue(source))return async()=>{};
    throw Error('COMPILER_OPTION_CONFIGURATION_UNSUPPORTED');
  }
  const selectedEntry=entries[0][0].replace(matches[0][0],'--cfg CANGJIE_VISIBLE_OPTIONS_ONLY='+enabled);
  const after=before.slice(0,entries[0].index)+selectedEntry+before.slice(entries[0].index+entries[0][0].length);
  if(after===before)return async()=>{};
  await fs.writeFile(file,after);
  return async()=>{await fs.writeFile(file,before);};
}

async function knownLegacyTrue(source) {
  // Match a complete revision, never a mixture of files from different pins.
  const files=['Option.cj','OptionAction.cj','OptionTable.cj'];
  const triples=[
    // 8e9c40c38408cfe5d6b79aaf5f7ae3570b4b36ef
    ['da964852d86e87152547b832c811051eecc0d125b393d1162f4c0839a25a70a1',
     '191b2c53ca79e8e98af81dbac949ea189d0a93b017f7b20f727eb2e9d4934238',
     'ba74baeb794a84b6aa7470d2b59cd712ffdf579eaa12fff87094cc0c9d47e8d3'],
    // 83901791548856f0458f3e3e38c4c1ab7ac496c5 (stage0 H1)
    ['cfb416cb6a900b7a9585b59da5c7c7ff9310f31f7f09021a5923525b839ecc50',
     'badc6528b56a749fea33d6f9c1a94cdab155a9f312a8b3bc4dffb18053f198b8',
     'ba74baeb794a84b6aa7470d2b59cd712ffdf579eaa12fff87094cc0c9d47e8d3'],
  ];
  try {
    if(await fs.lstat(path.join(source,'packages/option/src/BuildConfiguration.cj')).then(()=>true,error=>{if(error.code==='ENOENT')return false;throw error;}))return false;
    const hashes=await Promise.all(files.map(async file=>
      createHash('sha256').update(await fs.readFile(path.join(source,'packages/option/src',file))).digest('hex')));
    return triples.some(triple=>triple.every((expected,i)=>expected===hashes[i]));
  } catch(error) {if(error.code==='ENOENT')return false;throw error;}
}

export function requireOptionVisibility(actual, expected) {
  if(visibleOptionsOnly(actual)!==visibleOptionsOnly(expected))
    throw Error('COMPILER_OPTION_CONFIGURATION_MISMATCH');
}
