import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import {platformizeCjcToml} from '../sdk/producers/platform_matrix/link_option.mjs';

const read = file => fs.readFile(new URL('../../' + file, import.meta.url), 'utf8');
const workspace = await read('cjpm.toml');
const cjc = await read('packages/cjc/cjpm.toml');
const config = 'runtime_shim/cjc_runtime_config.o';
function options(text) {
  const match = text.match(/^\s*link-option\s*=\s*"([^"]*)"/m);
  assert.ok(match, 'actual manifest must declare link-option');
  return match[1].split(/\s+/).filter(Boolean);
}

for (const platform of ['linux', 'darwin', 'win32']) {
  test(`${platform}: platform rewrite and repeated SDK rewrite retain one workspace config`, () => {
    let manifest = cjc;
    for (const sdk of ['/sdk/seed', '/sdk/final', '/sdk/seed']) {
      manifest = platformizeCjcToml(manifest, platform, sdk, 'llvm.rsp', 'crt.rsp');
      const combined = [...options(workspace), ...options(manifest)];
      console.log(`CONFIG_ONCE_ASSERT_REACHED platform=${platform} sdk=${sdk}`);
      assert.equal(combined.filter(x => x === config).length, 1,
        'workspace + generated package must link config exactly once');
      assert.equal(combined.filter(x => x === 'runtime_shim/cjselfhost_llvmshim.o').length, 1);
      if (platform === 'darwin') {
        assert.ok(combined.includes(sdk + '/third_party/llvm/lib/libLLVM.dylib'));
        assert.ok(combined.includes('-headerpad_max_install_names'));
      } else if (platform === 'win32') {
        assert.ok(combined.includes('@llvm.rsp'));
        assert.ok(combined.includes('@crt.rsp'));
        assert.ok(combined.includes('--stack=0x4000000'));
      } else assert.equal(manifest, cjc);
    }
  });
}

test('non-cjc workspace consumers retain the shared config dependency', async () => {
  // Enumerate the actual workspace membership, including test roots, so moving
  // the object back to cjc alone cannot satisfy this independent control.
  const members = workspace.match(/members\s*=\s*\[([\s\S]*?)\]/)[1];
  const paths = [...members.matchAll(/"(packages\/[^\"]+)"/g)].map(x => x[1]);
  assert.ok(paths.includes('packages/utils'));
  assert.ok(paths.includes('packages/parse'));
  assert.ok(paths.includes('packages/compiler_unittest'));
  for (const member of paths.filter(x => x !== 'packages/cjc')) {
    const combined = [...options(workspace), ...options(await read(member + '/cjpm.toml'))];
    assert.equal(combined.filter(x => x === config).length, 1, member);
  }
  console.log(`NON_CJC_CONFIG_ASSERT_REACHED members=${paths.length - 1}`);
});

// packages/cjc/cjpm.toml: ELF inputs per Linux target, Mach-O inputs per Darwin target.
import {cjcLinkContractProblems, effectiveLinkOptions, DARWIN_CJC_LINK} from '../../ci/bootstrap/cjc-link-sections.mjs';
import {assembleCjcLinkOption} from '../sdk/producers/platform_matrix/link_option.mjs';
test('cjc manifest: Linux effective link equals the ELF set, Darwin carries the Mach-O set', () => {
  assert.deepEqual(cjcLinkContractProblems(cjc), []);
  const darwin = assembleCjcLinkOption('darwin', '${CANGJIE_HOME}', '').split(' ');
  assert.deepEqual([...DARWIN_CJC_LINK].sort(), [...darwin].map(x => x.replace('${CANGJIE_HOME}/third_party/llvm/lib/libLLVM.dylib',
    '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM.dylib')).sort());
  assert.deepEqual(effectiveLinkOptions(cjc, 'windows_x86_64'), ['runtime_shim/cjselfhost_llvmshim.o']);
});
test('red cut: global ELF options or a missing Darwin section are refused precisely', () => {
  const once = (text, from, to) => { assert.equal(text.split(from).length, 2, from); return text.replace(from, to); };
  const globalElf = once(cjc, '  link-option = "runtime_shim/cjselfhost_llvmshim.o"',
    '  link-option = "--export-dynamic runtime_shim/cjselfhost_llvmshim.o ${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so -lstdc++"');
  const problems = cjcLinkContractProblems(globalElf);
  assert.ok(problems.includes('global ELF link option --export-dynamic'), problems.join('\n'));
  assert.ok(problems.includes('darwin_aarch64 link differs from the Mach-O option set'));
  assert.ok(problems.includes('windows_x86_64 link carries ELF/Mach-O options'));
  const noDarwin = once(cjc, '[target.x86_64-apple-darwin]', '[target.x86_64-apple-darwin-disabled]');
  assert.deepEqual(cjcLinkContractProblems(noDarwin), ['darwin_x86_64 lacks its target section']);
  const noLinux = once(cjc, ' -lstdc++ runtime_shim/cjc_heap_defaults.o --wrap=CJ_MRT_CjRuntimeInit --wrap=CJ_MRT_CjRuntimeInitWithConfigV1"\n\n[target.aarch64',
    ' runtime_shim/cjc_heap_defaults.o --wrap=CJ_MRT_CjRuntimeInit --wrap=CJ_MRT_CjRuntimeInitWithConfigV1"\n\n[target.aarch64');
  assert.deepEqual(cjcLinkContractProblems(noLinux), ['linux_x86_64 link differs from the ELF option set']);
});
test('darwin platform rewrite links the Mach-O inputs exactly once', () => {
  let manifest = cjc;
  for (const sdk of ['/sdk/seed', '/sdk/final']) {
    manifest = platformizeCjcToml(manifest, 'darwin', sdk);
    const combined = effectiveLinkOptions(manifest, 'darwin_aarch64');
    assert.equal(combined.filter(x => x.endsWith('libLLVM.dylib')).length, 1);
    assert.equal(combined.filter(x => x === 'runtime_shim/cjselfhost_llvmshim.o').length, 1);
    assert.ok(combined.includes(sdk + '/third_party/llvm/lib/libLLVM.dylib'));
  }
});
