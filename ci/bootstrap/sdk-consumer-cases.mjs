#!/usr/bin/env zx
// Migrated legacy SDK consumers. All installation goes through the existing
// complete frozen-plan producer/resolver/assembler; native results are retained.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
const {values} = parseArgs({options: {
  suite: {type: 'string'}, output: {type: 'string'}, product: {type: 'string'},
  elf: {type: 'string'}, 'old-elf': {type: 'string', default: '/bin/true'},
  'new-elf': {type: 'string', default: '/bin/echo'}, repeat: {type: 'string', default: '1'},
  filter: {type: 'string'}, 'fixtures-from': {type: 'string'},
  'real-coloured-sdk': {type: 'string'}, 'real-official-sdk': {type: 'string'},
}});
const repeats = Number(values.repeat);
assert.ok(Number.isSafeInteger(repeats) && repeats > 0, '--repeat must be a positive integer');
assert.ok(process.env.SDK_MANIFEST_TEST_ROOT && process.env.SDK_SHAREDBUILD_ENGINE,
  'SDK_MANIFEST_TEST_ROOT and SDK_SHAREDBUILD_ENGINE must name private fixed inputs');
if (values.output) {
  await fs.mkdir(path.resolve(values.output), {recursive: true});
  assert.equal((await fs.readdir(path.resolve(values.output))).length, 0, 'output must be empty');
  process.env.SDK_MANIFEST_TEST_ROOT = path.resolve(values.output);
}
const {fixture: newFixture, command, assemble, observe, good, rejected, entries, nativeChecks, retainPublished,
  publish, verify, here, tuple, cross, readJson, atomicJson, fileDigest} = await import('./fixtures/sdk-consumer-fixture.mjs');
const records = [];
let activeTarget;
const prior = values['fixtures-from'] ? await readJson(path.join(path.resolve(values['fixtures-from']), 'results.json')) : null;
async function fixture(options = {}) {
  if (!prior) return newFixture(options);
  const record = prior.records.find(row => row.name === activeTarget && row.passed);
  assert.ok(record?.evidence, `--fixtures-from requires a successful frozen-plan input for ${activeTarget}`);
  const inputRoot = record.evidence, plan = await readJson(path.join(inputRoot, 'plan.json'));
  assert.equal(plan.role, options.role || 'target', 'replay must preserve the original role');
  for (const [id, requested] of Object.entries(options.parameters || {})) {
    const component = plan.components.find(row => row.id === id);
    for (const [key, value] of Object.entries(requested)) assert.deepEqual(component.config.options.parameters[key], value);
  }
  const sources = Object.fromEntries(['runtime', 'compiler', 'std', 'llvm'].map(name =>
    [name, plan.components.find(row => row.id === (name === 'llvm' ? 'llvm-tools' : name)).source]));
  for (const [name, files] of Object.entries(options.sources || {})) for (const [rel, bytes] of Object.entries(files)) {
    assert.deepEqual(await fs.readFile(path.join(sources[name].repo, rel)), Buffer.from(bytes), 'replay cannot replace the original source input');
  }
  const root = await fs.mkdtemp(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'sdk-replay-'));
  const {buildIdentities} = await import('./sdk-manifest.mjs');
  return {root, inputRoot, replay: true, sources, plan, identities: buildIdentities(plan), planFile: path.join(root, 'plan.json'), out: path.join(root, 'sdk')};
}
const appendMapping = (component, mapping) => {
  if (!component.install.some(row => JSON.stringify(row) === JSON.stringify(mapping))) component.install.push(mapping);
};
async function target(name, body) {
  if (values.filter && values.filter !== name) return;
  const started = new Date().toISOString(); activeTarget = name;
  try {
    const evidence = await body(); records.push({name, executed: true, passed: true, started, evidence});
    console.log(`PASS ASSERT ${name} executed=true N=1 evidence=${evidence}`);
  } catch (error) {
    records.push({name, executed: true, passed: false, started, error: error.stack});
    console.error(`FAIL ASSERT ${name} executed=true ${error.stack}`);
    throw error; // A new failure stops dependent successors; no retry-to-green.
  }
}
const product = values.product || process.env.SDK_BUILD_PRODUCT || path.join(here, 'sdk_build.sh');
async function host(binary, options = {}) {
  const input = binary ? {'fixture-product': await fs.readFile(binary)} : {};
  return fixture({role: 'host', sources: {compiler: input},
    parameters: {compiler: {...(binary ? {copyBinary: true} : {}), ...options}}});
}
async function installedCompiler(f, label) {
  const result = await assemble(f, label, product); good(result);
  const receipt = await readJson(path.join(f.identities.get('compiler').directory, 'output.json'));
  const expected = receipt.files['cjcj-stage1'].sha256;
  await entries(f, expected);
  return expected;
}
async function badPublisher(kind, slot = 'bin/cjc') {
  const f = await host(), source = path.join(f.root, 'bad-source');
  await fs.cp(path.join(f.inputRoot || f.root, 'official'), source, {recursive: true});
  const file = path.join(source, slot); await fs.unlink(file);
  const outside = path.join(f.root, 'outside-compiler');
  await fs.copyFile(values['old-elf'], outside);
  const before = {sha256: await fileDigest(outside), mtimeNs: (await fs.stat(outside, {bigint: true})).mtimeNs.toString()};
  await fs.symlink(kind === 'escape' ? outside : kind === 'cycle' ? '.' : `${path.basename(slot)}-missing`, file);
  const result = await publish(f, source, `${kind}-${path.basename(slot)}`);
  // This is the real source-authentication refusal, before a producer receipt.
  rejected(result, kind === 'escape' ? /SDK source link escapes root/ : kind === 'cycle' ? /SDK source directory cycle/ : /No such file or directory/);
  assert.match(result.stderr, new RegExp(path.basename(slot)));
  assert.deepEqual({sha256: await fileDigest(outside), mtimeNs: (await fs.stat(outside, {bigint: true})).mtimeNs.toString()}, before);
  await assert.rejects(fs.access(f.out));
  await fs.unlink(file); await fs.copyFile(path.join(f.root, 'official', slot), file);
  const restored = await retainPublished(f, source, `${kind}-restored`); assert.ok(restored.lock.source_layout[slot]);
  await installedCompiler(f, `${kind}-restored-assembly`);
  return f.root;
}
async function exeSuite() {
  for (const [name, rel] of [['regular-elf-reaches-ldd', 'bin/cjcj-stage1'], ['symlink-elf-reaches-ldd', 'bin/cjc']]) {
    await target(name, async () => {
      const f = await host(values.elf || '/bin/true'); await installedCompiler(f, 'exe-control');
      await nativeChecks(f, rel); return f.root;
    });
  }
  await target('nonelf-symlink-rejected', async () => {
    const bad = await host(undefined, {nonElf: true}); const result = await assemble(bad, 'nonelf-target', product);
    rejected(result, /rule=EXECUTABLE_FORMAT component=tools.*bin\/cjc/);
    await assert.rejects(fs.access(bad.out)); return bad.root;
  });
  await target('dangling-cjc-rejected', () => badPublisher('dangling'));
  await target('dangling-llc-rejected', () => badPublisher('dangling', 'third_party/llvm/bin/llc'));
}
async function swapSuite() {
  const oldHash = await fileDigest(values['old-elf']), newHash = await fileDigest(values['new-elf']);
  assert.notEqual(oldHash, newHash, 'old and new ELF must differ');
  for (const kind of ['regular', 'symlink']) await target(`${kind}-cjc-replaced`, async () => {
    const f = await host(values['new-elf']), source = path.join(f.root, `${kind}-input`);
    await fs.cp(path.join(f.inputRoot || f.root, 'official'), source, {recursive: true});
    for (const name of ['cjc', 'cjc-frontend']) await fs.unlink(path.join(source, 'bin', name));
    if (kind === 'regular') for (const name of ['cjc', 'cjc-frontend']) await fs.copyFile(values['old-elf'], path.join(source, 'bin', name));
    else {
      await fs.copyFile(values['old-elf'], path.join(source, 'bin/cjcj-stage1'));
      for (const name of ['cjc', 'cjc-frontend']) await fs.symlink('cjcj-stage1', path.join(source, 'bin', name));
    }
    const sealed = await retainPublished(f, source, `${kind}-source`);
    assert.equal(sealed.lock.source_layout['bin/cjc'].sha256, oldHash);
    assert.equal(await installedCompiler(f, `${kind}-swap`), newHash);
    await nativeChecks(f, 'bin/cjc'); return f.root;
  });
  await target('escape-outside-unchanged', () => badPublisher('escape'));
  // The frozen source admission now rejects external compiler inputs. There is
  // no accepted installation in which an external inherited link can survive.
  await target('escape-source-refused-before-install', () => badPublisher('escape'));
  await target('dangling-cjc-early-gate', () => badPublisher('dangling'));
  await target('producer-inside-bin-refused', async () => {
    const f = await host(), sdk = path.join(f.root, 'inside-sdk'), binary = path.join(sdk, 'bin/cjcj-stage1');
    await fs.mkdir(path.dirname(binary), {recursive: true}); await fs.copyFile(values['new-elf'], binary);
    const before = await fileDigest(binary);
    const result = await observe(f, 'inside-producer', ['python3', path.join(here, 'compiler_identity.py'), sdk, '--install', binary]);
    rejected(result, /producer must be outside destination bin/); assert.equal(await fileDigest(binary), before);
    return f.root;
  });
}
async function identitySuite() {
  await target('SDK_SHELL_FRONTEND_TARGET', async () => {
    const f = await host(values.elf); const expected = await installedCompiler(f, 'identity-assembly');
    await nativeChecks(f, 'bin/cjc');
    await atomicJson(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'identity-result.json'), {sdk: f.out, producer: expected, root: f.root});
    return f.root;
  });
}
async function inputLayoutSuite() {
  await target('sdk-build-input-layout', async () => {
    const f = await host(), source = path.join(f.root, 'linker-input');
    await fs.cp(path.join(f.inputRoot || f.root, 'official'), source, {recursive: true});
    const cjc = path.join(source, 'bin/cjc');
    good(await observe(f, 'original-linker-compile', ['cc', path.join(f.sources.compiler.repo, 'alias-tool.c'), '-o', cjc]));
    await fs.symlink('cjc', path.join(source, 'bin/linker'));
    const sealed = await retainPublished(f, source, 'linker-source', [{from: 'bin/linker', to: 'bin/linker'}]);
    await installedCompiler(f, 'linker-assembly');
    const installed = path.join(f.out, 'bin/linker'), original = path.join(source, 'bin/linker');
    const manifest = await readJson(path.join(f.out, 'SDK.manifest.json')), lock = await readJson(path.join(f.out, 'SDK.lock.json'));
    assert.equal(sealed.lock.source_layout['bin/linker'].target, 'cjc');
    assert.equal(sealed.lock.source_layout['bin/linker'].resolved, 'bin/cjc');
    assert.equal((await fs.lstat(installed)).isSymbolicLink(), false);
    assert.equal(await fileDigest(installed), await fileDigest(original));
    assert.equal((await fs.stat(installed)).mode & 0o777, (await fs.stat(original)).mode & 0o555);
    assert.equal(manifest.files['bin/linker'].component, 'official');
    assert.equal(lock.files['bin/linker'].type, 'file');
    assert.equal(lock.files['bin/linker'].sha256, sealed.lock.source_layout['bin/linker'].sha256);
    const inputVersion = await observe(f, 'linker-original-version', [original, '--version']); good(inputVersion);
    const inputDispatch = await observe(f, 'linker-original-dispatch', [original]); good(inputDispatch);
    assert.equal(inputDispatch.stdout, 'argv0=linker physical=cjc\n');
    const installedVersion = await observe(f, 'linker-installed-version', [installed, '--version']); good(installedVersion);
    assert.equal(installedVersion.stdout, inputVersion.stdout);
    const installedDispatch = await observe(f, 'linker-installed-dispatch', [installed]); good(installedDispatch);
    assert.equal(installedDispatch.stdout, 'argv0=linker physical=linker\n');
    await fs.rename(source, `${source}-removed`); await fs.rename(sealed.root, `${sealed.root}-removed`);
    const relocated = `${f.out}-relocated`; await fs.rename(f.out, relocated); f.out = relocated;
    const independent = await observe(f, 'linker-relocated-version', [path.join(f.out, 'bin/linker'), '--version']); good(independent);
    assert.equal(independent.stdout, inputVersion.stdout);
    const dispatch = await observe(f, 'linker-relocated-dispatch', [path.join(f.out, 'bin/linker')]); good(dispatch);
    assert.equal(dispatch.stdout, installedDispatch.stdout);
    good(await verify(f, 'linker-relocated-verifier')); return f.root;
  });
}

async function tupleSuite() {
  // A real-input rehearsal consumes its existing complete frozen plan and
  // original producer receipts. Loose LLVM_TUPLE/HOST_SDK cannot identify one.
  const planPath = process.env.SDK_TUPLE_PLAN;
  if (planPath) {
    await target('tuple-installed-executable', async () => {
      const root = await fs.mkdtemp(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'tuple-real-'));
      const f = {root, plan: await readJson(planPath), planFile: path.join(root, 'plan.json'), out: path.join(root, 'sdk')};
      good(await assemble(f, 'real-tuple', product));
      const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
      for (const name of ['llc', 'opt', 'ld.lld']) {
        const rel = `third_party/llvm/bin/${name}`;
        assert.equal(await fileDigest(path.join(f.out, rel)), manifest.files[rel].sha256);
        assert.ok((await fs.stat(path.join(f.out, rel))).mode & 0o111);
        await nativeChecks(f, rel);
      }
      return root;
    });
    return;
  }
  for (const mode of [0o755, 0o644]) await target(`tuple-installed-executable-input-${mode.toString(8)}`, async () => {
    const f = await fixture({role: 'host', parameters: {'llvm-tools': {toolMode: mode}}});
    const result = await assemble(f, `tuple-mode-${mode.toString(8)}`, product);
    // Modes are sealed producer identity, not assembler permission to change
    // arbitrary receipt bytes. A producer of nonexecutable tools must refuse.
    if (mode === 0o644) {
      assert.notEqual(result.rc, 0);
      assert.doesNotMatch(result.stderr, /FROZEN_PLAN_REQUIRED/);
      assert.match(result.stderr, /EACCES|Permission denied/);
      await assert.rejects(fs.access(f.out));
    } else {
      good(result);
      const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
      for (const name of ['llc', 'opt', 'ld.lld']) {
        const rel = `third_party/llvm/bin/${name}`, file = path.join(f.out, rel);
        assert.equal(await fileDigest(file), manifest.files[rel].sha256);
        assert.equal((await fs.stat(file)).mode & 0o777, mode);
        await nativeChecks(f, rel);
      }
    }
    return f.root;
  });
}
async function pairSuite() {
  for (const layout of ['flat', 'nested', 'nested-archive', 'nested-static']) for (const aliases of [[], ['libboundscheck.so'], ['libcangjie-runtime.so', 'libboundscheck.so']]) {
    await target(`${layout}-selected-pinned-pair-${aliases.length}`, async () => {
      const f = await fixture({runtimeLayout: layout, sources: {runtime: {'inherited.c': 'int inherited_library;\n'}}});
      const runtime = f.plan.components.find(row => row.id === 'runtime');
      for (const name of aliases) appendMapping(runtime, {from: layout === 'flat' ? name : `install/runtime/lib/${tuple}/${name}`, to: `lib/${tuple}/${name}`});
      good(await assemble(f, `pair-${layout}-${aliases.length}`, product));
      const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
      const expected = {};
      for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) {
        const row = manifest.files[`runtime/lib/${tuple}/${name}`];
        assert.equal(row.component, 'runtime');
        assert.equal(row.buildId, manifest.components.runtime.buildId);
        expected[name] = row.sha256;
        assert.equal(await fileDigest(path.join(f.out, `runtime/lib/${tuple}/${name}`)), row.sha256);
        assert.equal(await fs.stat(path.join(f.out, `lib/${tuple}/${name}`)).then(() => true, () => false), aliases.includes(name));
      }
      const argv = ['ld', '-shared', '-t', `-L${f.out}/lib/${tuple}`, `-L${f.out}/runtime/lib/${tuple}`,
        '-l:libcangjie-runtime.so', '-lboundscheck', '-o', path.join(f.root, 'linked.so')];
      const link = await observe(f, 'link-installed-pair', argv); good(link);
      const selected = {};
      for (const line of link.stdout.trim().split('\n')) {
        const file = line.trim(), name = path.basename(file);
        if (name in expected) selected[name] = {file, sha256: await fileDigest(file)};
      }
      for (const name of Object.keys(expected)) assert.equal(selected[name]?.sha256, expected[name]);
      const archive = manifest.files[`lib/${tuple}/libcangjie-runtime.a`];
      assert.equal(archive.component, 'runtime');
      assert.equal(await fileDigest(path.join(f.out, `lib/${tuple}/libcangjie-runtime.a`)), archive.sha256);
      await atomicJson(path.join(f.root, 'selected-pair.json'), {selected, expected, archive});
      return f.root;
    });
  }
}
async function stdSuite() {
  const packages = ['core', 'sort', 'collection.concurrentFFI'];
  for (const role of ['host', 'target']) for (const missing of ['', 'lib', 'runtime/lib']) {
    await target(`${role}-std-${missing.replaceAll('/', '_') || 'complete'}`, async () => {
      const omit = missing ? `${missing}/${tuple}/libcangjie-std-sort.${missing === 'lib' ? 'a' : 'so'}` : undefined;
      const f = await fixture({role, parameters: {std: {packages, includeFfi: true, ...(omit ? {omit} : {})}},
        prepareOfficial: async ({official}) => {
          for (const name of packages.slice(1)) for (const [prefix, ext] of [['lib', 'a'], ['runtime/lib', 'so']]) {
            await fs.copyFile(path.join(official, prefix, tuple, `libcangjie-std-core.${ext}`),
              path.join(official, prefix, tuple, `libcangjie-std-${name}.${ext}`));
          }
          await fs.copyFile(path.join(official, 'runtime/lib', tuple, 'libcangjie-std-core.so'), path.join(official, 'lib/libstdFFI.so'));
          for (const tpl of [tuple, cross]) for (const [prefix, ext] of [['lib', 'a'], ['runtime/lib', 'so']]) {
            await fs.mkdir(path.join(official, prefix, tpl), {recursive: true});
            await fs.copyFile(path.join(official, prefix, tuple, `libcangjie-std-core.${ext}`), path.join(official, prefix, tpl, `libkeep.${ext}`));
          }
        }});
      const official = f.plan.components.find(row => row.id === 'official');
      for (const tpl of [tuple, cross]) for (const [prefix, ext] of [['lib', 'a'], ['runtime/lib', 'so']]) {
        const rel = `${prefix}/${tpl}/libkeep.${ext}`; appendMapping(official, {from: rel, to: rel});
      }
      // Explicit frozen leaf mappings require every declared package before
      // assembly. This preserves complete-std refusal without deriving an
      // expectation from whichever producer outputs survived the build.
      const std = f.plan.components.find(row => row.id === 'std');
      std.install = [];
      for (const name of packages) for (const [prefix, ext] of [['lib', 'a'], ['runtime/lib', 'so']]) {
        const rel = `${prefix}/${tuple}/libcangjie-std-${name}.${ext}`;
        std.install.push({from: rel, to: rel});
      }
      for (const rel of ['lib/libstdFFI.so', 'std-producer.json', 'modules']) std.install.push({from: rel, to: rel});
      f.out = path.join(f.root, 'sdk [output]');
      const result = await assemble(f, `std-${role}-${missing.replaceAll('/', '_') || 'complete'}`, product);
      if (missing) {
        rejected(result, /rule=MISSING_ARTIFACT component=std/); assert.match(result.stderr, new RegExp(omit.replaceAll('.', '\\.')));
        await assert.rejects(fs.access(f.out));
      } else {
        good(result);
        const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
        const receipt = await readJson(path.join(f.identities.get('std').directory, 'output.json'));
        const installed = Object.fromEntries(Object.entries(manifest.files).filter(([, row]) => row.component === 'std').map(([rel, row]) => [rel, row.sha256]));
        const expected = Object.fromEntries(Object.entries(receipt.files).map(([rel, row]) => [rel, row.sha256]));
        assert.deepEqual(installed, expected, 'all std output entities and only that frozen producer are installed');
        for (const [rel, digest] of Object.entries(expected)) assert.equal(await fileDigest(path.join(f.out, rel)), digest);
        for (const tpl of [tuple, cross]) for (const [prefix, ext] of [['lib', 'a'], ['runtime/lib', 'so']]) {
          const rel = `${prefix}/${tpl}/libkeep.${ext}`;
          assert.equal(manifest.files[rel].component, 'official');
          assert.equal(await fileDigest(path.join(f.out, rel)), (await readJson(official.source.lock)).files[rel].sha256);
        }
        for (const name of ['libcangjie-runtime.so', 'libboundscheck.so']) assert.equal(manifest.files[`runtime/lib/${tuple}/${name}`].component, 'runtime');
        assert.ok(installed['lib/libstdFFI.so']);
        assert.ok(!Object.keys(manifest.files).some(rel => rel.includes(`/${cross}/libcangjie-std`) || /libcangjie-std\.(a|so)$/.test(rel)));
      }
      return f.root;
    });
  }
}

const runtimeSymbols = {
  mask: 'int g_cjLoadBadMask;',
  both: 'int g_cjLoadBadMask; int g_cjLoadBadMaskOffset; int g_cjLoadShift; int future_colour_export; int unrelated;',
  'shift-undefined': 'extern int g_cjLoadShift; int *reference=&g_cjLoadShift;',
  'future-undefined': 'extern int future_colour_export; int *reference=&future_colour_export;',
  'common-undefined': 'extern int unrelated; int *reference=&unrelated;',
  offset: 'int g_cjLoadBadMaskOffset;', none: 'int unrelated;',
  'offset-undefined': 'extern int g_cjLoadBadMaskOffset; int *reference=&g_cjLoadBadMaskOffset;',
  'prefix-undefined': 'extern int g_cjLoadBadMaskExtra; int *reference=&g_cjLoadBadMaskExtra;',
  undefined: 'extern int g_cjLoadBadMask; int *reference=&g_cjLoadBadMask;',
};
const runtimeSource = body => '#ifndef CJRT_SHA\n#define CJRT_SHA "official"\n#endif\nconst char provenance[]="CJRT-COMMIT:" CJRT_SHA; int official_symbol=1;\n' + body + '\n';
async function runtimeFixture(variant, role, stdVariant, order = [tuple]) {
  const versioned = variant.endsWith('-versioned'), kind = variant.replace(/-versioned$/, '');
  const std = stdVariant === 'version-reference' ? runtimeSymbols.undefined : runtimeSymbols[stdVariant];
  assert.ok(runtimeSymbols[kind] && std);
  const f = await fixture({role, colourReference: 'reference.c', sources: {
    runtime: {'runtime.c': runtimeSource(runtimeSymbols[kind]),
      'host.c': runtimeSource('int unrelated;'), 'reference.c': runtimeSource(runtimeSymbols.both),
      'versions.map': 'CANGJIE { global: *; };\n'},
    std: {'std.c': std + '\n', ...(stdVariant === 'version-reference' ? {'std-static.c':
      'extern int mask; int *reference=&mask;\n__asm__(".symver mask,g_cjLoadBadMask@CANGJIE");\n'} : {})},
  }, parameters: {runtime: {...(versioned ? {versioned: true} : {})},
    std: {...(stdVariant === 'version-reference' ? {staticSource: 'std-static.c'} : {})}},
  prepareOfficial: async ({official, sources}) => {
    // The host comparison is independent of the selected target. For a host
    // test it is the declared host runtime itself, as in the original cases.
    if (role === 'target') good(await command(['cc', '-shared', '-fPIC', path.join(sources.runtime.repo, 'host.c'),
      '-o', path.join(official, `runtime/lib/${tuple}/libcangjie-runtime.so`)]));
    for (const tpl of order) if (tpl !== tuple) {
      const target = path.join(official, 'runtime/lib', tpl, 'libcangjie-runtime.so');
      await fs.mkdir(path.dirname(target), {recursive: true});
      good(await command(['cc', '-shared', '-fPIC', path.join(sources.runtime.repo, 'host.c'), '-o', target]));
    }
  }});
  const official = f.plan.components.find(row => row.id === 'official');
  for (const tpl of order) if (tpl !== tuple) {
    const rel = `runtime/lib/${tpl}/libcangjie-runtime.so`; appendMapping(official, {from: rel, to: rel});
  }
  return f;
}
async function runtimeCase(name, order, variant, role, stdVariant, expected, diagnostic) {
  await target(name, async () => {
    const f = await runtimeFixture(variant, role, stdVariant, order);
    if (name === 'missing-target') {
      f.plan.components.find(row => row.id === 'runtime').install = [{from: `install/lib/${tuple}/libcangjie-runtime.a`, to: `lib/${tuple}/libcangjie-runtime.a`}];
    }
    if (name === 'source-mismatch') {
      // The frozen mapping declares the source's wrong tuple explicitly. It
      // must not discover/choose a different tuple from directory order.
      f.plan.components.find(row => row.id === 'runtime').install = [{from: `install/runtime/lib/${cross}`, to: `runtime/lib/${tuple}`}];
    }
    const result = await assemble(f, `runtime-${name}`, product);
    if (expected === 0) {
      good(result);
      const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
      const receipt = await readJson(path.join(f.identities.get('runtime').directory, 'output.json'));
      const rel = `runtime/lib/${tuple}/libcangjie-runtime.so`;
      assert.equal(await fileDigest(path.join(f.out, rel)), receipt.files[`install/${rel}`].sha256);
      assert.equal(manifest.files[rel].component, 'runtime');
      for (const tpl of order) if (tpl !== tuple) {
        const other = `runtime/lib/${tpl}/libcangjie-runtime.so`;
        assert.equal(manifest.files[other].component, 'official');
        assert.equal(await fileDigest(path.join(f.out, other)), (await readJson(f.plan.components[0].source.lock)).files[other].sha256);
      }
      good(await verify(f, `${name}-independent-verifier`));
      if (name.startsWith('pair-verify-host')) await nativeChecks(f, 'tools/bin/cjpm');
    } else {
      assert.notEqual(result.rc, 0, result.stdout + result.stderr);
      assert.doesNotMatch(result.stderr, /FROZEN_PLAN_REQUIRED/);
      assert.match(result.stderr, diagnostic);
      if (/STD-RUNTIME-COLOUR-MISMATCH/.test(diagnostic.source)) {
        assert.match(result.stderr, /std_sha256=[a-f0-9]{64}/);
        assert.match(result.stderr, /std_source=resolved-manifest/);
      }
      await assert.rejects(fs.access(f.out));
    }
    return f.root;
  });
}
async function runtimeSuite() {
  for (const [name, order] of [['windows-first', [cross, tuple]], ['linux-first', [tuple, cross]],
    ['verify-windows-first', [cross, tuple]], ['verify-linux-first', [tuple, cross]], ['single-tuple-control', [tuple]]]) {
    await runtimeCase(name, order, 'mask', 'target', 'undefined', 0);
  }
  await runtimeCase('missing-target', [cross], 'mask', 'target', 'undefined', 1, /rule=RUNTIME_PIN.*target runtime libcangjie-runtime.so missing/);
  await runtimeCase('source-mismatch', [tuple], 'mask', 'target', 'undefined', 1, /rule=MISSING_ARTIFACT component=runtime.*windows_x86_64_cjnative/);
  for (const variant of ['both', 'both-versioned', 'none', 'offset', 'offset-versioned', 'undefined']) for (const role of ['host', 'target']) {
    const coloured = variant.startsWith('both'), expected = coloured === (role === 'target') ? 0 : 1;
    await runtimeCase(`${variant}-${role}`, [tuple], variant, role, coloured ? 'undefined' : 'none', expected,
      role === 'target' ? /BOOTSTRAP_SDK_RUNTIME_COLOUR_PAIR_MISMATCH/ : /empty colour-only runtime export set|rule=RUNTIME_COLOUR/);
  }
  const pairs = {
    'pair-shift-target': ['both', 'target', 'shift-undefined', 0],
    'pair-shift-host': ['none', 'host', 'shift-undefined', 1],
    'pair-future-target': ['both', 'target', 'future-undefined', 0],
    'pair-common-target': ['both', 'target', 'common-undefined', 1],
    'pair-common-host': ['none', 'host', 'common-undefined', 0],
    'pair-mask-target': ['mask', 'target', 'undefined', 0],
    'pair-version-target': ['mask', 'target', 'version-reference', 0],
    'pair-offset-target': ['mask', 'target', 'offset-undefined', 0],
    'pair-official-host': ['none', 'host', 'none', 0],
    'pair-official-target': ['mask', 'target', 'none', 1],
    'pair-coloured-host': ['none', 'host', 'undefined', 1],
    'pair-offset-host': ['none', 'host', 'offset-undefined', 1],
    'pair-prefix-target': ['mask', 'target', 'prefix-undefined', 1],
    'pair-prefix-host': ['none', 'host', 'prefix-undefined', 0],
    'pair-definition-target': ['mask', 'target', 'mask', 1],
    'pair-install-target': ['mask', 'target', 'offset-undefined', 0],
    'pair-install-official': ['mask', 'target', 'none', 1],
    'pair-verify-host': ['mask', 'target', 'undefined', 0],
    'pair-verify-host-mismatch': ['mask', 'target', 'none', 1],
  };
  for (const [name, [variant, role, stdVariant, expected]] of Object.entries(pairs)) {
    await runtimeCase(name, [tuple], variant, role, stdVariant, expected, /STD-RUNTIME-COLOUR-MISMATCH/);
  }
  // Exercise the same std predicate CLI used by the real stage producer, on
  // the actual producer archives. Symbol-boundary observations remain separate
  // from an SDK build marker and cover definitions, undefined/versioned names.
  for (const [variant, expected] of [['undefined', '1'], ['offset-undefined', '1'], ['version-reference', '1'],
    ['none', '0'], ['prefix-undefined', '0'], ['mask', '0'], ['shift-undefined', '1'], ['future-undefined', '1'], ['common-undefined', '0']]) {
    await target(`std-cli-${variant}`, async () => {
      const f = await runtimeFixture('both', 'target', variant);
      await atomicJson(f.planFile, f.plan);
      const resolved = await observe(f, `std-cli-${variant}-producer`, [process.execPath, path.join(here, 'toolchain-sdk.mjs'), '--plan', f.planFile, '--resolve']);
      good(resolved);
      const {buildIdentities} = await import('./sdk-manifest.mjs');
      const archive = path.join(buildIdentities(f.plan).get('std').directory, 'artifacts/lib', tuple, 'libcangjie-std-core.a');
      const result = await observe(f, `std-cli-${variant}`, ['python3', path.join(here, 'std_runtime_colour.py'), '--std-colour', archive,
        '--colour-runtime', f.plan.verification.colourRuntime.path, '--host-runtime', f.plan.verification.hostRuntime.path]);
      good(result); assert.equal(result.stdout.trim(), expected); return f.root;
    });
  }
  assert.equal(Boolean(values['real-coloured-sdk']), Boolean(values['real-official-sdk']), 'both real SDK paths are required together');
  if (values['real-coloured-sdk']) {
    // Retained real SDKs already carry their frozen plan and original manifest.
    // This is a predicate rehearsal only; no production SDK is built here.
    for (const [name, runtimeSdk, stdSdk, expected] of [
      ['real-coloured', values['real-coloured-sdk'], values['real-coloured-sdk'], 0],
      ['real-official', values['real-official-sdk'], values['real-official-sdk'], 0],
      ['real-official-std', values['real-coloured-sdk'], values['real-official-sdk'], 1],
      ['real-coloured-std', values['real-official-sdk'], values['real-coloured-sdk'], 1],
    ]) await target(name, async () => {
      const root = await fs.mkdtemp(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'real-runtime-pair-'));
      const result = await observe({root}, name, ['python3', path.join(here, 'std_runtime_colour.py'),
        '--runtime', path.join(runtimeSdk, `runtime/lib/${tuple}/libcangjie-runtime.so`),
        '--std', path.join(stdSdk, `lib/${tuple}/libcangjie-std-core.a`), '--source', stdSdk,
        '--colour-runtime', path.join(values['real-coloured-sdk'], `runtime/lib/${tuple}/libcangjie-runtime.so`),
        '--host-runtime', path.join(values['real-official-sdk'], `runtime/lib/${tuple}/libcangjie-runtime.so`)]);
      assert.equal(result.rc, expected); if (expected) assert.match(result.stderr, /STD-RUNTIME-COLOUR-MISMATCH/);
      return root;
    });
  }
}
const suites = {exe: exeSuite, swap: swapSuite, identity: identitySuite, 'input-layout': inputLayoutSuite, tuple: tupleSuite, pair: pairSuite, std: stdSuite, runtime: runtimeSuite};
try {
  assert.ok(suites[values.suite], `unknown suite: ${values.suite}`);
  for (let i = 0; i < repeats; ++i) await suites[values.suite]();
  assert.ok(records.length, 'the assertion selection must execute at least one target');
} catch (error) { console.error(error.stack); process.exitCode = 1; }
await atomicJson(path.join(process.env.SDK_MANIFEST_TEST_ROOT, 'results.json'), {suite: values.suite, records});
