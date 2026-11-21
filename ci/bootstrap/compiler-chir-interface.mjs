#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {command, fileDigest} from './sdk-flow.mjs';

export const compilerChirSchema = 'schema/StdxChirFormat.fbs';
export const compilerChirAttributes = 'include/cangjie/CHIR/IR/AttributeInfo.h';
export const compilerChirGenerated = 'include/flatbuffers/StdxChirFormat_generated.h';

// This is the public serialized attribute word, not the private in-memory
// AttributeInfo class or the C++ layout of the compiler used to build std.ast.
export function wireAttributeHeader(source) {
  const body = /public func AttributeIndex\(attr: Attribute\): Int64 \{([\s\S]*?)\n\}/.exec(source)?.[1];
  if (!body) throw Error('missing CHIR AttributeIndex definition');
  const arms = [...body.matchAll(/case Attribute\.(\w+) => (\d+)\s*$/gm)];
  if (!arms.length || arms.length !== (body.match(/\bcase\b/g) || []).length)
    throw Error('unsupported CHIR AttributeIndex definition');
  const wire = arms.map(([, name, bit]) => ({name, bit:Number(bit)}))
    .filter(row => row.bit < 64).sort((a,b) => a.bit-b.bit);
  if (!wire.length || wire.some((row,i) => row.bit!==i))
    throw Error('noncontiguous CHIR wire attribute bits');
  return '#pragma once\n#include <cstdint>\n\nnamespace Cangjie::CHIR {\n' +
    'enum class Attribute {\n' + wire.map(row => '    '+row.name+',\n').join('') +
    '    ATTR_END\n};\nconstexpr std::uint64_t ATTR_SIZE = 64;\n}\n';
}

export async function compilerChirFlatc(sdk, shim) {
  const flatcInput = shim.flatc;
  if (!flatcInput?.path || !flatcInput.sha256) throw Error('missing paired flatc');
  const installed = path.join(sdk,flatcInput.path);
  const flatc = await fs.access(installed).then(()=>installed,e=>{
    if(e.code!=='ENOENT')throw e;
    return flatcInput.file;
  });
  if (!flatc || await fileDigest(flatc)!==flatcInput.sha256) throw Error('compiler CHIR flatc differs from paired flatc');
  return flatc;
}

export function compilerChirCommand(flatc, destination) {
  return [flatc,'--no-warnings','-c','-o',path.dirname(path.join(destination,compilerChirGenerated)),
    path.join(destination,compilerChirSchema)];
}

export async function installCompilerChirInterface({source, destination, sdk, shim, records, env}) {
  const schema = path.join(destination,compilerChirSchema);
  const header = path.join(destination,compilerChirAttributes);
  const generated = path.dirname(path.join(destination,compilerChirGenerated));
  const schemaText = await fs.readFile(path.join(source,compilerChirSchema),'utf8');
  const enumText = await fs.readFile(path.join(source,'packages/chir/src/Enums.cj'),'utf8');
  const definition = wireAttributeHeader(enumText);
  const flatc = await compilerChirFlatc(sdk,shim);
  for (const dir of [path.dirname(schema),path.dirname(header),generated]) await fs.mkdir(dir,{recursive:true});
  await fs.writeFile(schema,schemaText);
  await fs.writeFile(header,definition);
  await command(compilerChirCommand(flatc,destination),{cwd:source,env,records});
}
