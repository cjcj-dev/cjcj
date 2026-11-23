// H1 is built by H's cjpm/cjc but must link and load N's LLVM. The producer
// rewrites only this host's effective packages/cjc link options; these tests
// read the real manifest so the Linux ELF and Darwin Mach-O sections are the
// ones CJPM applies.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {h1PackageLinkOptions} from './sdk-native-stage.mjs';
import {h1ShimInstall} from './sdk-inputs.mjs';
import {effectiveLinkOptions, linkOptionLines, effectiveSections, DARWIN_CJC_LINK, LEGACY_LINUX_CJC_LINK} from './cjc-link-sections.mjs';

const manifest = await fs.readFile(new URL('../../packages/cjc/cjpm.toml', import.meta.url), 'utf8');
const source = '/work/h1-source', nativeLlvm = '/work/N/third_party/llvm/lib';
const sorted = list => [...list].sort();
function rewrite(platform, text = manifest, supports = true, llvmLibrary) {
  const darwin = platform.startsWith('darwin');
  const library = darwin ? 'libLLVM.dylib' : 'libLLVM-15.so';
  return h1PackageLinkOptions(text, {platform, source, linkFile: source + '/runtime_shim/h1-' + library,
    llvmLibraryFile: llvmLibrary ?? nativeLlvm + '/' + library, hostRuntimeSupportsConfigV1: supports});
}
function otherSectionsVerbatim(platform, out) {
  const wanted = effectiveSections(platform), rows = text => linkOptionLines(text).filter(row => !wanted.includes(row.section))
    .map(row => [row.section, row.value]);
  assert.deepEqual(rows(out), rows(manifest));
}

for (const platform of ['darwin_x86_64', 'darwin_aarch64']) for (const supports of [true, false]) {
  test(`${platform} H1 links N's LLVM and its -rpath names N's LLVM directory (ConfigV1=${supports})`, () => {
    const out = rewrite(platform, manifest, supports), actual = effectiveLinkOptions(out, platform);
    const expected = DARWIN_CJC_LINK.map(token => token === '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM.dylib'
      ? 'runtime_shim/h1-libLLVM.dylib' : token === '${CANGJIE_HOME}/third_party/llvm/lib' ? nativeLlvm : token);
    console.log(`DARWIN_H1_LINK_ASSERT_REACHED platform=${platform}`);
    assert.deepEqual(sorted(actual), sorted(expected));
    assert.equal(actual[actual.indexOf('-rpath') + 1], nativeLlvm);
    assert.equal(actual.some(token => token.includes('${CANGJIE_HOME}/third_party/llvm')), false);
    otherSectionsVerbatim(platform, out);
  });
}

for (const platform of ['linux_x86_64', 'linux_aarch64']) for (const supports of [true, false]) {
  test(`${platform} H1 keeps the ELF link set with N's LLVM input (ConfigV1=${supports})`, () => {
    const out = rewrite(platform, manifest, supports), actual = effectiveLinkOptions(out, platform);
    const expected = LEGACY_LINUX_CJC_LINK
      .filter(token => supports || token !== '--wrap=CJ_MRT_CjRuntimeInitWithConfigV1')
      .map(token => token === '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so' ? 'runtime_shim/h1-libLLVM-15.so' : token);
    assert.deepEqual(sorted(actual), sorted(expected));
    otherSectionsVerbatim(platform, out);
  });
}

test('H1 link rewrite rejects a second H LLVM input, any other H LLVM reference and an unusable N directory', () => {
  const section = '[target.x86_64-apple-darwin]\n  link-option = "';
  assert.ok(manifest.includes(section));
  assert.throws(() => rewrite('darwin_x86_64', manifest.replace(section, section + '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM.dylib ')),
    /H1_PACKAGE_LLVM_LINK_INPUT/);
  assert.throws(() => rewrite('darwin_x86_64', manifest.replace(section, section + '-L${CANGJIE_HOME}/third_party/llvm/lib/clang ')),
    /H1_PACKAGE_HOST_LLVM_REFERENCE/);
  assert.throws(() => rewrite('darwin_x86_64', manifest, true, '/work/N with space/third_party/llvm/lib/libLLVM.dylib'),
    /H1_PACKAGE_LLVM_DIRECTORY/);
  // The other host's section is not effective here and is left untouched.
  assert.doesNotThrow(() => rewrite('darwin_aarch64', manifest.replace(section, section + '-L${CANGJIE_HOME}/third_party/llvm/lib/clang ')));
});

test('the native stage CLI no longer accepts a private tools adapter', () => {
  const entry = fileURLToPath(new URL('./sdk-native-stage.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [entry, '--kind', 'h1', '--source', '/nonexistent/h1', '--sdk', '/nonexistent/N',
    '--output', '/nonexistent/out', '--platform', 'darwin_x86_64', '--private-tools', '/nonexistent/adapter'], {encoding: 'utf8'});
  console.log('PRIVATE_TOOLS_CLI_ASSERT_REACHED status=' + result.status);
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /Unknown option '--private-tools'/);
});

test('every public H1 host takes the prepare-native shim of its own commit; Windows keeps the graph selection', () => {
  const same = {compilerCommit: 'c'.repeat(40), h1Commit: 'c'.repeat(40), shimInstall: '/native-inputs/shim'};
  for (const platform of ['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64']) {
    console.log('H1_SHIM_SELECTION_ASSERT_REACHED ' + platform);
    assert.equal(h1ShimInstall(platform, same), same.shimInstall, platform);
    assert.equal(h1ShimInstall(platform, {...same, h1Commit: 'd'.repeat(40)}), undefined, platform);
  }
  assert.equal(h1ShimInstall('windows_x86_64', same), undefined);
});
