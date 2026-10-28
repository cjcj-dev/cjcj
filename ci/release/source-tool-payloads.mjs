// SDK-relative runtime inputs, taken from the native install rules and callers:
// Cangjie cjfmt reads its format file; the existing LSP links its shared library;
// HLE main.cj invokes node and its parser invokes TypeScript/cjbind dependencies.
import {nativeToolLibraries} from '../../build/srcbuild/tool-layout.mjs';
import {getTarget,getReleasePlatform} from '../../build/lib/targets.mjs';
export const SOURCE_TOOL_PAYLOADS = Object.freeze({
  cjfmt: Object.freeze(['tools/config/cangjie-format.toml']),
  LSPServer: Object.freeze(['.target-tools/tools/lsp']),
  hle: Object.freeze(['tools/dtsparser', 'tools/bin/node']),
  cjlint: Object.freeze(['.target-tools/tools/cjlint']),
  cjprof: Object.freeze(['tools/config/static','.target-tools/tools/config/static','tools/share/java/cjprof.jar']),
  cjcompat: Object.freeze([]),
  cjhead: Object.freeze(['.target-tools/tools/cjhead']),
  cjcov: Object.freeze([]), 'cjtrace-recover': Object.freeze([]),
});
export function sourceToolPayloads(tool, platform = 'linux-x64') {
  if (!SOURCE_TOOL_PAYLOADS[tool]) throw new Error(`no source-tool payload declaration for ${tool}`);
  let key=platform;
  try{getTarget(key);}catch{key=getReleasePlatform(platform).host;}
  const spec=getTarget(key).spec;
  if(tool==='cjfmt')return SOURCE_TOOL_PAYLOADS.cjfmt;
  if(tool==='LSPServer')return SOURCE_TOOL_PAYLOADS.LSPServer;
  if(tool==='cjlint')return SOURCE_TOOL_PAYLOADS.cjlint;
  if(tool==='cjprof')return [...SOURCE_TOOL_PAYLOADS.cjprof,...nativeToolLibraries('cjprof',spec.os).map(row=>row.to)];
  if(tool==='hle')return ['tools/dtsparser','tools/bin/node'+spec.exeSuffix];
  return SOURCE_TOOL_PAYLOADS[tool];
}
export function allSourceToolPayloads(tools,platform) {
  const union=new Map();for(const tool of tools)for(const relative of sourceToolPayloads(tool,platform))union.set(relative,tool);
  return [...union.entries()].map(([relative,tool])=>({relative,tool}));
}
