// SDK-relative runtime inputs, taken from the native install rules and callers:
// cjfmt/src/main.cpp reads the format file; LSP links the platform shared library;
// HLE main.cj invokes node and its parser invokes TypeScript/cjbind dependencies.
import {nativeToolLibraries} from '../../build/srcbuild/tool-layout.mjs';
import {getTarget,getReleasePlatform} from '../../build/lib/targets.mjs';
export const SOURCE_TOOL_PAYLOADS = Object.freeze({
  cjfmt: Object.freeze(['tools/config/cangjie-format.toml', 'tools/lib/libcangjie-lsp.so']),
  LSPServer: Object.freeze(['tools/lib/libcangjie-lsp.so']),
  hle: Object.freeze(['tools/dtsparser', 'tools/bin/node']),
  cjlint: Object.freeze(['tools/config']),
  cjprof: Object.freeze(['tools/config/static','.target-tools/tools/config/static']),
  cjcompat: Object.freeze([]),
  cjcov: Object.freeze([]), 'cjtrace-recover': Object.freeze([]),
});
export function sourceToolPayloads(tool, platform = 'linux-x64') {
  if (!SOURCE_TOOL_PAYLOADS[tool]) throw new Error(`no source-tool payload declaration for ${tool}`);
  let key=platform;
  try{getTarget(key);}catch{key=getReleasePlatform(platform).host;}
  const spec=getTarget(key).spec;
  const lsp=spec.os==='windows'
    ? ['tools/bin/libcangjie-lsp.dll', 'tools/lib/libcangjie-lsp.dll.a']
    : ['tools/lib/libcangjie-lsp'+(spec.os==='darwin'?'.dylib':'.so')];
  if(tool==='cjfmt')return ['tools/config/cangjie-format.toml',...lsp];
  if(tool==='LSPServer'||tool==='cjcompat')return lsp;
  if(tool==='cjlint')return ['tools/config',...nativeToolLibraries('cjlint',spec.os).map(row=>row.to),...lsp];
  if(tool==='cjprof')return [...SOURCE_TOOL_PAYLOADS.cjprof,...nativeToolLibraries('cjprof',spec.os).map(row=>row.to)];
  if(tool==='hle')return ['tools/dtsparser','tools/bin/node'+spec.exeSuffix];
  return SOURCE_TOOL_PAYLOADS[tool];
}
export function allSourceToolPayloads(tools,platform) {
  const union=new Map();for(const tool of tools)for(const relative of sourceToolPayloads(tool,platform))union.set(relative,tool);
  return [...union.entries()].map(([relative,tool])=>({relative,tool}));
}
