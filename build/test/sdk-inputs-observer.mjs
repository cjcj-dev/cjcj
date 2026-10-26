#!/usr/bin/env zx
// Limited integration observation only. Production CLI/config/fetch and cjpm
// Git operations remain real; native builds and SDK production are NOT_RUN.
export async function load(url, context, nextLoad) {
  const loaded = await nextLoad(url, context);
  if (loaded.format !== 'module' || !url.startsWith(new URL('../../', import.meta.url).href)) return loaded;
  let source = String(loaded.source);
  if (url.endsWith('/ci/srcbuild/steps/verify.mjs') && process.env.SDK_INPUT_OBSERVE === 'ci-verify') {
    // Keep the real CI argv/env/target and lineage call. Bypass only preflight
    // shell probes; downstream lineage observation stops before smoke/compile.
    const start = source.indexOf('const self =');
    const end = source.indexOf('// Bootstrap produces');
    if (start < 0 || end <= start) throw new Error('CI preflight observation anchor missing');
    source = source.slice(0,start) + source.slice(end);
  }
  if (url.endsWith('/lib/runtime-split.mjs') && process.env.SDK_INPUT_OBSERVE?.startsWith('package')) {
    source = source.replace('export function assertSdkCompilerRuntimeAbi(', 'function unusedSdkCompilerRuntimeAbi(');
    source += '\nexport function assertSdkCompilerRuntimeAbi() {}\n';
  }
  if (url.endsWith('/lib/runtime-split.mjs') && process.env.SDK_INPUT_OBSERVE === 'verify') {
    source = source.replace('export function assertRuntimeSplit(', 'function unusedRuntimeSplit(');
    source += '\nexport function assertRuntimeSplit() {}\n';
  }
  if (url.endsWith('/srcbuild/gc-unit-gate.mjs') && process.env.SDK_INPUT_OBSERVE === 'verify') {
    // The public verify stage now runs the installed language entry. Keep the
    // same finite language boundary while observing host selection downstream;
    // actual language production/qualification is outside this apparatus.
    const anchor = 'export async function runGcUnitLanguageTests(';
    if (!source.includes(anchor)) throw new Error('language observation anchor missing');
    source = source.replace(anchor, 'async function unusedGcUnitLanguageTests(');
    source += '\nexport async function runGcUnitLanguageTests() { console.log("FINITE_LANGUAGE_BOUNDARY_NOT_RUN"); }\n';
  }
  if (url.endsWith('/lib/package-lineage.mjs') && ['verify','ci-verify'].includes(process.env.SDK_INPUT_OBSERVE)) {
    const anchor = "const root = path.resolve(resolveOfficialSdkRoot(officialRoot) ?? await pinnedOfficialSdkRoot());";
    if (!source.includes(anchor)) throw new Error('lineage observation anchor missing');
    source = source.replace(anchor, anchor + `
      console.log('LINEAGE_INPUT_REACHED', root);
      if (root !== process.env.SDK_INPUT_EXPECT_H) throw new Error('LINEAGE_INPUT_MISMATCH');
      throw new Error('LINEAGE_INPUT_OBSERVED');
    `);
  }
  if (url.endsWith('/lib/sdk-path-parity.mjs') && process.env.SDK_INPUT_OBSERVE === 'package') {
    const anchor = 'const referenceRoot = path.resolve(resolveOfficialSdkRoot(officialRoot) ?? await pinnedOfficialSdkRoot());';
    if (!source.includes(anchor)) throw new Error('parity observation anchor missing');
    source = source.replace(anchor, anchor + `
      console.log('PARITY_INPUT_REACHED', JSON.stringify({referenceRoot, candidateRoot}));
      if (referenceRoot !== process.env.SDK_INPUT_EXPECT_H) throw new Error('PARITY_INPUT_MISMATCH');
      if (process.env.SDK_INPUT_READ_H === '1') {
        const entry = fs.readFileSync(path.join(referenceRoot, 'envsetup.sh'), 'utf8');
        if (!entry.length) throw new Error('PRIVATE_H_ENTRY_EMPTY');
        console.log('PRIVATE_H_ENTRY_READ', entry.length);
      }
      throw new BuildError('input-observer', 'PARITY_INPUT_OBSERVED');
    `);
  }
  if (url.endsWith('/srcbuild/stages/tools.mjs') && process.env.SDK_INPUT_OBSERVE === 'tools') {
    const check = 'const directory=requireToolProducer(name);';
    if (!source.includes(check)) throw new Error('producer observation anchor missing');
    source = source.replace(check, check + "\nconsole.log('TOOLS_PRODUCER_CHECK_REACHED',name);");
    const anchor = 'await prepareNativeToolDependencies(config,pending.map(([name])=>name));';
    if (!source.includes(anchor)) throw new Error('tools observation anchor missing');
    source = source.replace(anchor, `console.log('TOOLS_NATIVE_BOUNDARY_REACHED');
      throw new BuildError('input-observer', 'TOOLS_INPUT_OBSERVED');\n${anchor}`);
  }
  if (url.endsWith('/srcbuild/stages/stdx.mjs') && process.env.SDK_INPUT_OBSERVE === 'stdx') {
    const anchor = 'let split;';
    if (!source.includes(anchor)) throw new Error('stdx observation anchor missing');
    source = source.replace(anchor, `console.log('STDX_NATIVE_BOUNDARY_REACHED');
      throw new Error('STDX_INPUT_OBSERVED');\n${anchor}`);
  }
  return {...loaded, source};
}
