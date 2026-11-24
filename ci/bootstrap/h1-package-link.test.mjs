// H1 is built by H's cjpm/cjc but must link and load N's LLVM. The producer
// rewrites only this host's effective packages/cjc link options; these tests
// read the real manifest so the Linux ELF and Darwin Mach-O sections are the
// ones CJPM applies.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {h1PackageLinkOptions, h1HeapDefaultsBuild} from './sdk-native-stage.mjs';
import {FIXED_INPUTS} from './sdk-targets.mjs';
import {h1ShimInstall, validateSourceInputs, FIXED_H1_MACRO_BLOB} from './sdk-inputs.mjs';
import {effectiveLinkOptions, linkOptionLines, effectiveSections, DARWIN_CJC_LINK, LEGACY_LINUX_CJC_LINK} from './cjc-link-sections.mjs';

const manifest = await fs.readFile(new URL('../../packages/cjc/cjpm.toml', import.meta.url), 'utf8');
const source = '/work/h1-source', nativeLlvm = '/work/N/third_party/llvm/lib';
const sorted = list => [...list].sort();
// The managed Unix H1 is built from FIXED_INPUTS.h1. Its packages/cjc
// manifest is kept here byte for byte (sha256 bound) so the producer is
// tested on the source it actually reads, not only on candidate HEAD: it has
// the ELF link in [package] alone and no [target.<triple>] section.
const H1_SOURCE = '83901791548856f0458f3e3e38c4c1ab7ac496c5';
const H1_MANIFEST_SHA256 = 'ff3df7623e3415e82a65025318a01e45e66d2d73b205a71c5e6e04785801d68b';
const h1Manifest = [
"[package]",
"  cjc-version = \"1.1.0\"",
"  name = \"cjc\"",
"  organization = \"cjcj\"",
"  description = \"Self-hosted Cangjie compiler executable entry\"",
"  version = \"0.1.0\"",
"  target-dir = \"\"",
"  script-dir = \"\"",
"  src-dir = \"src\"",
"  output-type = \"executable\"",
"  compile-option = \"\"",
"  override-compile-option = \"\"",
"  link-option = \"--export-dynamic runtime_shim/cjselfhost_llvmshim.o runtime_shim/cjc_runtime_config.o ${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so -lstdc++\"",
"  package-configuration = {}",
"",
"[dependencies]",
"  \"cjcj::driver\" = { path = \"../driver\" }",
"  \"cjcj::utils\" = { path = \"../utils\" }",
"  \"cjcj::frontend\" = { path = \"../frontend\" }",
"  \"cjcj::chir\" = { path = \"../chir\" }",
"  \"cjcj::basic\" = { path = \"../basic\" }",
""
].join('\n');
const UNIX = ['linux_x86_64', 'linux_aarch64', 'darwin_aarch64', 'darwin_x86_64'];
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

test('the H1 manifest under test is the exact FIXED_INPUTS.h1 packages/cjc/cjpm.toml', () => {
  assert.equal(FIXED_INPUTS.h1, H1_SOURCE);
  assert.equal(createHash('sha256').update(h1Manifest).digest('hex'), H1_MANIFEST_SHA256);
  // Where the object is present (full local clone), it is the same bytes.
  const git = spawnSync('git', ['show', `${H1_SOURCE}:packages/cjc/cjpm.toml`], {encoding: 'utf8'});
  if (git.status === 0) assert.equal(git.stdout, h1Manifest);
  assert.equal(linkOptionLines(h1Manifest).some(row => row.section.startsWith('target.')), false);
});

for (const platform of UNIX) for (const supports of [true, false]) {
  test(`${platform} H1 from FIXED_INPUTS.h1 links N's LLVM with no H LLVM or ELF residue (ConfigV1=${supports})`, () => {
    const darwin = platform.startsWith('darwin');
    const out = rewrite(platform, h1Manifest, supports), actual = effectiveLinkOptions(out, platform);
    console.log(`H1_FIXED_SOURCE_LINK_ASSERT_REACHED platform=${platform}`);
    const expected = darwin
      ? ['-export_dynamic', 'runtime_shim/cjselfhost_llvmshim.o', 'runtime_shim/cjc_runtime_config.o',
        '-headerpad_max_install_names', 'runtime_shim/h1-libLLVM.dylib', '-rpath', nativeLlvm, '-lc++']
      : ['--export-dynamic', 'runtime_shim/cjselfhost_llvmshim.o', 'runtime_shim/cjc_runtime_config.o',
        'runtime_shim/h1-libLLVM-15.so', '-lstdc++'];
    assert.deepEqual(actual, expected);
    assert.equal(actual.some(token => token.includes('${CANGJIE_HOME}/third_party/llvm')), false);
    if (darwin) {
      for (const elf of ['--export-dynamic', '-lstdc++']) assert.equal(actual.includes(elf), false, elf);
      assert.equal(actual.some(token => token.includes('libLLVM-15.so')), false);
      // Same Mach-O contract as candidate HEAD's [target.<triple>] link; the
      // fixed source carries cjc_runtime_config.o in [package] instead of the
      // workspace line.
      assert.deepEqual(sorted(actual), sorted([...effectiveLinkOptions(rewrite(platform, manifest, supports), platform),
        'runtime_shim/cjc_runtime_config.o']));
    }
    assert.deepEqual(linkOptionLines(out).filter(row => row.section !== 'package'), linkOptionLines(h1Manifest).filter(row => row.section !== 'package'));
  });
}

test('candidate HEAD keeps its own [target.<triple>] link on all four Unix hosts', () => {
  for (const platform of UNIX) {
    const actual = effectiveLinkOptions(rewrite(platform), platform);
    assert.equal(actual.some(token => token.includes('${CANGJIE_HOME}/third_party/llvm')), false, platform);
    if (platform.startsWith('darwin')) {
      for (const elf of ['--export-dynamic', '-lstdc++']) assert.equal(actual.includes(elf), false, platform);
      assert.equal(actual.some(token => token.includes('libLLVM-15.so')), false, platform);
    } else assert.ok(actual.includes('runtime_shim/h1-libLLVM-15.so'), platform);
  }
});

test('a Darwin H1 from an ELF-only [package] rejects ELF tokens with no Mach-O meaning', () => {
  const line = '-lstdc++"';
  assert.ok(h1Manifest.includes(line));
  for (const token of ['--wrap=CJ_MRT_CjRuntimeInit', '-Wl,--gc-sections', '/opt/lib/libextra.so'])
    assert.throws(() => rewrite('darwin_x86_64', h1Manifest.replace(line, `-lstdc++ ${token}"`)), /H1_PACKAGE_DARWIN_ELF_TOKEN/, token);
  assert.throws(() => rewrite('darwin_aarch64', h1Manifest.replace(line, `-lstdc++ ${'${CANGJIE_HOME}'}/third_party/llvm/lib/libLLVM-15.so"`)),
    /H1_PACKAGE_LLVM_LINK_INPUT/);
});

test('H1 compiles cjc_heap_defaults.c only where a manifest names its object, and fails closed if that source is absent', () => {
  const workspace = '[workspace]\n  link-option = "runtime_shim/cjc_runtime_config.o"\n';
  for (const platform of UNIX) {
    console.log(`H1_HEAP_DEFAULTS_ASSERT_REACHED platform=${platform}`);
    // FIXED_INPUTS.h1: no runtime_shim/cjc_heap_defaults.c, no reference.
    assert.equal(h1HeapDefaultsBuild({workspaceText: workspace, packageText: h1Manifest, platform, sourcePresent: false}), false);
    const linux = platform.startsWith('linux');
    assert.equal(h1HeapDefaultsBuild({workspaceText: workspace, packageText: manifest, platform, sourcePresent: true}), linux);
    if (linux) assert.throws(() => h1HeapDefaultsBuild({workspaceText: workspace, packageText: manifest, platform, sourcePresent: false}),
      /H1_HEAP_DEFAULTS_SOURCE_MISSING runtime_shim\/cjc_heap_defaults\.c/);
    else assert.equal(h1HeapDefaultsBuild({workspaceText: workspace, packageText: manifest, platform, sourcePresent: false}), false);
    // A workspace line naming the object binds every host the same way.
    assert.throws(() => h1HeapDefaultsBuild({workspaceText: workspace.replace('config.o', 'config.o runtime_shim/cjc_heap_defaults.o'),
      packageText: h1Manifest, platform, sourcePresent: false}), /H1_HEAP_DEFAULTS_SOURCE_MISSING/);
  }
});

test('the Unix H1 producer gates the heap-defaults compile on that decision', async () => {
  const stage = await fs.readFile(new URL('./sdk-native-stage.mjs', import.meta.url), 'utf8');
  const unix = stage.slice(stage.indexOf("// Linux and Darwin build H1 from the public CJPM workspace"), stage.indexOf("} else if(kind==='compiler')"));
  assert.match(unix, /const heapDefaults=h1HeapDefaultsBuild\(\{workspaceText:before\.toString\(\),packageText:packageBefore\.toString\(\),platform,/);
  assert.match(unix, /if\(heapDefaults\)await command\(/);
  assert.equal((unix.match(/cjc_heap_defaults\.c/g) || []).length, 1);
});

test('either Darwin manifest shape fails closed on any link token outside the Mach-O contract', () => {
  // The reviewer's counterexample: 2 manifests x 2 Darwin hosts x 4 single extra tokens.
  const inject = (text, token) => text.replace(/^(\s*link-option\s*=\s*"[^"\n]*)"/m, `$1 ${token}"`);
  for (const [shape, text] of Object.entries({'FIXED_INPUTS.h1': h1Manifest, 'candidate HEAD': manifest}))
    for (const platform of ['darwin_x86_64', 'darwin_aarch64']) {
      rewrite(platform, text); // control: the unmodified manifest links
      for (const token of ['--wrap=review', '-Wl,--gc-sections', '/lib/libextra.so', '--gc-sections'])
        assert.throws(() => rewrite(platform, inject(text, token)), /H1_PACKAGE_DARWIN_(ELF_TOKEN|LINK_SET)/,
          `${shape} ${platform} ${token}`);
    }
});

const repository = fileURLToPath(new URL('../..', import.meta.url));
const gitOut = (...args) => spawnSync('git', ['-C', repository, ...args], {encoding: 'utf8'});
const fixedObject = gitOut('cat-file', '-e', FIXED_INPUTS.h1 + '^{commit}').status === 0;
const SAME_BLOB_OTHER_COMMIT = 'b14420bd35868433349d26c5c5d0c4ff58f159f5'; // parent of a74bcfa8aa (first later macro change)
test('the default Unix H1 passes the macro gate by its approved blob; other H1s and every compiler still need the candidate macro',
  {skip: !fixedObject && 'FIXED_INPUTS.h1 object absent (shallow clone)'}, async () => {
  const row = commit => ({repository, commit, tree: gitOut('rev-parse', commit + '^{tree}').stdout.trim()});
  const head = row(gitOut('rev-parse', 'HEAD').stdout.trim()), fixed = row(FIXED_INPUTS.h1);
  assert.equal(gitOut('rev-parse', FIXED_INPUTS.h1 + ':packages/macro/src/InvokeUtil.cj').stdout.trim(), FIXED_H1_MACRO_BLOB);
  // The fixed H1 macro source differs from the candidate's: the old gate's first error.
  assert.notEqual(gitOut('rev-parse', 'HEAD:packages/macro/src/InvokeUtil.cj').stdout.trim(), FIXED_H1_MACRO_BLOB);
  const base = {llvm: head, runtime: head, ast: head, compiler: head};
  await validateSourceInputs({...base, h1: fixed});
  // Identity, not content: the same macro blob at another commit is refused.
  assert.equal(gitOut('rev-parse', SAME_BLOB_OTHER_COMMIT + ':packages/macro/src/InvokeUtil.cj').stdout.trim(), FIXED_H1_MACRO_BLOB);
  await assert.rejects(validateSourceInputs({...base, h1: row(SAME_BLOB_OTHER_COMMIT)}), /NATIVE_MACRO_SOURCE h1/);
  // The compiler is never admitted by the H1 blob; a forged tree is refused first.
  await assert.rejects(validateSourceInputs({...base, h1: fixed, compiler: fixed}), /NATIVE_MACRO_SOURCE compiler/);
  await assert.rejects(validateSourceInputs({...base, h1: {...fixed, tree: head.tree}}), /NATIVE_SOURCE_TREE h1/);
});

test('installed-H1 reuse reads the heap decision from the pinned H1 manifests: none for FIXED_INPUTS.h1 on any Unix host',
  {skip: !fixedObject && 'FIXED_INPUTS.h1 object absent (shallow clone)'}, () => {
  const show = rel => gitOut('show', FIXED_INPUTS.h1 + ':' + rel).stdout;
  const sourcePresent = gitOut('ls-tree', FIXED_INPUTS.h1, '--', 'runtime_shim/cjc_heap_defaults.c').stdout.trim() !== '';
  assert.equal(sourcePresent, false);
  for (const platform of UNIX)
    assert.equal(h1HeapDefaultsBuild({workspaceText: show('cjpm.toml'), packageText: show('packages/cjc/cjpm.toml'), platform, sourcePresent}),
      false, platform);
});
