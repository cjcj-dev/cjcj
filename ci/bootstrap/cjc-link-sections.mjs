// packages/<member>/cjpm.toml carries a cross-platform [package].link-option
// and platform link inputs in [target.<triple>] sections; CJPM applies the
// package value followed by the section matching the build host. Consumers
// that rewrite link inputs operate on exactly those effective lines.
export const HOST_TRIPLES = Object.freeze({
  linux_x86_64: 'x86_64-unknown-linux-gnu', linux_aarch64: 'aarch64-unknown-linux-gnu',
  darwin_x86_64: 'x86_64-apple-darwin', darwin_aarch64: 'aarch64-apple-darwin',
  windows_x86_64: 'x86_64-w64-mingw32',
});
const LINK = /^(\s*link-option\s*=\s*)"([^"\r\n]*)"/;
export function linkOptionLines(text) {
  const rows = [];
  let section = '', offset = 0;
  for (const line of text.split('\n')) {
    const header = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (header) section = header[1].trim();
    const match = LINK.exec(line);
    if (match) rows.push({section, start: offset, end: offset + match[0].length, prefix: match[1], value: match[2]});
    offset += line.length + 1;
  }
  return rows;
}
export function effectiveSections(platform) {
  const triple = HOST_TRIPLES[platform];
  if (!triple) throw new Error('CJC_LINK_PLATFORM ' + platform);
  return ['package', 'target.' + triple];
}
export function effectiveLinkOptions(text, platform) {
  const wanted = effectiveSections(platform);
  return linkOptionLines(text).filter(row => wanted.includes(row.section))
    .flatMap(row => row.value.split(/\s+/).filter(Boolean));
}
// Rewrite the effective link-option lines for platform; others stay verbatim.
export function rewriteEffectiveLinkOptions(text, platform, rewrite) {
  const wanted = effectiveSections(platform);
  let result = '', last = 0;
  for (const row of linkOptionLines(text)) {
    if (!wanted.includes(row.section)) continue;
    result += text.slice(last, row.start) + row.prefix + JSON.stringify(rewrite(row.value, row.section));
    last = row.end;
  }
  return result + text.slice(last);
}

// The compiler executable's link contract: the effective Linux link is item
// for item the former ELF option set, Darwin carries the Mach-O inputs of
// build/sdk/producers/platform_matrix/link_option.mjs, and no ELF-only token
// is global (so it never reaches a Mach-O or PE link).
export const LEGACY_LINUX_CJC_LINK = Object.freeze(['--export-dynamic', 'runtime_shim/cjselfhost_llvmshim.o',
  '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so', '-lstdc++', 'runtime_shim/cjc_heap_defaults.o',
  '--wrap=CJ_MRT_CjRuntimeInit', '--wrap=CJ_MRT_CjRuntimeInitWithConfigV1']);
export const DARWIN_CJC_LINK = Object.freeze(['runtime_shim/cjselfhost_llvmshim.o', '-headerpad_max_install_names',
  '-export_dynamic', '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM.dylib', '-lc++', '-rpath', '${CANGJIE_HOME}/third_party/llvm/lib']);
const ELF_ONLY = ['--export-dynamic', '-lstdc++', '--wrap=CJ_MRT_CjRuntimeInit', '--wrap=CJ_MRT_CjRuntimeInitWithConfigV1'];
export function cjcLinkContractProblems(text) {
  const problems = [], sorted = list => [...list].sort();
  const rows = linkOptionLines(text), global = rows.filter(row => row.section === 'package').flatMap(row => row.value.split(/\s+/).filter(Boolean));
  for (const token of global) if (ELF_ONLY.includes(token) || /libLLVM-15\.so$/.test(token)) problems.push('global ELF link option ' + token);
  for (const platform of ['linux_x86_64', 'linux_aarch64']) {
    const actual = effectiveLinkOptions(text, platform);
    if (JSON.stringify(sorted(actual)) !== JSON.stringify(sorted(LEGACY_LINUX_CJC_LINK))) problems.push(platform + ' link differs from the ELF option set');
    const inputs = actual.filter(token => !token.startsWith('-'));
    if (JSON.stringify(inputs) !== JSON.stringify(LEGACY_LINUX_CJC_LINK.filter(token => !token.startsWith('-')))) problems.push(platform + ' link input order changed');
  }
  for (const platform of ['darwin_aarch64', 'darwin_x86_64']) {
    if (!rows.some(row => row.section === 'target.' + HOST_TRIPLES[platform])) { problems.push(platform + ' lacks its target section'); continue; }
    const actual = effectiveLinkOptions(text, platform);
    if (JSON.stringify(sorted(actual)) !== JSON.stringify(sorted(DARWIN_CJC_LINK))) problems.push(platform + ' link differs from the Mach-O option set');
  }
  const windows = effectiveLinkOptions(text, 'windows_x86_64');
  if (windows.some(token => ELF_ONLY.includes(token) || token.endsWith('.dylib'))) problems.push('windows_x86_64 link carries ELF/Mach-O options');
  return problems;
}
