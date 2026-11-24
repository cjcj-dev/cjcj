// phase=prepare: five native hosts, both artifact families, no route to publish,
// and native-inputs roots that bind their real installations and provenance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import crypto from 'node:crypto';
import {PREPARE_HOSTS, PROVENANCE_KEYS, assembleNativeInputs, prepareProvenance, prepareWorkflowProblems,
  checkSuperbuildInstall, installLlvm, installAst, componentCommits, prepareComponentProblems, installHost, prepareHostVersion,
  packNativeInputs, compilerSource, PREPARE_LLVM_TOOLS, PREPARE_AST_STD_HEADERS, PREPARE_PYTHON_RECORD, nativePairSelection, installHle, hleCjbindAsset, HLE_CJBIND, HLE_CJBIND_SOURCE_BUILD, hleCjbindSource, PREPARE_SHIM_OBJECT} from './prepare_native_inputs.mjs';
import {configureHleInput, readHleDependencies} from '../../../../ci/bootstrap/hle-input.mjs';
import {installHleDependencies} from '../../../srcbuild/hle-dependencies.mjs';
import {readInstalledNativeShim} from '../../../../ci/bootstrap/native-shim-inputs.mjs';
import {unpackNativeArtifact} from '../../../../ci/bootstrap/native-artifact-archive.mjs';
import {preparePython, buildPrepareLlvm, llvmConfigureArgs, buildPrepareShim, shimRequiredSymbols, shimSymbolProblems, PREPARE_LLVM_TARGETS,
  llvmLibrarySymbolProblems, lldbPythonArgs, PREPARE_PYTHON, pythonCacheConfiguration, lldbPythonBuildPackage,
  compilerRtLibraries, compilerRtTargets, compilerRtArgs, PREPARE_COMPILER_RT_TRIPLES} from './build_prepare_llvm.mjs';
import {copyOutputs} from '../../../../ci/bootstrap/sdk-flow.mjs';
import {selectedStdAst} from '../../../../ci/bootstrap/sdk-std-resume.mjs';
import {createBootstrapTargets, FIXED_INPUTS, nativeTargetLibraryExcludes} from '../../../../ci/bootstrap/sdk-targets.mjs';
import {execFileSync, spawnSync} from 'node:child_process';
import {preserveNativePythonInput} from '../../../../ci/bootstrap/native-cjdb-job.mjs';
import {pythonSourceInputs} from '../../../../ci/bootstrap/sdk-cjdb-python.mjs';
import {installedInputs} from '../srcbuild/lib/installed-inputs.mjs';
import {nativeInstallationLocations} from '../../../../ci/bootstrap/native-installation-locations.mjs';
import {readInstalledNativeAst} from '../../../../ci/bootstrap/installed-native-ast.mjs';
import {sdkPlatform, stdxChirMembers} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {rejectPrivateTools} from '../../../../ci/bootstrap/deploy-native-tools.mjs';
import {load as loadYaml} from '../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {sourceBuildCells} from '../../../lib/targets.mjs';

const root = path.resolve(import.meta.dirname, '../../../..');
const read = name => fs.readFileSync(path.join(root, '.github/workflows', name + '.yml'), 'utf8');
const real = () => ({release: read('release'), prepare: read('prepare'), sdkBuild: read('sdk-build'), target: read('sdk-build-target')});
const once = (text, from, to) => { assert.equal(text.split(from).length, 2, from); return text.replace(from, to); };

test('the real workflows wire the five-host prepare path without a route to publish', () => {
  assert.deepEqual(prepareWorkflowProblems(real()), []);
  assert.deepEqual(PREPARE_HOSTS.map(row => row.target), ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64']);
  for (const cell of sourceBuildCells()) {
    const host = PREPARE_HOSTS.find(row => row.target === cell.target);
    assert.ok(host, cell.target);
    assert.equal(host.runner, cell.runner, `${cell.target} runner differs from the repository source matrix`);
    assert.equal(host.llvm_platform, cell.llvm_platform);
  }
});

test('red cut: dropping one native host from prepare-native is rejected', () => {
  const w = real();
  w.prepare = once(w.prepare, '          - target: darwin-x64\n            llvm_platform: darwin_x86_64\n            runner: macos-15-intel\n', '');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native lacks host darwin-x64|darwin_x86_64|macos-15-intel'));
});

test('red cut: a prepare host on a foreign runner is rejected', () => {
  const w = real();
  w.prepare = once(w.prepare, '            llvm_platform: windows_x86_64\n            runner: windows-2025\n',
    '            llvm_platform: windows_x86_64\n            runner: ubuntu-24.04\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native lacks host windows-x64|windows_x86_64|windows-2025'));
});

test('red cut: a publish route into prepare.yml or a prepare route back into release.yml is rejected', () => {
  const w = real();
  w.prepare = once(w.prepare, '  prepare-srcbuild-linux-x64:\n', '  publish:\n    needs: prepare-native\n    runs-on: ubuntu-24.04\n    steps:\n      - run: true\n\n  prepare-srcbuild-linux-x64:\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare.yml: unexpected job publish'), JSON.stringify(prepareWorkflowProblems(w)));
  const v = real();
  v.release = once(v.release, '    if: ${{ !inputs.dry_run }}\n', "    if: inputs.phase == 'publish' && !inputs.dry_run\n");
  assert.ok(prepareWorkflowProblems(v).includes('release still reads inputs.phase; prepare lives in prepare.yml'));
  const t = real();
  t.target = once(t.target, '    if: inputs.llvm_tools_only != true\n', '    if: inputs.llvm_tools_only != true && inputs.prepare_native != true\n');
  assert.ok(prepareWorkflowProblems(t).includes('sdk-build-target.yml plan still reads prepare_native'));
});

test('red cut: the same-run linux-x64 source build must consume this run\'s native inputs', () => {
  const w = real();
  w.prepare = once(w.prepare, '      native_inputs_artifact: native-inputs\n      native_inputs_run_id: ${{ github.run_id }}\n',
    '      native_inputs_artifact: native-inputs\n      native_inputs_run_id: ${{ inputs.native_inputs_run_id }}\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-srcbuild-linux-x64 native_inputs_run_id must be ${{ github.run_id }}'));
});

test('red cut: prepare-native without one artifact family is rejected', () => {
  const w = real();
  w.prepare = once(w.prepare, '          name: native-runtime-install-${{ matrix.llvm_platform }}\n', '          name: native-runtime-install\n');
  assert.ok(prepareWorkflowProblems(w).includes('prepare-native does not upload native-runtime-install-${{ matrix.llvm_platform }}'));
});

const commit = c => c.repeat(40);
// A host root as install-host leaves it: the SDK tree, its original archive
// file and the HOST-INPUT.json record that binds archive name, size and digest.
function putHost(dir, platform, version = '1.1.0') {
  const native = sdkPlatform(platform), archive = `cangjie-sdk-fixture-${version}.tar.gz`;
  fs.mkdirSync(path.join(dir, 'host/bin'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'host/bin/cjc' + native.exe), 'host');
  fs.mkdirSync(path.join(dir, 'host-archive'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'host-archive', archive), 'original archive bytes');
  const bytes = fs.readFileSync(path.join(dir, 'host-archive', archive));
  fs.writeFileSync(path.join(dir, 'HOST-INPUT.json'), JSON.stringify({schema: 'cjcj-prepare-host-v1', platform, version, install: 'host',
    archive: {file: `host-archive/${archive}`, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), size: bytes.length}}));
}
const env = {GITHUB_SHA: commit('a'), GITHUB_RUN_ID: '4242', GITHUB_RUN_ATTEMPT: '1',
  CJCJ_NATIVE_LLVM_REF: commit('b'), CJCJ_NATIVE_RUNTIME_REF: commit('c')};
const pins = {COMPILER_REF: commit('d'), TOOLS_REF: commit('e'), STDX_REF: commit('f')};
function inputs(t, {darwin = false, skip, hostTarget} = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-inputs-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), body); };
  putHost(dir, PREPARE_HOSTS.find(h => h.target === (hostTarget || 'linux-aarch64')).llvm_platform);
  for (const [name, file] of [['llvm', 'BUILD-INPUTS.json'], ['runtime', 'NATIVE-INPUTS.json'], ['ast', 'BUILD-INPUTS.json']])
    if (name !== skip) put(`${name}/${file}`, JSON.stringify({configuration: {name}, ...(name === 'llvm' && skip !== 'shim' ? {nativeShim: {}} : {})}));
  if (skip !== 'hle') put('hle/hle-dependencies.json', '{}');
  if (darwin) for (const rel of ['ts/src/sharedbuild/cjcj-stage1.mjs', 'ts/src/sharedbuild/stage1-transform.mjs']) put('adapter/' + rel, '//');
  return dir;
}

test('assemble binds the real installations and every provenance identity', t => {
  const dir = inputs(t);
  const {locations, record} = assembleNativeInputs({root: dir, target: 'linux-aarch64', hostVersion: '1.1.0', env, pins});
  assert.equal(locations.platform, 'linux_aarch64');
  assert.deepEqual(locations.host, {install: 'host', archive: 'host-archive/cangjie-sdk-fixture-1.1.0.tar.gz', version: '1.1.0'});
  assert.deepEqual(Object.keys(locations.installations), ['llvm', 'runtime', 'ast', 'shim']);
  assert.deepEqual(locations.installations.shim, {install: 'llvm'});
  assert.equal(locations.hleDependencies, 'hle/hle-dependencies.json');
  assert.deepEqual(locations.tools, {});
  for (const key of PROVENANCE_KEYS) assert.ok(record[key], key);
  assert.equal(record.tools_ref, pins.TOOLS_REF);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'locations.json'))), locations);
});

test('assemble fails closed on a missing installation, adapter or identity', t => {
  assert.throws(() => assembleNativeInputs({root: inputs(t, {skip: 'ast', hostTarget: 'linux-x64'}), target: 'linux-x64', env, pins}),
    /NATIVE_INPUTS_COMPONENT_MISSING ast/);
  assert.throws(() => assembleNativeInputs({root: inputs(t, {skip: 'hle', hostTarget: 'linux-x64'}), target: 'linux-x64', env, pins}),
    /NATIVE_INPUTS_COMPONENT_MISSING hle/);
  assert.throws(() => assembleNativeInputs({root: inputs(t, {skip: 'shim', hostTarget: 'linux-x64'}), target: 'linux-x64', env, pins}),
    /NATIVE_INPUTS_COMPONENT_MISSING shim/);
  for (const target of ['windows-x64', 'darwin-arm64', 'linux-x64'])
    assert.throws(() => assembleNativeInputs({root: inputs(t, {darwin: true, hostTarget: target}), target, env, pins}),
      /NATIVE_TOOLS_ADAPTER_UNEXPECTED/);
  assert.throws(() => prepareProvenance({...env, CJCJ_NATIVE_RUNTIME_REF: 'main'}, pins), /PREPARE_PROVENANCE native_runtime_ref/);
  assert.throws(() => assembleNativeInputs({root: inputs(t), target: 'freebsd-x64', env, pins}), /PREPARE_HOST_UNKNOWN/);
  const darwin = assembleNativeInputs({root: inputs(t, {hostTarget: 'darwin-x64'}), target: 'darwin-x64', env, pins});
  assert.deepEqual(darwin.locations.tools, {});
});

// ---- N/LLVM + AST producers on all five hosts (ruling 1) ----
const job = text => loadYaml(text).jobs['prepare-native'];
test('every prepare host runs its N/LLVM and AST producer and installs both', () => {
  assert.deepEqual(prepareComponentProblems(job(read('prepare')).steps), []);
});
test('red cut: dropping one host family\'s N/LLVM or AST step names exactly that host and component', () => {
  const entry='prepare_native_superbuild.mjs "${{ matrix.target }}"';
  const step='      - name: Install N/LLVM and AST into the native input root\n';
  const cuts = [
    ...['Linux','macOS','Windows'].map(os=>[step,step+`        if: runner.os != '${os}'\n`,
      PREPARE_HOSTS.filter(h=>(h.target.startsWith('darwin')?'macOS':h.target.startsWith('windows')?'Windows':'Linux')===os)
        .map(h=>`${h.target} lacks native producer ${entry}`)]),
    ...[entry,'git -C compiler checkout','srcbuild_git_checkout_skip_zone_identifier flatbuffers'].map(marker=>[marker,'cut-native-source',
      PREPARE_HOSTS.map(h=>`${h.target} lacks native producer ${marker}`)]),
    ['prepare_native_inputs.mjs install-hle\n','prepare_native_inputs.mjs echo-hle\n',
      PREPARE_HOSTS.map(h=>`${h.target} lacks hle producer prepare_native_inputs.mjs install-hle`)],
  ];
  for (const [from, to, want] of cuts) {
    const target=read('prepare'), start=target.indexOf('  prepare-native:');
    const cutTarget=target.slice(0,start)+once(target.slice(start),from,to);
    const problems = prepareComponentProblems(job(cutTarget).steps)
      .map(p => p.replace(/^prepare-native host /, ''));
    assert.deepEqual(problems, want, from);
    assert.ok(prepareWorkflowProblems({...real(), prepare: cutTarget}).length >= want.length);
  }
});
test('red cut: re-adding the private adapter deployment to prepare-native is refused', () => {
  const text = once(read('prepare'), '      - name: Install N/LLVM and AST into the native input root\n',
    '      - name: Deploy adapter\n        run: node ci/bootstrap/deploy-native-tools.mjs src ref out\n      - name: Install N/LLVM and AST into the native input root\n');
  assert.ok(prepareWorkflowProblems({...real(), prepare: text}).includes('prepare-native consumes the retired private tools adapter'));
});

// ---- end-to-end mock layout: producer output -> native-inputs -> downstream readers ----
const LLVM = commit('1'), RUNTIME = commit('2'), COMPILER = commit('3'), SHIM = commit('a');
// build_prepare_llvm.mjs output shape for the shim object (shim step) and cjdb.
// compiler-rt of the same build (build_prepare_llvm.mjs compiler-rt): ar archives,
// Darwin's lipo'd libclang_rt.osx.a a fat file.
const rtBytes = (row, label) => Buffer.concat([row.name === 'libclang_rt.osx.a' ? Buffer.from([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2])
  : Buffer.from('!<arch>\n'), Buffer.from(`${row.name} ${label}`)]);
const escape = text => text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
function putShimCjdb(out, native, label, platform) {
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(out, rel)), {recursive: true}); fs.writeFileSync(path.join(out, rel), body); };
  const object = Buffer.from('shim object ' + label);
  put('fixed-llc/cjselfhost_llvmshim.o', object);
  put('fixed-llc/SHIM-BUILD.json', JSON.stringify({object: 'fixed-llc/cjselfhost_llvmshim.o', bytes: object.length,
    sha256: crypto.createHash('sha256').update(object).digest('hex'), symbols: ['LLVMSelfhost', 'CJOF'], argv: ['clang++']}));
  put(`bin/lldb${native.exe}`, 'lldb ' + label);
  if (native.os !== 'win32') { put('bin/lldb-argdumper', 'lldb-argdumper ' + label); fs.chmodSync(path.join(out, 'bin/lldb-argdumper'), 0o755); }
  put(native.os === 'win32' ? 'lldb-lib/liblldb.dll' : native.os === 'darwin' ? 'lldb-lib/liblldb.15.dylib' : 'lldb-lib/liblldb.so.15', 'liblldb');
  // clang-resource-headers of the same build (build_prepare_llvm.mjs clang-resources)
  for (const name of CLANG_HEADERS) put(`clang-resources/15.0.4/include/${name}`, 'builtin ' + name);
  for (const row of compilerRtLibraries(platform)) put(`compiler-rt/${row.name}`, rtBytes(row, label));
}
const CLANG_HEADERS = ['stddef.h', 'stdint.h', 'stdarg.h'];
// The pinned Python prefix layout of each host (build_prepare_llvm.mjs PREPARE_PYTHON).
function pythonLayout(platform) {
  const os = sdkPlatform(platform).os;
  if (os === 'win32') return {interpreter: 'python.exe', header: 'include/Python.h', library: 'libs/python311.lib',
    stdlib: 'Lib/os.py', include: 'include', suffix: '.cp311-win_amd64.pyd', lldb: 'liblldb.dll', copy: true};
  const darwin = os === 'darwin';
  return {interpreter: 'bin/python3.11', header: 'include/python3.11/Python.h',
    library: darwin ? 'lib/libpython3.11.dylib' : 'lib/libpython3.11.so.1.0', stdlib: 'lib/python3.11/os.py',
    include: 'include/python3.11', suffix: darwin ? '.cpython-311-darwin.so' : '.cpython-311-x86_64-linux-gnu.so',
    lldb: darwin ? 'liblldb.15.dylib' : 'liblldb.so.15', copy: false};
}
// No network or foreign binaries: extract a small, digest-pinned tar using the
// target's archive layout and model sysconfig and the surrounding LLVM install.
for (const {llvm_platform: platform} of PREPARE_HOSTS.filter(h => h.llvm_platform !== 'windows_x86_64')) {
  test(platform + ': prepared Python record reaches the package reader', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'python-package-'));
    t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
    const sdk = path.join(dir, 'sdk'), out = path.join(dir, 'out'), layout = pythonLayout(platform);
    const write = (file, data) => {
      fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, data);
    };
    const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    const fixed = PREPARE_PYTHON[platform], tree = path.join(dir, 'tree'), top = fixed.prefix ?? '.';
    for (const rel of [layout.interpreter, layout.header, layout.library, 'share/fixture']) {
      write(path.join(tree, top, rel), platform + ':' + rel);
    }
    const archive = path.join(dir, 'fixture.tar.gz');
    execFileSync('tar', ['-czf', archive, '-C', tree, top]);
    const pin = {...fixed, url: 'https://example.invalid/fixture.tar.gz',
      sha256: digest(archive), size: fs.statSync(archive).size};
    const configure = prefix => ({version: pin.version + ' (fixture)', configure: '--enable-shared',
      executable: path.join(prefix, layout.interpreter), include: path.join(prefix, layout.include),
      library: path.join(prefix, layout.library)});
    const {root: prefix} = await preparePython({platform, out, configure,
      download: (url, file) => { assert.equal(url, pin.url); fs.copyFileSync(archive, file); }}, {[platform]: pin});

    const native = sdkPlatform(platform), nativeRoot = path.join(sdk, 'third_party/llvm');
    fs.cpSync(prefix, nativeRoot, {recursive: true});
    const record = path.join(sdk, 'share/cjcj/build-inputs/python-original.json');
    const input = {record: path.join(out, 'PYTHON-BUILD-INPUTS.json')};
    const original = await pythonSourceInputs({...input, root: prefix, nativeRoot, platform, selected: configure(prefix)});
    write(path.join(sdk, 'BUILD-INPUTS.json'), JSON.stringify({
      configuration: {pythonInputs: input}, pythonSource: original}));
    await preserveNativePythonInput(sdk);
    fs.rmSync(out, {recursive: true});
    const selected = configure(nativeRoot), artifacts = [];
    for (const rel of ['third_party/llvm/' + native.llvmDirectory + '/' + native.llvmLibrary, 'tools/bin/cjdb']) {
      const file = path.join(sdk, rel);
      write(file, 'native fixture: ' + rel);
      artifacts.push({path: rel, sha256: digest(file)});
    }
    const readPackage = async sha256 => {
      const pythonSource = await pythonSourceInputs({record, sha256, root: nativeRoot, nativeRoot, platform, selected});
      write(path.join(path.dirname(record), 'native-llvm.json'), JSON.stringify({rc: 0, platform, artifacts,
        pythonSource, pythonConfiguration: {selected}, pythonInstallation: {observed: {version: selected.version}}}));
      return (await installedInputs(sdk, platform)).components.find(row => row.component === 'python');
    };
    const row = await readPackage(original.build.originalInputs.sha256);
    assert.deepEqual(row.source, {status: 'resolved', kind: 'archive', url: pin.url, version: pin.version, sha256: pin.sha256});
    assert.deepEqual(row.build.producer, {repository: root,
      commit: execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
      scriptSha256: digest(path.join(root, 'build/sdk/producers/release/build_prepare_llvm.mjs'))});
    assert.equal(row.build.originalInputs.sha256, digest(record));
    const facts = JSON.parse(fs.readFileSync(record));
    for (const producer of ['legacy string', {repository: root}, {...facts.producer, commit: 'g'.repeat(40)}]) {
      write(record, JSON.stringify({...facts, producer}));
      await assert.rejects(readPackage(), {message: 'INSTALLED_PYTHON_CONFIGURATION'});
    }
  });
}

for (const type of ['commit', 'blob']) {
  test(`preparePython: ${type === 'commit' ? 'detached commit HEAD reaches download' : 'blob HEAD fails before prefix and download'}`, async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'python-head-'));
    t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
    const git = (args, input) => execFileSync('git', args, {cwd: dir, encoding: 'utf8', input}).trim();
    git(['init', '--quiet', '--object-format=sha1']);
    if (type === 'commit') {
      git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '--no-gpg-sign', '-qm', 'fixture']);
      git(['checkout', '--quiet', '--detach', 'HEAD']);
    } else {
      const blob = git(['hash-object', '-w', '--stdin'], 'not a commit');
      git(['update-ref', 'refs/tags/blob', blob]);
      git(['symbolic-ref', 'HEAD', 'refs/tags/blob']);
    }
    assert.equal(git(['cat-file', '-t', 'HEAD']), type);

    // Use the fixture's Git metadata for the producer's own source root.
    const previous = {GIT_DIR: process.env.GIT_DIR, GIT_WORK_TREE: process.env.GIT_WORK_TREE};
    const out = path.join(dir, 'out'), sentinel = new Error('download reached');
    let downloads = 0;
    try {
      process.env.GIT_DIR = path.join(dir, '.git');
      process.env.GIT_WORK_TREE = root;
      const result = await preparePython({platform: 'linux_x86_64', out, download: () => {
        downloads++;
        throw sentinel;
      }}).catch(error => error);
      const prefix = fs.existsSync(path.join(out, 'python'));
      if (type === 'commit') {
        assert.deepEqual({prefix, downloads}, {prefix: true, downloads: 1});
        assert.equal(result, sentinel);
      } else {
        assert.deepEqual({prefix, downloads}, {prefix: false, downloads: 0});
        assert.equal(result.code, 128); // Git rejected the revision.
      }
    } finally {
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    }
  });
}

test('preparePython rejects other archive bytes with the release pin', async t => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'python-archive-'));
  t.after(() => fs.rmSync(out, {recursive: true, force: true}));
  await assert.rejects(preparePython({platform: 'linux_x86_64', out,
    download: (_url, file) => fs.writeFileSync(file, 'other archive')}), {message: 'PREPARE_PYTHON_ARCHIVE_IDENTITY'});
});
function putPython(out, platform) {
  if (!PREPARE_PYTHON[platform]) return;
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(out, rel)), {recursive: true}); fs.writeFileSync(path.join(out, rel), body); };
  const L = pythonLayout(platform);
  const products = {[L.interpreter]: 'python interpreter', [L.header]: 'python header', [L.library]: 'python library'};
  for (const [rel, body] of Object.entries(products)) put('python/' + rel, body);
  put('python/' + L.stdlib, 'stdlib');
  // the same build's lldb package: _lldb is its liblldb (Unix: a link; Windows: a copy)
  put('lldb-python/lldb/__init__.py', 'import six\nimport _lldb');
  put('lldb-python/six.py', 'six of the same LLDB tree');
  if (!fs.existsSync(path.join(out, 'lldb-lib', L.lldb))) put('lldb-lib/' + L.lldb, 'liblldb');
  if (L.copy) fs.copyFileSync(path.join(out, 'lldb-lib', L.lldb), path.join(out, 'lldb-python/lldb/_lldb' + L.suffix));
  else fs.symlinkSync('../../../' + L.lldb, path.join(out, 'lldb-python/lldb/_lldb' + L.suffix));
  // upstream finish_swig_python's second relative link: lldb/lldb-argdumper -> <prefix>/bin
  if (!L.copy) fs.symlinkSync('../../../../bin/lldb-argdumper', path.join(out, 'lldb-python/lldb/lldb-argdumper'));
  else put('lldb-python/lldb/lldb-argdumper.exe', 'lldb-argdumper copy');
  const files = Object.fromEntries(Object.entries(products).map(([rel, body]) => [rel, {sha256: crypto.createHash('sha256').update(body).digest('hex')}]));
  const pin = PREPARE_PYTHON[platform];
  put('PYTHON-BUILD-INPUTS.json', JSON.stringify({schema: 'cjcj-prepare-python-v1', rc: 0, target: platform, host: platform,
    producer: {repository: 'fixture', commit: SHIM}, source: {url: pin.url, version: pin.version, sha256: pin.sha256}, files}));
  const selected = {executable: out + '/python/' + L.interpreter, include: out + '/python/' + L.include,
    library: out + '/python/' + L.library, suffix: L.suffix, version: pin.version + ' (main)'};
  put('PYTHON-CONFIGURED.json', JSON.stringify({selected, actual: selected, cacheSha256: 'c'.repeat(64)}));
}
function produced(t, target) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-e2e-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const native = sdkPlatform(PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  const put = (rel, body) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), body); };
  // An ELF64 x86-64 header and the source stamp, as the real library carries them.
  const elf = Buffer.alloc(64); elf.set([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]); elf.writeUInt16LE(62, 18);
  put('llvm-out/' + native.llvmLibrary, Buffer.concat([elf, Buffer.from(`llvm bytes ${target} CJLLVM-COMMIT:${LLVM}\n`)]));
  putPython(path.join(dir, 'llvm-out'), native.platform ?? PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  for (const tool of PREPARE_LLVM_TOOLS) put(`llvm-out/bin/${tool}${native.exe}`, `${tool} ${target}`);
  putShimCjdb(path.join(dir, 'llvm-out'), native, target, PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  put('root/hle/hle-dependencies.json', '{}');
  for (const rel of ['libcangjie-ast-support.a', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h',
    ...stdxChirMembers, ...PREPARE_AST_STD_HEADERS, 'include/cangjie/AST/Node.h', 'third_party/flatbuffers/bin/flatc' + native.exe])
    put('ast-out/' + rel, 'ast ' + rel);
  putHost(path.join(dir, 'root'), PREPARE_HOSTS.find(h => h.target === target).llvm_platform);
  put('root/runtime/NATIVE-INPUTS.json', JSON.stringify({configuration: {runtime: RUNTIME}}));
  const root = path.join(dir, 'root'), commits = {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER};
  installLlvm({root, target, from: path.join(dir, 'llvm-out'), commits, producer: 'test', shimCommit: SHIM});
  installAst({root, target, from: path.join(dir, 'ast-out'), commits});
  return {dir, root, native};
}
for (const host of PREPARE_HOSTS) test(`${host.target}: prepare output is read by the downstream native consumers`, async t => {
  const {root, native} = produced(t, host.target);
  const {locations} = assembleNativeInputs({root, target: host.target, hostVersion: '1.1.0', env, pins});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'locations.json'))), locations);
  // configure-gha-inputs / select-native-host: the same resolver and readers.
  const resolved = await nativeInstallationLocations(root, locations, {});
  for (const name of ['llvm', 'runtime', 'ast']) {
    assert.ok(fs.existsSync(resolved[name].buildResult), name);
    assert.ok(resolved[name].install.startsWith(root + path.sep), name);
  }
  const llvmFacts = JSON.parse(fs.readFileSync(resolved.llvm.buildResult));
  assert.equal(llvmFacts.commits.compiler, COMPILER);
  assert.equal(llvmFacts.commits.llvm, LLVM);
  assert.ok(fs.existsSync(path.join(resolved.llvm.install, 'third_party/llvm', native.llvmDirectory, native.llvmLibrary)));
  // sdk-inputs.mjs shapes.llvm members and the real shim reader on the N install.
  for (const rel of [PREPARE_SHIM_OBJECT, 'tools/bin/cjdb' + native.exe]) assert.ok(fs.existsSync(path.join(resolved.llvm.install, rel)), rel);
  assert.equal(resolved.shim.install, resolved.llvm.install);
  const shim = await readInstalledNativeShim({install: resolved.shim.install});
  assert.equal(shim.source.commit, SHIM); assert.equal(shim.compiler.commit, COMPILER); assert.equal(shim.llvm.commit, LLVM);
  fs.appendFileSync(path.join(resolved.llvm.install, PREPARE_SHIM_OBJECT), 'x');
  await assert.rejects(readInstalledNativeShim({install: resolved.llvm.install}), /NATIVE_SHIM_INSTALLED_BYTES/);
  const ast = await readInstalledNativeAst({install: resolved.ast.install, buildResult: resolved.ast.buildResult,
    platform: locations.platform, commit: COMPILER, llvmCommit: LLVM});
  assert.equal(ast.library, `lib/${native.tuple}/libcangjie-ast-support.a`);
  assert.deepEqual(rejectPrivateTools(locations.tools), {});
  const provenance = JSON.parse(fs.readFileSync(path.join(root, 'PREPARE-PROVENANCE.json')));
  assert.equal(provenance.target, host.target);
});
test('red cut: downstream consumers refuse a damaged, mispaired or escaping prepare layout', async t => {
  const target = 'darwin-arm64';
  const tampered = produced(t, target);
  const {locations} = assembleNativeInputs({root: tampered.root, target, hostVersion: '1.1.0', env, pins});
  const resolved = await nativeInstallationLocations(tampered.root, locations, {});
  const read = () => readInstalledNativeAst({install: resolved.ast.install, buildResult: resolved.ast.buildResult,
    platform: locations.platform, commit: COMPILER, llvmCommit: LLVM});
  await read();
  fs.appendFileSync(path.join(resolved.ast.install, 'schema/StdAstFormat.fbs'), 'changed');
  await assert.rejects(read(), /NATIVE_AST_INSTALL_BYTES schema\/StdAstFormat\.fbs/);
  const other = produced(t, target);
  const located = assembleNativeInputs({root: other.root, target, hostVersion: '1.1.0', env, pins}).locations;
  const rows = await nativeInstallationLocations(other.root, located, {});
  await assert.rejects(readInstalledNativeAst({install: rows.ast.install, buildResult: rows.ast.buildResult,
    platform: located.platform, commit: commit('9'), llvmCommit: LLVM}), /NATIVE_AST_SOURCE_PAIR/);
  await assert.rejects(nativeInstallationLocations(other.root,
    {...located, installations: {...located.installations, ast: {...located.installations.ast, install: '../ast'}}}, {}), /INSTALL_PATH \.\.\/ast/);
  assert.throws(() => rejectPrivateTools({privateRoot: 'adapter'}), /NATIVE_TOOLS_PRIVATE_ROOT_RETIRED/);
  // A producer output that lacks a member or a commit is never installed.
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-empty-'));
  t.after(() => fs.rmSync(empty, {recursive: true, force: true}));
  assert.throws(() => installAst({root: empty, target, from: path.join(other.dir, 'llvm-out'), commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}}),
    /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING libcangjie-ast-support\.a/);
  assert.throws(() => componentCommits({PREPARE_LLVM_COMMIT: LLVM, PREPARE_RUNTIME_COMMIT: RUNTIME}), /PREPARE_COMPONENT_COMMIT compiler/);
});

// ---- host SDK: the original official archive, the consumer's pair rule ----
test('prepare host version follows the consumer pair rule and the checked-in pin', () => {
  const pinned = prepareHostVersion('linux-x64', {});
  assert.match(pinned, /^\d+\.\d+\.\d+-alpha\.\d+$/);
  assert.equal(prepareHostVersion('windows-x64', {CJCJ_NATIVE_LLVM_REF: LLVM, CJCJ_NATIVE_RUNTIME_REF: RUNTIME, CJCJ_NATIVE_HOST_VERSION: pinned}), pinned);
  assert.throws(() => prepareHostVersion('linux-x64', {CJCJ_NATIVE_LLVM_REF: LLVM, CJCJ_NATIVE_RUNTIME_REF: RUNTIME}),
    /NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED/);
  assert.throws(() => prepareHostVersion('linux-x64', {CJCJ_NATIVE_HOST_VERSION: '1.0.0-alpha.1'}), /PREPARE_HOST_VERSION_UNPINNED/);
});
test('install-host keeps only an archive with the pinned name, size and digest', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-host-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const fake = name => async (platform, work) => {
    const sdk = path.join(work, 'host-sdk-x/cangjie');
    fs.mkdirSync(path.join(sdk, 'bin'), {recursive: true}); fs.writeFileSync(path.join(sdk, 'bin/cjc'), 'h');
    fs.writeFileSync(path.join(work, name), 'not the release');
    return {path: sdk, archive: path.join(work, name), sha256: crypto.createHash('sha256').update('not the release').digest('hex')};
  };
  const root = path.join(dir, 'root'); fs.mkdirSync(root);
  await assert.rejects(installHost({root, target: 'linux-x64', env: {}, prepare: fake('host-sdk.tar')}), /PREPARE_HOST_ARCHIVE_IDENTITY/);
  assert.ok(!fs.existsSync(path.join(root, 'HOST-INPUT.json')) && !fs.existsSync(path.join(root, '.host-download')));
  fs.mkdirSync(path.join(root, 'host'));
  await assert.rejects(installHost({root, target: 'linux-x64', env: {}, prepare: fake('x')}), /NATIVE_INPUTS_COMPONENT_EXISTS host/);
});
test('assemble names the recorded original archive and refuses a changed one', t => {
  const dir = inputs(t, {hostTarget: 'linux-x64'});
  const {locations} = assembleNativeInputs({root: dir, target: 'linux-x64', env, pins});
  assert.equal(locations.host.archive, 'host-archive/cangjie-sdk-fixture-1.1.0.tar.gz');
  assert.throws(() => assembleNativeInputs({root: dir, target: 'linux-x64', hostVersion: '9.9.9', env, pins}), /PREPARE_HOST_VERSION/);
  fs.appendFileSync(path.join(dir, locations.host.archive), 'x');
  assert.throws(() => assembleNativeInputs({root: dir, target: 'linux-x64', env, pins}), /PREPARE_HOST_ARCHIVE_IDENTITY/);
  const bare = inputs(t, {hostTarget: 'linux-x64'}); fs.rmSync(path.join(bare, 'HOST-INPUT.json'));
  assert.throws(() => assembleNativeInputs({root: bare, target: 'linux-x64', env, pins}), /NATIVE_INPUTS_COMPONENT_MISSING host/);
  assert.throws(() => assembleNativeInputs({root: inputs(t, {hostTarget: 'linux-x64'}), target: 'linux-aarch64', env, pins}), /PREPARE_HOST_RECORD/);
});

// ---- transport: one tar per family keeps modes; the consumer takes only it ----
test('pack and the consumer unpack keep executable modes and refuse other layouts', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-pack-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const root = path.join(dir, 'native-inputs');
  fs.mkdirSync(path.join(root, 'host/bin'), {recursive: true});
  fs.writeFileSync(path.join(root, 'host/bin/cjc'), '#!/bin/sh\n'); fs.chmodSync(path.join(root, 'host/bin/cjc'), 0o755);
  fs.writeFileSync(path.join(root, 'locations.json'), '{}');
  const packed = packNativeInputs({root, out: path.join(dir, 'native-inputs.tar')});
  assert.throws(() => packNativeInputs({root, out: path.join(root, 'x.tar')}), /NATIVE_INPUTS_ARCHIVE_INSIDE_ROOT/);
  const download = path.join(dir, 'download'); fs.mkdirSync(download);
  fs.copyFileSync(packed.file, path.join(download, 'native-inputs.tar')); // artifact transport: bytes only
  unpackNativeArtifact({directory: download, archive: 'native-inputs.tar'});
  assert.equal(fs.statSync(path.join(download, 'host/bin/cjc')).mode & 0o111, 0o111);
  assert.ok(!fs.existsSync(path.join(download, 'native-inputs.tar')));
  const loose = path.join(dir, 'loose'); fs.mkdirSync(loose);
  fs.copyFileSync(packed.file, path.join(loose, 'native-inputs.tar')); fs.writeFileSync(path.join(loose, 'extra'), '');
  assert.throws(() => unpackNativeArtifact({directory: loose, archive: 'native-inputs.tar'}), /NATIVE_ARTIFACT_SINGLE_ARCHIVE_REQUIRED/);
  const directoryUpload = path.join(dir, 'directory-upload'); fs.cpSync(root, directoryUpload, {recursive: true});
  assert.throws(() => unpackNativeArtifact({directory: directoryUpload, archive: 'native-inputs.tar'}), /NATIVE_ARTIFACT_SINGLE_ARCHIVE_REQUIRED/);
});
test('red cut: uploading a directory instead of the tar, or a cjv host, is refused', () => {
  const dir = once(read('prepare'), '          path: ${{ runner.temp }}/native-inputs.tar\n', '          path: ${{ runner.temp }}/native-inputs\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), prepare: dir}), ['prepare-native uploads native-inputs-${{ matrix.target }} without native-inputs.tar']);
  const rt = once(read('prepare'), '          path: .platform-ci/runtime-install.tar\n', '          path: .platform-ci/runtime-install\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), prepare: rt}),
    ['prepare-native uploads native-runtime-install-${{ matrix.llvm_platform }} without runtime-install.tar']);
  const cjv = once(read('prepare'), '          cp -a .platform-ci/runtime-install "$root/runtime"\n',
    '          cp -a .platform-ci/runtime-install "$root/runtime"\n          npx --yes zx@8 ci/setup_sdk.mjs\n');
  assert.deepEqual(prepareWorkflowProblems({...real(), prepare: cjv}), ['prepare-native provisions the host from an installed toolchain']);
});
test('every native-inputs consumer unpacks the tar before the host or runtime is read', () => {
  const jobs = loadYaml(read('sdk-build-target')).jobs;
  for (const name of ['source-stage0', 'native-windows-sdk']) {
    const steps = jobs[name].steps.map(step => step.name || '');
    const at = label => steps.indexOf(label);
    assert.ok(at('Unpack selected native inputs with their file modes') === at('Receive selected native inputs before choosing the host') + 1, name);
    assert.ok(at('Unpack selected native inputs with their file modes') < at('Select actual native host and freeze the same inputs'), name);
    assert.ok(at('Unpack fixed native runtime installation with its file modes') === at('Receive fixed native runtime installation') + 1, name);
  }
  // ci.yml consumes the same native-inputs artifact for its coloured target SDK.
  const ci = loadYaml(read('ci')).jobs.build.steps.map(step => step.name || '');
  assert.equal(ci.indexOf('Unpack native SDK producer inputs with their file modes'), ci.indexOf('Receive native SDK producer inputs') + 1);
  assert.ok(ci.indexOf('Unpack native SDK producer inputs with their file modes') < ci.indexOf('Prepare paired coloured target SDK'));
});

// ---- N/LLVM producer: the same dylib build with its tools on all hosts ----
test('the N/LLVM producer configures the dylib build and installs library and tools', async t => {
  const args = llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', platform: 'windows_x86_64', compiler: 'c'});
  // Unix readers link the installed N library; Windows keeps the static tools.
  const unix = llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', platform: 'linux_x86_64', compiler: 'c',
    python: {executable: 'e', include: 'i', library: 'l'}});
  for (const flag of ['-DLLVM_LINK_LLVM_DYLIB=ON', '-DLLDB_ENABLE_PYTHON=ON', '-DPython3_EXECUTABLE=e', '-DPython3_INCLUDE_DIR=i', '-DPython3_LIBRARY=l'])
    assert.ok(unix.includes(flag), flag);
  assert.ok(!unix.includes('-DLLVM_LINK_LLVM_DYLIB=OFF') && !unix.includes('-DLLDB_ENABLE_PYTHON=OFF'));
  assert.throws(() => lldbPythonArgs({executable: 'e', include: 'i'}), /PREPARE_LLDB_PYTHON_SELECTION library/);
  // Every prepare host builds LLDB with its pinned Python prefix (source and package cjdb need it).
  assert.deepEqual(Object.keys(PREPARE_PYTHON).sort(), PREPARE_HOSTS.map(host => host.llvm_platform).sort());
  for (const pin of Object.values(PREPARE_PYTHON)) assert.ok(pin.version === '3.11.9' && /^[0-9a-f]{64}$/.test(pin.sha256) && pin.size > 0);
  const win = lldbPythonArgs({executable: 'C:\\p\\python.exe', include: 'C:\\p\\include', library: 'C:\\p\\libs\\python311.lib'}, 'win32');
  assert.ok(win.includes('-DPython3_EXECUTABLE=C:/p/python.exe') && win.includes('-DPython3_LIBRARY=C:/p/libs/python311.lib'), win.join(' '));
  for (const flag of ['-DLLVM_BUILD_LLVM_DYLIB=ON', '-DLLVM_LINK_LLVM_DYLIB=OFF', '-DLLDB_ENABLE_PYTHON=OFF', '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64', '-DLLVM_ENABLE_ZLIB=OFF',
    '-DLLVM_ENABLE_PROJECTS=clang;lldb;compiler-rt', '-DCANGJIE_ROOT=c', '-DLLDB_INCLUDE_TESTS=OFF',
    '-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF', '-DCOMPILER_RT_BUILD_LIBFUZZER=OFF', '-DCOMPILER_RT_BUILD_SANITIZERS=OFF'])
    assert.ok(args.includes(flag), flag);
  assert.ok(!args.includes('-DLLVM_ENABLE_PROJECTS='), 'the LLVM build enables lldb');
  assert.ok(PREPARE_LLVM_TARGETS.includes('lldb'));
  assert.throws(() => llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', platform: 'linux_x86_64'}), /PREPARE_LLVM_COMPILER_SOURCE/);
  assert.ok(!llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', platform: 'linux_x86_64', compiler: 'c'}).includes('-DLLVM_ENABLE_ZLIB=OFF'));
  // compiler-rt target selection (pinned CompilerRTUtils.cmake:423-434): off Darwin the
  // default-target-only build takes CMAKE_C_COMPILER_TARGET, the host triple whose arch is
  // the installed library suffix; Darwin builds its fat osx libraries with neither.
  for (const platform of PREPARE_HOSTS.map(host => host.llvm_platform)) {
    const configure = llvmConfigureArgs({source: 's', build: 'b', runtime: 'r', sha: LLVM, jobs: '4', platform, compiler: 'c'});
    const targets = configure.filter(arg => /^-DCMAKE_[A-Z]+_COMPILER_TARGET=/.test(arg));
    if (sdkPlatform(platform).os === 'darwin') {
      assert.deepEqual(targets, [], platform);
      assert.ok(!configure.some(arg => arg.startsWith('-DCOMPILER_RT_DEFAULT_TARGET_ONLY')), platform);
      continue;
    }
    assert.deepEqual(targets, ['-DCMAKE_C_COMPILER_TARGET=' + PREPARE_COMPILER_RT_TRIPLES[platform]], platform);
    assert.ok(configure.includes('-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON'), platform);
    const arch = PREPARE_COMPILER_RT_TRIPLES[platform].split('-')[0];
    for (const row of compilerRtLibraries(platform)) assert.ok(row.source.endsWith(`-${arch}.a`), `${platform} ${row.source}`);
  }
  assert.deepEqual(Object.keys(PREPARE_COMPILER_RT_TRIPLES).sort(),
    PREPARE_HOSTS.map(host => host.llvm_platform).filter(platform => sdkPlatform(platform).os !== 'darwin').sort());
  assert.throws(() => compilerRtArgs('linux_riscv64'), /PLATFORM|PREPARE_COMPILER_RT_TRIPLE/);
  for (const platform of PREPARE_HOSTS.map(host => host.llvm_platform)) {
    const native = sdkPlatform(platform), work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-'));
    t.after(() => fs.rmSync(work, {recursive: true, force: true}));
    const seen = [];
    let omitClangResources = false, omitCompilerRt, omitSix = false, omitArgdumper = false;
    const run = (file, argv) => { // records argv; the build step leaves the real output shape
      const all = [file, ...argv]; seen.push(all.join(' '));
      if (all[0] === 'git' && all.includes('rev-parse')) return {status: 0, stdout: LLVM + '\n'};
      if (all.includes('--jobs-only')) return {status: 0, stdout: '3\n'};
      if (all[0] === 'cmake' && all[1] === '--build') {
        const build = all[2];
        fs.mkdirSync(path.join(build, native.llvmDirectory), {recursive: true}); fs.mkdirSync(path.join(build, 'bin'), {recursive: true});
        fs.writeFileSync(path.join(build, native.llvmDirectory, native.llvmLibrary), 'lib');
        for (const tool of ['llc', 'llvm-as', 'llvm-dis', 'llvm-nm', 'lldb']) fs.writeFileSync(path.join(build, 'bin', tool + native.exe), tool);
        if (all.includes('lldb-argdumper') && !omitArgdumper) { fs.writeFileSync(path.join(build, 'bin/lldb-argdumper'), 'argdumper'); fs.chmodSync(path.join(build, 'bin/lldb-argdumper'), 0o644); }
        fs.mkdirSync(path.join(build, 'lib'), {recursive: true});
        fs.writeFileSync(path.join(build, native.os === 'win32' ? 'bin' : 'lib', native.os === 'win32' ? 'liblldb.dll' : 'liblldb.so.15'), 'liblldb');
        if (all.includes('clang-resource-headers') && !omitClangResources) for (const name of CLANG_HEADERS) {
          fs.mkdirSync(path.join(build, 'lib/clang/15.0.4/include'), {recursive: true});
          fs.writeFileSync(path.join(build, 'lib/clang/15.0.4/include', name), 'builtin ' + name);
        }
        // compiler-rt lands in lib/clang/<version>/lib/<os> (PER_TARGET_RUNTIME_DIR=OFF), with a non-required archive beside it
        if (all.includes('builtins') && !omitClangResources) for (const row of [...compilerRtLibraries(platform), {name: 'x', source: 'other/libclang_rt.extra.a'}]) {
          if (row.source === omitCompilerRt) continue;
          const file = path.join(build, 'lib/clang/15.0.4/lib', row.source);
          fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, rtBytes(row, platform));
        }
        if (all.includes('lldb-python')) {
          const pkg = path.join(build, lldbPythonBuildPackage(native.os)), L = pythonLayout(platform);
          fs.mkdirSync(pkg, {recursive: true});
          fs.writeFileSync(path.join(pkg, '__init__.py'), 'import six\nimport _lldb');
          if (!omitSix) fs.writeFileSync(path.join(path.dirname(pkg), 'six.py'), 'six of the same LLDB tree');
          if (L.copy) fs.copyFileSync(path.join(build, 'bin/liblldb.dll'), path.join(pkg, '_lldb' + L.suffix));
          else fs.symlinkSync('../../../liblldb.so.15', path.join(pkg, '_lldb' + L.suffix));
        }
      }
      // llvm-nm --defined-only as each format prints it: ELF versioned, Mach-O with '_'.
      if (all[0].endsWith('llvm-nm' + native.exe)) return {status: 0, stdout: native.os === 'darwin'
        ? '0000 T _LLVMInitializeX86TargetInfo\n' : native.os === 'linux' ? '0000 T LLVMInitializeX86TargetInfo@@LLVM_15\n'
          : '0000 T LLVMInitializeX86TargetInfo\n'};
      return {status: 0, stdout: ''};
    };
    const python = PREPARE_PYTHON[platform] ? {executable: '/p/bin/python3.11', include: '/p/include/python3.11', library: '/p/lib/libpython3.11.so'} : undefined;
    const out = path.join(work, 'out');
    const compiler = path.join(work, 'compiler'); fs.mkdirSync(path.join(compiler, 'schema'), {recursive: true});
    fs.writeFileSync(path.join(compiler, 'schema/CjoFormat.fbs'), 'schema');
    assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out, work, env: {}, run}), /PREPARE_LLVM_COMPILER_SOURCE/);
    if (python) assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out, work, env: {}, run, compiler}), /PREPARE_LLDB_PYTHON_REQUIRED/);
    buildPrepareLlvm({platform, sha: LLVM, out, work, env: {}, run, compiler, python});
    if (python) {
      const binding = fs.lstatSync(path.join(out, 'lldb-python/lldb/_lldb' + pythonLayout(platform).suffix));
      assert.ok(pythonLayout(platform).copy ? binding.isFile() : binding.isSymbolicLink(), platform);
      // the package's sibling six crosses with it, from the build tree's site-packages
      assert.deepEqual(fs.readdirSync(path.join(out, 'lldb-python')).sort(), ['lldb', 'six.py'], platform);
      assert.equal(fs.readFileSync(path.join(out, 'lldb-python/six.py'), 'utf8'), 'six of the same LLDB tree');
      // red cut: an LLDB Python build without its six sibling is not exported, and the build path is named
      omitSix = true;
      const noSix = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-nosix-'));
      t.after(() => fs.rmSync(noSix, {recursive: true, force: true}));
      assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out: path.join(noSix, 'out'), work: noSix, env: {}, run, compiler, python}),
        new RegExp(`^Error: PREPARE_LLDB_PYTHON_SIX_MISSING ${escape(path.posix.dirname(lldbPythonBuildPackage(native.os)))}/six\\.py$`));
      omitSix = false;
    }
    if (native.os !== 'win32') {
      // the helper the package's lldb-argdumper link names is exported executable beside lldb
      assert.equal(fs.readFileSync(path.join(out, 'bin/lldb-argdumper'), 'utf8'), 'argdumper');
      assert.equal(fs.statSync(path.join(out, 'bin/lldb-argdumper')).mode & 0o777, 0o755, platform);
      // red cut: a Unix build without the helper is not exported
      omitArgdumper = true;
      const noHelper = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-nohelper-'));
      t.after(() => fs.rmSync(noHelper, {recursive: true, force: true}));
      assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out: path.join(noHelper, 'out'), work: noHelper, env: {}, run, compiler, python}),
        /^Error: PREPARE_LLDB_ARGDUMPER_MISSING bin\/lldb-argdumper$/);
      omitArgdumper = false;
    } else assert.ok(!fs.existsSync(path.join(out, 'bin/lldb-argdumper')), platform);
    for (const name of CLANG_HEADERS) assert.ok(fs.existsSync(path.join(out, 'clang-resources/15.0.4/include', name)), name);
    // compiler-rt is moved out of the resource tree under its installed names (ExtractRtlib.cmake)
    assert.deepEqual(fs.readdirSync(path.join(out, 'compiler-rt')).sort(), compilerRtLibraries(platform).map(row => row.name).sort(), platform);
    for (const row of compilerRtLibraries(platform)) {
      assert.deepEqual(fs.readFileSync(path.join(out, 'compiler-rt', row.name)), rtBytes(row, platform), row.name);
      assert.ok(!fs.existsSync(path.join(out, 'clang-resources/15.0.4/lib', row.source)), row.source);
    }
    assert.ok(fs.existsSync(path.join(out, 'clang-resources/15.0.4/lib/other/libclang_rt.extra.a')));
    assert.ok(seen.some(line => line.startsWith('cmake --build') && line.includes(`--target ${compilerRtTargets(native.os).join(' ')} LLVM `)), platform);
    // red cut: an LLVM build without one required compiler-rt library is not exported, and that one is named
    omitCompilerRt = compilerRtLibraries(platform).at(-1).source;
    const noRt = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-nort-'));
    t.after(() => fs.rmSync(noRt, {recursive: true, force: true}));
    assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out: path.join(noRt, 'out'), work: noRt, env: {}, run, compiler, python}),
      new RegExp(`^Error: PREPARE_COMPILER_RT_MISSING lib/clang/15\\.0\\.4/lib/${escape(omitCompilerRt)}$`));
    omitCompilerRt = undefined;
    // red cut: an LLVM build without the clang resource tree is not exported
    omitClangResources = true;
    const noClang = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-llvm-noclang-'));
    t.after(() => fs.rmSync(noClang, {recursive: true, force: true}));
    assert.throws(() => buildPrepareLlvm({platform, sha: LLVM, out: path.join(noClang, 'out'), work: noClang, env: {}, run, compiler, python}),
      /PREPARE_CLANG_RESOURCES lib\/clang must hold exactly one version directory/);
    omitClangResources = false;
    if (python) fs.rmSync(path.join(out, 'lldb-python'), {recursive: true});
    putPython(out, platform);
    assert.ok(seen.some(line => line.startsWith('cmake -G') && line.includes(python ? '-DLLDB_ENABLE_PYTHON=ON -DPython3_EXECUTABLE=/p/bin/python3.11'
      : '-DLLDB_ENABLE_PYTHON=OFF')), platform);
    assert.ok(seen.some(line => line.startsWith('cmake --build') && line.includes('LLVM llc llvm-as llvm-dis llvm-nm lldb clang-resource-headers')), platform);
    assert.ok(seen.some(line => line.startsWith('cmake -G') && line.includes('-DLLVM_ENABLE_PROJECTS=clang;lldb') && line.includes('-DCANGJIE_ROOT=')), platform);
    assert.ok(fs.existsSync(path.join(out, 'bin', 'lldb' + native.exe)));
    const objectBytes = Buffer.from('compiled shim ' + platform);
    fs.mkdirSync(path.join(work, 'dylib-build/include/llvm/Config'), {recursive: true});
    fs.writeFileSync(path.join(work, 'dylib-build/include/llvm/Config/llvm-config.h'), '');
    fs.writeFileSync(path.join(work, 'flatc'), 'flatc');
    const shimRun = nm => (file, argv) => {
      if (file === 'clang++') fs.writeFileSync(argv[argv.indexOf('-o') + 1], objectBytes);
      if (file.endsWith('llvm-nm' + native.exe)) return {status: 0, stdout: nm};
      return {status: 0, stdout: ''};
    };
    const prefix = native.os === 'darwin' ? '_' : '';
    // red cut: an object without the CJOF entry points is not installed
    assert.throws(() => buildPrepareShim({platform, compiler, flatc: path.join(work, 'flatc'), out, work, env: {},
      run: shimRun(`0000 T ${prefix}LLVMSelfhostLoopInfoCreate\n0000 T ${prefix}LLVMGlobalObjectAddStringAttribute\n`)}), /PREPARE_SHIM_SYMBOLS CJOF$/);
    assert.deepEqual(shimRequiredSymbols(fs.readFileSync(path.resolve(import.meta.dirname, '../../../../runtime_shim/cjselfhost_llvmshim.cpp'), 'utf8')),
      ['LLVMGlobalObjectAddStringAttribute', 'LLVMSelfhost', 'CJOF']);
    assert.deepEqual(shimSymbolProblems('0000 T _LLVMGlobalObjectAddStringAttributeX\n', ['LLVMGlobalObjectAddStringAttribute']), ['LLVMGlobalObjectAddStringAttribute']);
    const shimRecord = buildPrepareShim({platform, compiler, flatc: path.join(work, 'flatc'), out, work, env: {},
      run: shimRun(`0000 T ${prefix}LLVMSelfhostLoopInfoCreate\n0010 T ${prefix}CJOFPackageView\n0020 T ${prefix}LLVMGlobalObjectAddStringAttribute\n`)});
    assert.equal(shimRecord.bytes, objectBytes.length);
    assert.ok(fs.existsSync(path.join(out, native.llvmLibrary)));
    for (const tool of PREPARE_LLVM_TOOLS) assert.ok(fs.existsSync(path.join(out, 'bin', tool + native.exe)), tool);
    const root = path.join(work, 'root'); fs.mkdirSync(root);
    const target = PREPARE_HOSTS.find(h => h.llvm_platform === platform).target;
    assert.throws(() => installLlvm({root, target, from: out, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'llvm-dylib'}),
      /PREPARE_COMPONENT_COMMIT shim/);
    const facts = installLlvm({root, target, from: out, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'llvm-dylib', shimCommit: SHIM});
    assert.deepEqual(Object.keys(facts.tools), PREPARE_LLVM_TOOLS.map(tool => `third_party/llvm/bin/${tool}${native.exe}`));
    assert.equal(facts.nativeShim.object.path, PREPARE_SHIM_OBJECT);
    assert.equal(facts.cjdb.file, 'tools/bin/cjdb' + native.exe);
    await readInstalledNativeShim({install: path.join(root, 'llvm')});
    assert.equal(facts.clangResources.path, 'third_party/llvm/lib/clang');
    // lib/<tuple> holds the compiler-rt libraries, each recorded with path, sha256 and bytes
    assert.deepEqual(facts.targetLibraries.map(row => row.path), compilerRtLibraries(platform).map(row => `lib/${native.tuple}/${row.name}`));
    assert.equal(facts.configuration.projects, 'clang;lldb;compiler-rt');
    for (const row of facts.targetLibraries) {
      const bytes = fs.readFileSync(path.join(root, 'llvm', row.path));
      assert.deepEqual(bytes, fs.readFileSync(path.join(out, 'compiler-rt', path.basename(row.path))), row.path);
      assert.deepEqual({sha256: row.sha256, bytes: row.bytes}, {sha256: crypto.createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length});
    }
    // red cut: an N output without one compiler-rt library is not installed, and that one is named
    const lastRt = compilerRtLibraries(platform).at(-1).name;
    const noRtOut = path.join(work, 'out-nort'); fs.cpSync(out, noRtOut, {recursive: true, verbatimSymlinks: true});
    fs.rmSync(path.join(noRtOut, 'compiler-rt', lastRt));
    assert.throws(() => installLlvm({root: path.join(work, 'root-nort'), target, from: noRtOut,
      commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}),
      new RegExp(`^Error: NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING compiler-rt/${escape(lastRt)}$`));
    // red cut: a compiler-rt member that is not a static library is not installed
    const firstRt = compilerRtLibraries(platform)[0].name;
    const textRt = path.join(work, 'out-textrt'); fs.cpSync(out, textRt, {recursive: true, verbatimSymlinks: true});
    fs.writeFileSync(path.join(textRt, 'compiler-rt', firstRt), 'not an archive');
    assert.throws(() => installLlvm({root: path.join(work, 'root-textrt'), target, from: textRt,
      commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}),
      new RegExp(`^Error: PREPARE_COMPILER_RT_NOT_STATIC_LIBRARY compiler-rt/${escape(firstRt)}$`));
    // the required compiler-rt libraries left the resource tree; a non-required one stays there
    assert.deepEqual(Object.keys(facts.clangResources.files).sort(),
      [...CLANG_HEADERS.map(name => '15.0.4/include/' + name), '15.0.4/lib/other/libclang_rt.extra.a'].sort());
    for (const name of CLANG_HEADERS) assert.ok(fs.existsSync(path.join(root, 'llvm/third_party/llvm/lib/clang/15.0.4/include', name)), name);
    // red cut: an N without the clang resource tree is not installed
    const noResources = path.join(work, 'out-noclang'); fs.cpSync(out, noResources, {recursive: true, verbatimSymlinks: true});
    fs.rmSync(path.join(noResources, 'clang-resources'), {recursive: true});
    assert.throws(() => installLlvm({root: path.join(work, 'root-noclang'), target, from: noResources,
      commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}),
      /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING clang-resources/);
    if (python) {
      const L = pythonLayout(platform);
      assert.equal(facts.pythonInstallationInput.record, PREPARE_PYTHON_RECORD);
      assert.ok(fs.existsSync(path.join(root, 'llvm/third_party/llvm', L.interpreter)));
      assert.ok(facts.python.configured.selected.executable);
      const binding = path.join(root, 'llvm/third_party/llvm/lib/python3.11/site-packages/lldb/_lldb' + L.suffix);
      if (L.copy) assert.deepEqual(fs.readFileSync(binding), fs.readFileSync(path.join(root, 'llvm/third_party/llvm/lib', L.lldb)));
      else assert.equal(fs.realpathSync(binding), fs.realpathSync(path.join(root, 'llvm/third_party/llvm/lib', L.lldb)));
      // six sits beside lldb in the one site-packages cjdb's PYTHONPATH names (sdk-cjdb-python.mjs)
      assert.equal(fs.readFileSync(path.join(root, 'llvm/third_party/llvm/lib/python3.11/site-packages/six.py'), 'utf8'), 'six of the same LLDB tree');
      if (!L.copy) {
        // the package's helper link resolves to the same build's helper, installed executable at bin/
        const helper = path.join(root, 'llvm/third_party/llvm/lib/python3.11/site-packages/lldb/lldb-argdumper');
        assert.equal(fs.readlinkSync(helper), '../../../../bin/lldb-argdumper');
        assert.equal(fs.realpathSync(helper), fs.realpathSync(path.join(root, 'llvm/third_party/llvm/bin/lldb-argdumper')));
        assert.equal(fs.statSync(helper).mode & 0o777, 0o755);
        const cut = (name, edit) => { const from = path.join(work, 'out-' + name); fs.cpSync(out, from, {recursive: true, verbatimSymlinks: true}); edit(from);
          return () => installLlvm({root: path.join(work, 'root-' + name), target, from, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}); };
        // red cut: a producer output without the helper is not installed
        assert.throws(cut('nohelper', from => fs.rmSync(path.join(from, 'bin/lldb-argdumper'))),
          /^Error: NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING bin\/lldb-argdumper$/);
        // red cut: a helper without its executable mode is not installed
        assert.throws(cut('nomode', from => fs.chmodSync(path.join(from, 'bin/lldb-argdumper'), 0o644)),
          /^Error: NATIVE_INPUTS_PRODUCER_OUTPUT_MODE bin\/lldb-argdumper$/);
        // red cut: a package link to a file outside third_party/llvm is not installed
        assert.throws(cut('escape', from => fs.symlinkSync(path.join(out, 'bin/lldb'), path.join(from, 'lldb-python/lldb/escaped'))),
          /^Error: PREPARE_LLDB_PYTHON_LINK lib\/python3\.11\/site-packages\/lldb\/escaped$/);
      }
      // red cut: a producer output whose lldb package lost its six sibling is not installed
      const nosix = path.join(work, 'out-nosix'); fs.cpSync(out, nosix, {recursive: true, verbatimSymlinks: true}); fs.rmSync(path.join(nosix, 'lldb-python/six.py'));
      assert.throws(() => installLlvm({root: path.join(work, 'root-nosix'), target, from: nosix, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER},
        producer: 'x', shimCommit: SHIM}), /^Error: NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-python\/six\.py$/);
      assert.ok(seen.some(line => line.startsWith('cmake --build') && line.includes(L.copy ? ' lldb clang-resource-headers lldb-python --parallel'
        : ' lldb clang-resource-headers lldb-argdumper lldb-python --parallel')), 'lldb-python target');
      // red cut: a Python LLDB build without its lldb package is not installed
      const nopkg = path.join(work, 'out-nopkg'); fs.cpSync(out, nopkg, {recursive: true, verbatimSymlinks: true}); fs.rmSync(path.join(nopkg, 'lldb-python'), {recursive: true});
      assert.throws(() => installLlvm({root: path.join(work, 'root-nopkg'), target, from: nopkg, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER},
        producer: 'x', shimCommit: SHIM}), /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING lldb-python\/lldb/);
      // red cuts: no Python output, or a Python product that is not the recorded one
      const bare = path.join(work, 'out-nopython'); fs.cpSync(out, bare, {recursive: true}); fs.rmSync(path.join(bare, 'PYTHON-BUILD-INPUTS.json'));
      assert.throws(() => installLlvm({root: path.join(work, 'root-nopython'), target, from: bare, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER},
        producer: 'x', shimCommit: SHIM}), /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING PYTHON-BUILD-INPUTS\.json/);
      const swapped = path.join(work, 'out-swapped'); fs.cpSync(out, swapped, {recursive: true});
      fs.writeFileSync(path.join(swapped, 'python', L.library), 'another python');
      assert.throws(() => installLlvm({root: path.join(work, 'root-swapped'), target, from: swapped, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER},
        producer: 'x', shimCommit: SHIM}), new RegExp('PREPARE_PYTHON_PRODUCT_BYTES ' + L.library.replace(/[./]/g, '\\$&')));
    } else assert.equal(facts.pythonInstallationInput, undefined);
    // red cuts: no shim object or no lldb executable means no N install
    for (const [rel, message] of [['fixed-llc/cjselfhost_llvmshim.o', 'fixed-llc/cjselfhost_llvmshim\\.o'], [`bin/lldb${native.exe}`, `bin/lldb${native.exe.replace('.', '\\.')}`]]) {
      const copy = path.join(work, 'out-' + path.basename(rel)); fs.cpSync(out, copy, {recursive: true}); fs.rmSync(path.join(copy, rel));
      assert.throws(() => installLlvm({root: path.join(work, 'root-' + path.basename(rel)), target, from: copy,
        commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}), new RegExp(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING ${message}`));
    }
    // red cut: a missing tool is never installed
    fs.rmSync(path.join(out, 'bin', 'llvm-dis' + native.exe));
    assert.throws(() => installLlvm({root: path.join(work, 'root2'), target, from: out, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}, producer: 'x', shimCommit: SHIM}),
      new RegExp(`NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING bin/llvm-dis${native.exe.replace('.', '\\.')}`));
  }
  assert.throws(() => buildPrepareLlvm({platform: 'linux_x86_64', sha: 'main', out: os.tmpdir(), env: {}, run: () => ({status: 0})}), /PREPARE_LLVM_SHA/);
});

// ---- AST compiler: the source the consumer job selects ----
test('the AST compiler source is the consumer job\'s source selection', () => {
  const pinned = fs.readFileSync(path.join(root, 'ci/source_pin.env'), 'utf8').match(/^COMPILER_REF=([0-9a-f]{40})$/m)[1];
  assert.equal(compilerSource({}).commit, pinned);
  const explicit = {CJCJ_SOURCE_SELECTION: JSON.stringify({compiler: {url: 'https://example.invalid/compiler.git', tag: commit('9')}})};
  assert.deepEqual(compilerSource(explicit), {repository: 'https://example.invalid/compiler.git', commit: commit('9')});
  assert.throws(() => compilerSource({CJCJ_SOURCE_SELECTION: JSON.stringify({compiler: {url: 'https://example.invalid/c.git', tag: 'main'}})}),
    /WORKFLOW_FIXED_SOURCE_REQUIRED compiler/);
});

// ---- HLE dependency package: the real configureHleInput reads assemble output ----
test('install-hle yields the hleDependencies the real configureHleInput accepts, and fails closed', async t => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-hle-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const parser = path.join(work, 'dtsparser'); fs.mkdirSync(parser);
  // the pinned tools dtsparser/package.json dependency spellings
  fs.writeFileSync(path.join(parser, 'package.json'), JSON.stringify({dependencies: {typescript: 'npm:typescript@4.9.5', 'https-proxy-agent': '7.0.6 '}}));
  const cjbind = path.join(work, 'cjbind-fixture'); fs.writeFileSync(cjbind, 'cjbind bytes');
  const asset = {name: 'cjbind-fixture', size: 12, sha256: crypto.createHash('sha256').update('cjbind bytes').digest('hex'),
    version: HLE_CJBIND.version, url: HLE_CJBIND.base + 'cjbind-fixture'};
  const modules = (versions = {}) => (prefix, specs) => {
    for (const spec of specs) {
      const name = spec.slice(0, spec.lastIndexOf('@', spec.length) > 0 ? spec.indexOf('@', 1) : undefined);
      const version = versions[name] ?? spec.replace(/^.*@/, '').trim();
      fs.mkdirSync(path.join(prefix, 'node_modules', name), {recursive: true});
      fs.writeFileSync(path.join(prefix, 'node_modules', name, 'package.json'), JSON.stringify({name, version}));
    }
    fs.mkdirSync(path.join(prefix, 'node_modules/.bin'), {recursive: true});
    return ['npm', 'install', ...specs];
  };
  const root = path.join(work, 'root'); fs.mkdirSync(root);
  putHost(root, 'linux_x86_64');
  for (const [name, file] of [['llvm', 'BUILD-INPUTS.json'], ['runtime', 'NATIVE-INPUTS.json'], ['ast', 'BUILD-INPUTS.json']]) {
    fs.mkdirSync(path.join(root, name)); fs.writeFileSync(path.join(root, name, file), JSON.stringify({configuration: {name}, nativeShim: {}}));
  }
  const descriptor = await installHle({root, target: 'linux-x64', parser, cjbindFile: cjbind, asset, installModules: modules()});
  assert.deepEqual(descriptor.modules.packages, {typescript: '4.9.5', 'https-proxy-agent': '7.0.6'});
  assert.equal(descriptor.node.version, process.version);
  assert.ok(!fs.existsSync(path.join(root, 'hle/modules/.bin')));
  const {locations} = assembleNativeInputs({root, target: 'linux-x64', hostVersion: '1.1.0', env, pins});
  assert.equal(locations.hleDependencies, 'hle/hle-dependencies.json');
  const envFile = path.join(work, 'github-env');
  const selected = await configureHleInput(root, 'linux_x86_64', envFile);
  assert.equal(selected, fs.realpathSync(path.join(root, 'hle/hle-dependencies.json')));
  assert.equal(fs.readFileSync(envFile, 'utf8'), `CJCJ_HLE_DEPENDENCIES=${selected}\n`);
  const read = await readHleDependencies(selected, 'linux_x86_64');
  assert.equal(read.cjbind.path, path.join(fs.realpathSync(root), 'hle/cjbind/cjbind'));
  assert.ok(fs.statSync(read.modules.path).isDirectory());
  // red cuts at the consumer: escaping descriptor, escaping or missing member
  const locationsFile = path.join(root, 'locations.json'), saved = fs.readFileSync(locationsFile, 'utf8');
  fs.writeFileSync(locationsFile, JSON.stringify({...locations, hleDependencies: '../hle/hle-dependencies.json'}));
  await assert.rejects(configureHleInput(root, 'linux_x86_64'), /GHA_HLE_ARTIFACT_PATH/);
  fs.writeFileSync(locationsFile, saved);
  const descriptorFile = path.join(root, 'hle/hle-dependencies.json'), original = fs.readFileSync(descriptorFile, 'utf8');
  const outside = path.join(work, 'outside-node'); fs.writeFileSync(outside, 'node');
  fs.writeFileSync(descriptorFile, JSON.stringify({...descriptor, node: {...descriptor.node, path: outside}}));
  await assert.rejects(configureHleInput(root, 'linux_x86_64'), /GHA_HLE_ARTIFACT_MEMBER/);
  fs.writeFileSync(descriptorFile, original);
  for (const member of ['cjbind/cjbind', 'node/node', 'modules']) {
    const file = path.join(root, 'hle', member), aside = file + '.aside';
    fs.renameSync(file, aside);
    await assert.rejects(configureHleInput(root, 'linux_x86_64'), /ENOENT/, member);
    fs.renameSync(aside, file);
  }
  await configureHleInput(root, 'linux_x86_64');
  // red cuts at the producer: unpinned cjbind bytes, unavailable asset, wrong module tree
  const again = path.join(work, 'again');
  for (const [options, message] of [[{cjbindFile: outside, asset}, /HLE_CJBIND_IDENTITY/],
    [{cjbindFile: cjbind, asset, installModules: modules({typescript: '5.0.0'})}, /HLE_MODULES_VERSION typescript/]]) {
    fs.rmSync(again, {recursive: true, force: true}); fs.mkdirSync(again);
    await assert.rejects(installHle({root: again, target: 'linux-x64', parser, installModules: modules(), ...options}), message);
  }
  // The four release-asset hosts keep exactly their four pinned sha256 assets.
  assert.deepEqual(Object.fromEntries(Object.entries(HLE_CJBIND.assets).map(([key, row]) => [key, row.sha256])), {
    linux_x86_64: '71bf15dbd18a343c366a923a5b25766a373af5d1709a59c25ced545ebc88f21e',
    linux_aarch64: '18fee7c8d63722f0eb990a5640d877212b195c5d994d78df29e65434d21bb579',
    windows_x86_64: '417c6aac0d2ff448490c2027bbbd619cf09d10b207e1513ebff369d69db9935e',
    darwin_aarch64: '4da660c010203be14660edb5ee0e76f4a894214ca7a7c383702159d2f9d4005b'});
  for (const platform of ['linux_x86_64', 'linux_aarch64', 'windows_x86_64', 'darwin_aarch64'])
    assert.match(hleCjbindAsset(platform).url, /^https:\/\/gitcode\.com\/Cangjie-SIG\/cjbind-cangjie\/releases\/download\/v1\.1\.0-alpha\.53\.1\//);
  assert.throws(() => hleCjbindAsset('darwin_x86_64'), /HLE_CJBIND_UNAVAILABLE darwin_x86_64/);
  // A source commit is not an identity on a release-asset host.
  const SOURCE = 'd9ba9709906fda36fdb486fa55ec615cdb1fa2cb';
  fs.rmSync(again, {recursive: true, force: true}); fs.mkdirSync(again);
  await assert.rejects(installHle({root: again, target: 'linux-x64', parser, cjbindFile: cjbind, asset, cjbindSourceCommit: SOURCE,
    installModules: modules()}), /HLE_CJBIND_SOURCE_UNAPPROVED linux_x86_64/);
});

// ---- darwin-x64: the approved source-built cjbind identity ----
test('darwin-x64 installs the approved source-built cjbind that the real configureHleInput accepts, and fails closed', async t => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-hle-source-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const SOURCE = 'd9ba9709906fda36fdb486fa55ec615cdb1fa2cb';
  assert.deepEqual(HLE_CJBIND_SOURCE_BUILD, {darwin_x86_64: {repo: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git',
    commit: SOURCE, tag: 'v1.1.0-alpha.53.1', version: 'v1.1.0-alpha.53.1-source'}});
  assert.equal(hleCjbindSource('darwin-x64').commit, SOURCE);
  for (const target of ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64'])
    assert.throws(() => hleCjbindSource(target), /HLE_CJBIND_SOURCE_UNAPPROVED/);
  const parser = path.join(work, 'dtsparser'); fs.mkdirSync(parser);
  fs.writeFileSync(path.join(parser, 'package.json'), JSON.stringify({dependencies: {typescript: 'npm:typescript@4.9.5'}}));
  const modules = () => (prefix, specs) => {
    for (const spec of specs) {
      const name = spec.slice(0, spec.indexOf('@', 1)), version = spec.replace(/^.*@/, '').trim();
      fs.mkdirSync(path.join(prefix, 'node_modules', name), {recursive: true});
      fs.writeFileSync(path.join(prefix, 'node_modules', name, 'package.json'), JSON.stringify({name, version}));
    }
    return ['npm', 'install', ...specs];
  };
  const built = path.join(work, 'cjbind-source/target/release/bin/main');
  fs.mkdirSync(path.dirname(built), {recursive: true}); fs.writeFileSync(built, 'source-built cjbind'); fs.chmodSync(built, 0o755);
  const empty = path.join(work, 'empty'); fs.writeFileSync(empty, ''); fs.chmodSync(empty, 0o755);
  const plain = path.join(work, 'not-executable'); fs.writeFileSync(plain, 'cjbind'); fs.chmodSync(plain, 0o644);
  const again = path.join(work, 'again');
  for (const [options, message] of [
    [{}, /HLE_CJBIND_SOURCE_FILE_REQUIRED darwin_x86_64/],
    [{cjbindSourceCommit: SOURCE}, /HLE_CJBIND_SOURCE_FILE_REQUIRED darwin_x86_64/],
    [{cjbindFile: built}, /HLE_CJBIND_SOURCE_COMMIT \(none\) != d9ba9709906fda36fdb486fa55ec615cdb1fa2cb/],
    [{cjbindFile: built, cjbindSourceCommit: 'e'.repeat(40)}, /HLE_CJBIND_SOURCE_COMMIT e{40} != d9ba9709906fda36fdb486fa55ec615cdb1fa2cb/],
    [{cjbindFile: built, cjbindSourceCommit: SOURCE.slice(0, 12)}, /HLE_CJBIND_SOURCE_COMMIT d9ba9709906f != /],
    [{cjbindFile: built, cjbindSourceCommit: SOURCE.toUpperCase()}, /HLE_CJBIND_SOURCE_COMMIT D9BA/],
    [{cjbindFile: path.join(work, 'absent'), cjbindSourceCommit: SOURCE}, /HLE_CJBIND_SOURCE_FILE /],
    [{cjbindFile: empty, cjbindSourceCommit: SOURCE}, /HLE_CJBIND_SOURCE_FILE /],
    [{cjbindFile: plain, cjbindSourceCommit: SOURCE}, /HLE_CJBIND_SOURCE_FILE /],
    [{cjbindFile: path.dirname(built), cjbindSourceCommit: SOURCE}, /HLE_CJBIND_SOURCE_FILE /]]) {
    fs.rmSync(again, {recursive: true, force: true}); fs.mkdirSync(again);
    console.log('DARWIN_X64_CJBIND_RED_ASSERT_REACHED ' + JSON.stringify(Object.keys(options)));
    await assert.rejects(installHle({root: again, target: 'darwin-x64', parser, installModules: modules(), ...options}), message);
    assert.equal(fs.existsSync(path.join(again, 'hle')), false, 'no HLE component before the identity holds');
  }
  const root = path.join(work, 'root'); fs.mkdirSync(root);
  putHost(root, 'darwin_x86_64');
  for (const [name, file] of [['llvm', 'BUILD-INPUTS.json'], ['runtime', 'NATIVE-INPUTS.json'], ['ast', 'BUILD-INPUTS.json']]) {
    fs.mkdirSync(path.join(root, name)); fs.writeFileSync(path.join(root, name, file), JSON.stringify({configuration: {name}, nativeShim: {}}));
  }
  const descriptor = await installHle({root, target: 'darwin-x64', parser, cjbindFile: built, cjbindSourceCommit: SOURCE, installModules: modules()});
  console.log('DARWIN_X64_CJBIND_GREEN_ASSERT_REACHED');
  assert.equal(descriptor.platform, 'darwin_x86_64');
  assert.deepEqual(descriptor.cjbind, {path: 'cjbind/cjbind', version: 'v1.1.0-alpha.53.1-source',
    source: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git@d9ba9709906fda36fdb486fa55ec615cdb1fa2cb', commit: SOURCE,
    sha256: crypto.createHash('sha256').update('source-built cjbind').digest('hex'), size: 19});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'hle/hle-dependencies.json'), 'utf8')), descriptor);
  assert.equal(fs.statSync(path.join(root, 'hle/cjbind/cjbind')).mode & 0o777, 0o755);
  const {locations} = assembleNativeInputs({root, target: 'darwin-x64', hostVersion: '1.1.0', env, pins});
  assert.equal(locations.hleDependencies, 'hle/hle-dependencies.json');
  const selected = await configureHleInput(root, 'darwin_x86_64');
  const read = await readHleDependencies(selected, 'darwin_x86_64');
  assert.equal(read.cjbind.path, path.join(fs.realpathSync(root), 'hle/cjbind/cjbind'));
  assert.equal(fs.readFileSync(read.cjbind.path, 'utf8'), 'source-built cjbind');
  assert.equal(read.cjbind.commit, SOURCE);
  await assert.rejects(configureHleInput(root, 'darwin_aarch64'), /GHA_NATIVE_ARTIFACT_PLATFORM/);
  // The SDK consumer (build/srcbuild/hle-dependencies.mjs) admits that version
  // and only it beside the two release versions, and only as the approved
  // build: darwin_x86_64, the approved repository and the approved commit.
  // Mach-O x86_64 headers stand in for the binaries (launcher-format check).
  const tools = path.join(work, 'tools'), dts = path.join(tools, 'packages/hle/src/dtsparser');
  fs.mkdirSync(dts, {recursive: true}); fs.copyFileSync(path.join(parser, 'package.json'), path.join(dts, 'package.json'));
  const macho = path.join(work, 'macho-x64'), header = Buffer.alloc(32);
  header.writeUInt32LE(0xfeedfacf, 0); header.writeUInt32LE(0x01000007, 4); fs.writeFileSync(macho, header);
  const input = (cjbind, platform = 'darwin_x86_64') => ({...read, platform, node: {...read.node, path: macho},
    cjbind: {...read.cjbind, path: macho, ...cjbind}});
  let n = 0;
  const consume = (cjbind, platform) => installHleDependencies({toolsRoot: tools, sdk: path.join(work, 'sdk' + n++),
    platform: platform ?? 'darwin_x86_64', input: input(cjbind, platform), prepareOnly: true});
  const consumed = await consume({});
  assert.equal(consumed.facts.cjbind.version, 'v1.1.0-alpha.53.1-source');
  assert.equal(consumed.facts.cjbind.source, 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git@' + SOURCE);
  await assert.rejects(consume({version: 'v1.1.0-alpha.53.2-source'}), /HLE_DEPENDENCY_VERSION cjbind/);
  // Same version and format, another source identity: refused at the consumer.
  const zero = '0'.repeat(40);
  await assert.rejects(consume({commit: zero, source: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git@' + zero}),
    /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
  await assert.rejects(consume({source: 'https://gitcode.com/Cangjie-SIG/cjbind-cangjie.git@' + zero}),
    /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
  await assert.rejects(consume({source: 'https://example.invalid/cjbind.git@' + SOURCE}), /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
  await assert.rejects(consume({commit: undefined}), /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
  // The source build is approved for darwin_x86_64 only.
  const elf = path.join(work, 'elf-x64'), elfHeader = Buffer.alloc(64);
  Buffer.from([127, 69, 76, 70, 2, 1]).copy(elfHeader); elfHeader.writeUInt16LE(62, 18); fs.writeFileSync(elf, elfHeader);
  await assert.rejects(installHleDependencies({toolsRoot: tools, sdk: path.join(work, 'sdk-linux'), platform: 'linux_x86_64',
    input: {...read, platform: 'linux_x86_64', node: {...read.node, path: elf}, cjbind: {...read.cjbind, path: elf}},
    prepareOnly: true}), /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
  // A release version may not carry a source commit.
  await assert.rejects(consume({version: 'v1.1.0-alpha.53.1'}), /HLE_DEPENDENCY_SOURCE_IDENTITY cjbind/);
});

test('prepare-native builds the darwin-x64 source cjbind on its own host and hands it to install-hle', () => {
  const steps = job(read('prepare')).steps, find = text => steps.filter(step => String(step.run || '').includes(text));
  const [build] = find('prepare_native_inputs.mjs cjbind-source'), [hle] = find('prepare_native_inputs.mjs install-hle');
  assert.equal(find('prepare_native_inputs.mjs cjbind-source').length, 1);
  assert.equal(build.if, "matrix.target == 'darwin-x64'");
  assert.ok(steps.indexOf(build) < steps.indexOf(hle));
  assert.ok(steps.indexOf(steps.find(step => String(step.run || '').includes('prepare_native_inputs.mjs install-host'))) < steps.indexOf(build));
  for (const piece of ['test "$actual" = "$CJBIND_REF"', 'export CANGJIE_HOME="$RUNNER_TEMP/native-inputs/host"', 'uv run --python 3.13 ./scripts/cjpm.py build',
    './target/release/bin/main --version', 'echo "commit=$actual" >> "$GITHUB_OUTPUT"']) assert.ok(build.run.includes(piece), piece);
  assert.equal(/patch_opt/.test(build.run), false, 'the official host SDK is used as installed');
  assert.deepEqual(hle.env, {CJBIND_FILE: '${{ steps.cjbind.outputs.file }}', CJBIND_COMMIT: '${{ steps.cjbind.outputs.commit }}'});
  const cuts = [[`          ./target/release/bin/main --version\n`, '', 'prepare-native does not build the darwin-x64 source cjbind'],
    [`        if: matrix.target == 'darwin-x64'\n        run: |\n          set -euo pipefail\n          eval`, `        run: |\n          set -euo pipefail\n          eval`,
      'prepare-native does not build the darwin-x64 source cjbind'],
    [` --cjbind-source-commit "$CJBIND_COMMIT"'`, `'`, 'prepare-native does not hand the darwin-x64 source cjbind to install-hle'],
    [`          CJBIND_FILE: \${{ steps.cjbind.outputs.file }}\n`, `          CJBIND_FILE: \${{ steps.other.outputs.file }}\n`,
      'prepare-native does not hand the darwin-x64 source cjbind to install-hle']];
  for (const [from, to, problem] of cuts) {
    console.log('PREPARE_CJBIND_WIRING_CUT_REACHED ' + problem);
    assert.ok(prepareWorkflowProblems({...real(), prepare: once(read('prepare'), from, to)}).includes(problem), from);
  }
});

// ---- default prepare pair, Mach-O symbols, std AST headers, the formal nativeN check ----
const pinStep = path.join(root, 'ci/native-llvm-inputs.mjs');
const prepareCli = path.join(root, 'build/sdk/producers/release/prepare_native_inputs.mjs');
const cli = (file, args, environment) => spawnSync(process.execPath, [file, ...args], {encoding: 'utf8', env: environment});
const jobEnv = inputs => ({...Object.fromEntries(Object.entries(process.env)
  .filter(([key]) => !key.startsWith('CJCJ_NATIVE_') && !['GITHUB_ENV', 'GITHUB_OUTPUT'].includes(key))), ...inputs});
// prepare-native: job env from the form inputs; step 1 is the real pin step
// (writes GITHUB_ENV); step 2 inherits the job env overlaid with what step 1 wrote.
function chained(t, inputs) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-pin-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const githubEnv = path.join(dir, 'github-env');
  fs.writeFileSync(githubEnv, '');
  const pin = cli(pinStep, [], {...jobEnv(inputs), GITHUB_ENV: githubEnv});
  assert.equal(pin.status, 0, pin.stderr);
  const written = Object.fromEntries(fs.readFileSync(githubEnv, 'utf8').split('\n').filter(Boolean)
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
  return {dir, written, step: {...jobEnv(inputs), ...written}};
}
const formDefault = {CJCJ_NATIVE_LLVM_REF: '', CJCJ_NATIVE_RUNTIME_REF: '', CJCJ_NATIVE_HOST_VERSION: ''};
test('default prepare: the pin step and install-host chained through GITHUB_ENV select the pinned host on all five hosts', t => {
  for (const host of PREPARE_HOSTS) {
    const {written, step} = chained(t, formDefault);
    assert.match(written.CJCJ_NATIVE_LLVM_REF, /^[0-9a-f]{40}$/);
    assert.equal(written.CJCJ_NATIVE_PAIR_SELECTION, 'pinned');
    const selected = cli(prepareCli, ['host-version', '--target', host.target], step);
    assert.equal(selected.status, 0, `${host.target}: ${selected.stderr}`);
    assert.equal(selected.stdout.trim(), prepareHostVersion(host.target, {}));
  }
});
test('red cut: an explicit pair without a host version is refused after the pin step; a forged pinned marker is refused', t => {
  const llvmPin = readSourcePinsForTest('llvm_pin.env').LLVM_SHA, runtimePin = readSourcePinsForTest('runtime_pin.env').RUNTIME_REF;
  const {dir, written, step} = chained(t, {CJCJ_NATIVE_LLVM_REF: llvmPin, CJCJ_NATIVE_RUNTIME_REF: runtimePin, CJCJ_NATIVE_HOST_VERSION: ''});
  assert.equal(written.CJCJ_NATIVE_PAIR_SELECTION, 'explicit');
  for (const command of ['host-version', 'install-host']) {
    const refused = cli(prepareCli, [command, '--root', path.join(dir, 'root'), '--target', 'linux-x64'], step);
    assert.equal(refused.status, 1, command);
    assert.match(refused.stderr, /NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED/, command);
  }
  assert.ok(!fs.existsSync(path.join(dir, 'root')), 'refused before any host download');
  const withHost = cli(prepareCli, ['host-version', '--target', 'linux-x64'], {...step, CJCJ_NATIVE_HOST_VERSION: prepareHostVersion('linux-x64', {})});
  assert.equal(withHost.status, 0, withHost.stderr);
  const forged = cli(prepareCli, ['host-version', '--target', 'linux-x64'], {...step, CJCJ_NATIVE_PAIR_SELECTION: 'pinned', CJCJ_NATIVE_LLVM_REF: LLVM});
  assert.equal(forged.status, 1);
  assert.match(forged.stderr, /NATIVE_PAIR_SELECTION_NOT_PINNED/);
  assert.throws(() => nativePairSelection({CJCJ_NATIVE_PAIR_SELECTION: 'maybe'}), /NATIVE_PAIR_SELECTION_INVALID maybe/);
  // a second pin step in the same job keeps the pinned selection it exported
  const again = cli(pinStep, [], {...chained(t, formDefault).step});
  assert.match(again.stdout, /CJCJ_NATIVE_PAIR_SELECTION=pinned/);
});
function readSourcePinsForTest(file) {
  return Object.fromEntries(fs.readFileSync(path.join(root, 'ci', file), 'utf8').split(/\r?\n/).filter(line => /^[A-Z][A-Z0-9_]*=/.test(line))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}
test('the LLVM library symbol check accepts the ELF and Mach-O names of the C symbol and nothing else', () => {
  assert.deepEqual(llvmLibrarySymbolProblems('00000000012a4560 T LLVMInitializeX86TargetInfo@@LLVM_15\n'), []);
  assert.deepEqual(llvmLibrarySymbolProblems('0000000000a1c000 T _LLVMInitializeX86TargetInfo\n'), []);
  assert.deepEqual(llvmLibrarySymbolProblems('0000000000a1c000 T LLVMInitializeX86TargetInfo\r\n'), []);
  for (const nm of ['', '0000 T _LLVMInitializeX86TargetInfoX\n', '0000 T XLLVMInitializeX86TargetInfo\n',
    '0000 T __LLVMInitializeX86TargetInfo\n', '0000 T _LLVMInitializeARMTargetInfo\n'])
    assert.deepEqual(llvmLibrarySymbolProblems(nm), ['LLVMInitializeX86TargetInfo'], JSON.stringify(nm));
});
test('install-ast installs Parse/Parser.h and the header tree std reads from the AST include root', t => {
  const {dir, root: prepared} = produced(t, 'linux-x64');
  const facts = JSON.parse(fs.readFileSync(path.join(prepared, 'ast/BUILD-INPUTS.json'), 'utf8'));
  const std = selectedStdAst({ast: {install: path.join(prepared, 'ast'), astInstallation: facts.astInstallation}, compiler: {}});
  // sdk-native-stage.mjs STD_AST_HEADER reads these under the same include root.
  for (const rel of ['cangjie/Parse/Parser.h', 'cangjie/CHIR/IR/AttributeInfo.h', 'cangjie/AST/Node.h'])
    assert.ok(fs.statSync(path.join(std.include, rel)).isFile(), rel);
  assert.equal(facts.astInstallation.headers.root, 'include/cangjie');
  assert.equal(facts.astInstallation.headers.files, 3);
  const without = path.join(dir, 'ast-out-no-parser');
  fs.cpSync(path.join(dir, 'ast-out'), without, {recursive: true});
  fs.rmSync(path.join(without, 'include/cangjie/Parse/Parser.h'));
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-ast-'));
  t.after(() => fs.rmSync(empty, {recursive: true, force: true}));
  assert.throws(() => installAst({root: empty, target: 'linux-x64', from: without, commits: {llvm: LLVM, runtime: RUNTIME, compiler: COMPILER}}),
    /NATIVE_INPUTS_PRODUCER_OUTPUT_MISSING include\/cangjie\/Parse\/Parser\.h/);
});
test('the LLDB build Python identity must be the selected prefix', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-python-')); t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const file = rel => { fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive: true}); fs.writeFileSync(path.join(dir, rel), rel); return path.join(dir, rel); };
  const selected = {executable: file('p/bin/python3.11'), include: path.dirname(file('p/include/python3.11/Python.h')),
    library: file('p/lib/libpython3.11.so.1.0'), suffix: '.cpython-311-x86_64-linux-gnu.so'};
  const cache = (executable, suffix = selected.suffix) => { fs.mkdirSync(path.join(dir, 'build'), {recursive: true});
    fs.writeFileSync(path.join(dir, 'build/CMakeCache.txt'), `Python3_EXECUTABLE:FILEPATH=${executable}\nPython3_INCLUDE_DIR:PATH=${selected.include}\n`
      + `Python3_LIBRARY:FILEPATH=${selected.library}\nLLDB_PYTHON_EXT_SUFFIX:STRING=${suffix}\n`); return path.join(dir, 'build'); };
  assert.deepEqual(pythonCacheConfiguration({selected, build: cache(selected.executable)}).actual.executable, selected.executable);
  assert.throws(() => pythonCacheConfiguration({selected, build: cache(file('other/bin/python3.11'))}), /PREPARE_LLDB_PYTHON_IDENTITY executable/);
  assert.throws(() => pythonCacheConfiguration({selected, build: cache(selected.executable, '.so')}), /PREPARE_LLDB_PYTHON_IDENTITY suffix/);
});
test('prepare N reaches the formal nativeN check with its library digest, verifier tools and Python input',
  {skip: process.platform !== 'linux' || process.arch !== 'x64'}, async t => {
  const {dir, root: prepared} = produced(t, 'linux-x64');
  const native = sdkPlatform('linux_x86_64');
  const {locations} = assembleNativeInputs({root: prepared, target: 'linux-x64', hostVersion: '1.1.0', env, pins});
  // This runner's verifier tools, found on PATH (sdk-native-capi.mjs: cmake, clang++, ninja).
  const bin = path.join(dir, 'verifier-bin'); fs.mkdirSync(bin);
  for (const name of ['cmake', 'clang++', 'ninja'])
    fs.writeFileSync(path.join(bin, name), `#!/bin/sh\necho NATIVE_VERIFIER_${name}_REACHED >&2\nexit 7\n`, {mode: 0o755});
  const resolved = await nativeInstallationLocations(prepared, locations, {PATH: bin});
  assert.deepEqual(Object.keys(resolved.llvm.verification.tools), ['cmake', 'clang++', 'ninja']);
  const facts = JSON.parse(fs.readFileSync(resolved.llvm.buildResult, 'utf8'));
  // sdk-inputs.mjs carries the library digest and the Python record from the N facts.
  const carried = {...resolved.llvm.verification, librarySha256: facts.llvmLibrary.sha256,
    python: {record: path.join(resolved.llvm.install, facts.pythonInstallationInput.record), sha256: facts.pythonInstallationInput.sha256}};
  const row = (sha, name) => ({commit: sha, tree: 'a'.repeat(40), repository: path.join(prepared, name), install: path.join(prepared, name),
    configuration: {}, buildResult: path.join(prepared, name, 'BUILD-INPUTS.json'), sourceRoot: path.join(prepared, name)});
  const nativeN = verification => {
    const runtimeRow = row(RUNTIME, 'runtime');
    const graph = createBootstrapTargets({platform: 'linux_x86_64', work: path.join(dir, 'work'), install: path.join(dir, 'stage'),
      llvmCommit: LLVM, runtimeCommit: RUNTIME, astCommit: COMPILER,
      host: {version: FIXED_INPUTS.host, install: path.join(prepared, 'host')}, llvm: {...row(LLVM, 'llvm'), ...resolved.llvm, verification},
      runtime: runtimeRow, ast: row(COMPILER, 'ast'), h1: row(FIXED_INPUTS.h1, 'h1'), compiler: row('b'.repeat(40), 'compiler'),
      stdlib: runtimeRow, tools: {cc: 'clang', cxx: 'clang++', launcher: 'sccache', zx: 'zx'}});
    const argv = graph.stages.find(stage => stage.id === 'nativeN').test.commands[0].argv;
    const run = spawnSync(argv[0], argv.slice(1), {encoding: 'utf8'});
    return {request: JSON.parse(argv[2]), status: run.status, output: `${run.stdout}${run.stderr}`};
  };
  const reached = nativeN(carried);
  for (const key of ['librarySha256', 'tools', 'python']) assert.ok(reached.request[key], key);
  // The check ran this runner's cmake for the C API probe: rc is that tool's 7.
  assert.equal(reached.status, 7, reached.output);
  assert.doesNotMatch(reached.output, /NATIVE_LLVM_ORIGINAL_INPUT_REQUIRED|LLVM_DYLIB_SHA256|LLVM_DYLIB_STAMP|ENTRY_FORMAT|TOOL_IDENTITY/);
  assert.match(reached.output, /NATIVE_VERIFIER_cmake_REACHED/);
  // red cut: the same N row without its verification inputs (the 268c1df locations)
  const missing = nativeN({librarySha256: facts.llvmLibrary.sha256});
  assert.equal(missing.status, 1);
  assert.match(missing.output, /NATIVE_LLVM_ORIGINAL_INPUT_REQUIRED/);
  // red cut: a library that is not the recorded original input never reaches the probe
  fs.appendFileSync(path.join(resolved.llvm.install, 'third_party/llvm', native.llvmDirectory, native.llvmLibrary), 'x');
  const changed = nativeN(carried);
  assert.equal(changed.status, 1);
  assert.match(changed.output, /LLVM_DYLIB_SHA256/);
  assert.doesNotMatch(changed.output, /NATIVE_VERIFIER_cmake_REACHED/);
});
test('Darwin and Windows prepare N carry the pinned Python input and clang resources to nativeN and stage0-run', async t => {
  for (const target of ['darwin-x64', 'darwin-arm64', 'windows-x64']) {
    const platform = PREPARE_HOSTS.find(h => h.target === target).llvm_platform, L = pythonLayout(platform);
    const {dir, root: prepared} = produced(t, target);
    const {locations} = assembleNativeInputs({root: prepared, target, hostVersion: '1.1.0', env, pins});
    const bin = path.join(dir, 'verifier-bin'); fs.mkdirSync(bin);
    for (const name of ['cmake', 'clang++', 'ninja'])
      fs.writeFileSync(path.join(bin, name), `#!/bin/sh\nexit 7\n`, {mode: 0o755});
    const resolved = await nativeInstallationLocations(prepared, locations, {PATH: bin});
    const facts = JSON.parse(fs.readFileSync(resolved.llvm.buildResult, 'utf8'));
    // The N the actual installLlvm wrote has the Python record, bound to the pinned prefix archive.
    assert.ok(facts.pythonInstallationInput, target);
    const record = path.join(resolved.llvm.install, facts.pythonInstallationInput.record);
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(record)).digest('hex'), facts.pythonInstallationInput.sha256);
    assert.deepEqual(JSON.parse(fs.readFileSync(record, 'utf8')).source, {url: PREPARE_PYTHON[platform].url,
      version: '3.11.9', sha256: PREPARE_PYTHON[platform].sha256});
    for (const rel of [L.interpreter, L.header, L.library])
      assert.ok(fs.existsSync(path.join(resolved.llvm.install, 'third_party/llvm', rel)), target + ' ' + rel);
    // sdk-inputs.mjs carries exactly this record (fixed path, matching digest) into the N verification.
    assert.equal(facts.pythonInstallationInput.record, PREPARE_PYTHON_RECORD);
    const carried = {...resolved.llvm.verification, librarySha256: facts.llvmLibrary.sha256,
      python: {record, sha256: facts.pythonInstallationInput.sha256}};
    // The graph's nativeN request carries it, so CJDB_PYTHON_NATIVE_INPUT_REQUIRED is not the first error.
    const row = (sha, name) => ({commit: sha, tree: 'a'.repeat(40), repository: path.join(prepared, name), install: path.join(prepared, name),
      configuration: {}, buildResult: path.join(prepared, name, 'BUILD-INPUTS.json'), sourceRoot: path.join(prepared, name)});
    const runtimeRow = row(RUNTIME, 'runtime');
    const graph = createBootstrapTargets({platform, work: path.join(dir, 'work'), install: path.join(dir, 'stage'),
      llvmCommit: LLVM, runtimeCommit: RUNTIME, astCommit: COMPILER,
      host: {version: FIXED_INPUTS.host, install: path.join(prepared, 'host')},
      llvm: {...row(LLVM, 'llvm'), ...resolved.llvm, verification: carried},
      runtime: runtimeRow, ast: row(COMPILER, 'ast'), h1: row(FIXED_INPUTS.h1, 'h1'), compiler: row('b'.repeat(40), 'compiler'),
      stdlib: runtimeRow, tools: {cc: 'clang', cxx: 'clang++', launcher: 'sccache', zx: 'zx'}});
    const request = JSON.parse(graph.stages.find(stage => stage.id === 'nativeN').test.commands[0].argv[2]);
    assert.deepEqual(request.python, {record, sha256: facts.pythonInstallationInput.sha256}, target);
    // stage0-run's installation recipe copies N's clang resources; that member now exists in N.
    const copy = graph.stages.find(stage => stage.id === 'stage0-run').copies.find(row => row.owner === 'N clang resources');
    assert.ok(copy && fs.existsSync(path.join(copy.from, '15.0.4/include/stddef.h')), target);
  }
});
// stage1-initial .. final: every installation recipe that copies N's lib/<tuple>
// (ci/bootstrap/sdk-targets.mjs installationRecipe) reads it from prepare N, and
// the real installer (ci/bootstrap/sdk-flow.mjs copyOutputs) installs the
// compiler-rt libraries the N facts record, on all five hosts.
for (const host of PREPARE_HOSTS) test(`${host.target}: every installation recipe installs prepare N's lib/<tuple> compiler-rt libraries`, async t => {
  const platform = host.llvm_platform, native = sdkPlatform(platform), tuple = native.tuple;
  const {dir, root: prepared} = produced(t, host.target);
  const {locations} = assembleNativeInputs({root: prepared, target: host.target, hostVersion: '1.1.0', env, pins});
  const resolved = await nativeInstallationLocations(prepared, locations, {});
  const facts = JSON.parse(fs.readFileSync(resolved.llvm.buildResult, 'utf8'));
  const names = compilerRtLibraries(platform).map(row => row.name);
  assert.deepEqual(facts.targetLibraries.map(row => row.path), names.map(name => `lib/${tuple}/${name}`));
  const row = (sha, name) => ({commit: sha, tree: 'a'.repeat(40), repository: path.join(prepared, name), install: path.join(prepared, name),
    configuration: {}, buildResult: path.join(prepared, name, 'BUILD-INPUTS.json'), sourceRoot: path.join(prepared, name)});
  const runtimeRow = row(RUNTIME, 'runtime');
  const graph = createBootstrapTargets({platform, work: path.join(dir, 'work'), install: path.join(dir, 'stage'),
    llvmCommit: LLVM, runtimeCommit: RUNTIME, astCommit: COMPILER,
    host: {version: FIXED_INPUTS.host, install: path.join(prepared, 'host')},
    llvm: {...row(LLVM, 'llvm'), ...resolved.llvm, verification: {...resolved.llvm.verification, librarySha256: facts.llvmLibrary.sha256}},
    runtime: runtimeRow, ast: row(COMPILER, 'ast'), h1: row(FIXED_INPUTS.h1, 'h1'), compiler: row('b'.repeat(40), 'compiler'),
    stdlib: runtimeRow, tools: {cc: 'clang', cxx: 'clang++', launcher: 'sccache', zx: 'zx'}});
  const libraryCopy = stage => (stage.copies || []).filter(copy => copy.owner === 'N' && copy.to === 'lib/' + tuple);
  const consumers = graph.stages.filter(stage => libraryCopy(stage).length);
  const final = graph.stages.find(stage => stage.output === '${install}');
  const ids = consumers.map(stage => stage.id);
  for (const id of ['stage1-initial', final.id]) assert.ok(ids.includes(id), `${host.target} ${id} copies N lib/${tuple}: ${ids}`);
  console.log(`LIBTUPLE_RECIPE_CONSUMERS ${host.target} final=${final.id} ${ids.join(',')}`);
  const absent = () => graph.stages.flatMap(stage => (stage.copies || [])
    .filter(copy => copy.from.startsWith(resolved.llvm.install + '/') && !fs.existsSync(copy.from))
    .map(copy => stage.id + ' ' + copy.from.slice(resolved.llvm.install.length + 1)));
  assert.deepEqual(absent(), [], host.target);
  for (const stage of consumers) {
    const sdk = path.join(dir, 'sdk-' + stage.id);
    await copyOutputs(sdk, libraryCopy(stage));
    assert.deepEqual(fs.readdirSync(path.join(sdk, 'lib', tuple)).sort(), [...names].sort(), stage.id);
    for (const library of facts.targetLibraries)
      assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(sdk, library.path))).digest('hex'), library.sha256, stage.id);
  }
  // red cut: the prepare N without lib/<tuple> (6683f8e) is absent from exactly these recipes, and the installer stops
  fs.rmSync(path.join(resolved.llvm.install, 'lib', tuple), {recursive: true});
  assert.deepEqual(absent(), consumers.map(stage => `${stage.id} lib/${tuple}`), host.target);
  console.log(`LIBTUPLE_RED_CUT_REACHED ${host.target} ${absent().length} recipes lack lib/${tuple}`);
  await assert.rejects(copyOutputs(path.join(dir, 'sdk-cut'), libraryCopy(consumers[0])), /ENOENT/);
});
// The five-host lib/<tuple> contract is cangjie_compiler's CLANG_RT_LIBS
// (third_party/CMakeLists.txt, both fixed fixtures) and what the driver links.
test('prepare N lib/<tuple> is the cangjie_compiler CLANG_RT_LIBS set on each of the five hosts', () => {
  for (const fixture of ['compiler-174db8f', 'compiler-41b223-windows']) {
    const cmake = fs.readFileSync(path.join(root, 'build/test/fixtures', fixture, 'third_party/CMakeLists.txt'), 'utf8');
    for (const line of ['set(LIB_PROFILE_NAME libclang_rt-${LIB_PROFILE}.a)', 'set(LIB_BUILTINS_NAME libclang_rt.osx.a)',
      'set(LIB_BUILTINS_NAME libclang_rt-${LIB_BUILTINS}.a)', 'set(LIB_FUZZER_NOMAIN_NAME libclang_rt.${LIB_FUZZER_NOMAIN}.a)',
      'set(LIB_PROFILE profile)', 'set(LIB_FUZZER_NOMAIN fuzzer_no_main)', 'set(LIB_BUILTINS builtins)',
      'install(FILES ${CLANG_RT_LIBS} DESTINATION lib/${output_lib_dir}${SANITIZER_SUBPATH})'])
      assert.ok(cmake.includes(line), fixture + ': ' + line);
    assert.match(cmake, /if\(\$\{CMAKE_SYSTEM_PROCESSOR\} STREQUAL "x86_64" OR DARWIN\)\n\s+list\(APPEND CLANG_RT_LIBS \$\{LIB_BUILTINS_PATH\}\)\n\s+endif\(\)\n\s+list\(APPEND CLANG_RT_LIBS \$\{LIB_PROFILE_PATH\}\)\n\s+if\(NOT WIN32 AND NOT IOS\)\n\s+list\(APPEND CLANG_RT_LIBS \$\{LIB_FUZZER_NOMAIN_PATH\}\)/, fixture);
  }
  const installed = Object.fromEntries(PREPARE_HOSTS.map(host => [host.target, compilerRtLibraries(host.llvm_platform).map(row => row.name)]));
  assert.deepEqual(installed, {
    'linux-x64': ['libclang_rt-builtins.a', 'libclang_rt-profile.a', 'libclang_rt.fuzzer_no_main.a'],
    'linux-aarch64': ['libclang_rt-profile.a', 'libclang_rt.fuzzer_no_main.a'],
    'windows-x64': ['libclang_rt-builtins.a', 'libclang_rt-profile.a'],
    'darwin-arm64': ['libclang_rt.osx.a', 'libclang_rt-profile.a', 'libclang_rt.fuzzer_no_main.a'],
    'darwin-x64': ['libclang_rt.osx.a', 'libclang_rt-profile.a', 'libclang_rt.fuzzer_no_main.a']});
  // none of them is supplied by the AST or std installation instead (sdk-targets.mjs nativeTargetLibraryExcludes)
  for (const names of Object.values(installed)) assert.deepEqual(names.filter(name => nativeTargetLibraryExcludes.includes(name)), []);
  // the driver links exactly these names (packages/driver, read only)
  const driver = name => fs.readFileSync(path.join(root, 'packages/driver/src', name), 'utf8');
  assert.match(driver('Linux_CJNATIVE.cj'), /if \(driverOptions\.target\.arch != ArchType\.AARCH64\) \{\n\s+tool\.AppendArg\("-lclang_rt-builtins"\)/);
  assert.ok(driver('Darwin_CJNATIVE.cj').includes('FileUtil.JoinPath(cangjieLibPath, "libclang_rt.osx.a")'));
  assert.ok(driver('MinGW_CJNATIVE.cj').includes('tool.AppendArg("-lclang_rt-builtins")'));
  assert.ok(driver('ToolChain.cj').includes('return "libclang_rt-profile.a"'));
});

// The fixed LLDB's Unix package carries two relative links (lldb/bindings/python/CMakeLists.txt
// finish_swig_python): _lldb -> liblldb and lldb-argdumper -> ../../../../bin/lldb-argdumper.
// The formal SDK path check accepts the installed N, and names the helper link once it is cut.
for (const host of PREPARE_HOSTS.filter(h => sdkPlatform(h.llvm_platform).os !== 'win32'))
  test(`${host.target}: the installed LLDB package links pass SDK path parity, and fail once the helper is cut`, async t => {
    const {assertSdkPathParity} = await import('../../../lib/sdk-path-parity.mjs');
    const {dir, root} = produced(t, host.target);
    const sdk = path.join(dir, 'sdk'), official = path.join(dir, 'official'); fs.mkdirSync(sdk); fs.mkdirSync(official);
    await copyOutputs(sdk, [{from: path.join(root, 'llvm/third_party/llvm'), to: 'third_party/llvm', owner: 'N'}]);
    await assertSdkPathParity(sdk, {officialRoot: official, target: host.target});
    fs.rmSync(path.join(sdk, 'third_party/llvm/bin/lldb-argdumper'));
    await assert.rejects(assertSdkPathParity(sdk, {officialRoot: official, target: host.target}), error => {
      assert.match(error.message, /package-link-invalid\tthird_party\/llvm\/lib\/python3\.11\/site-packages\/lldb\/lldb-argdumper\t\.\.\/\.\.\/\.\.\/\.\.\/bin\/lldb-argdumper/);
      assert.doesNotMatch(error.message, /_lldb/);
      return true;
    });
  });

// Windows LLDB copies liblldb.dll to _lldb*.pyd, so importing lldb maps LLDB under the
// binding's name only (sdk-cjdb-python.mjs verifyCjdbPythonInstallation).
test('windows_x86_64: the imported _lldb pyd is the LLDB module, and only from inside the install', async t => {
  const {verifyCjdbPythonInstallation} = await import('../../../../ci/bootstrap/sdk-cjdb-python.mjs');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cjdb-windows-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  const root = path.join(dir, 'third_party/llvm'), outside = path.join(dir, 'outside'), site = path.join(root, 'lib/python3.11/site-packages/lldb');
  const suffix = '.cp311-win_amd64.pyd', binding = path.join(site, '_lldb' + suffix);
  for (const rel of ['python.exe', 'python311.dll', 'bin/liblldb.dll', 'lib/python3.11/site-packages/lldb/__init__.py'])
    { fs.mkdirSync(path.dirname(path.join(root, rel)), {recursive: true}); fs.writeFileSync(path.join(root, rel), rel); }
  fs.copyFileSync(path.join(root, 'bin/liblldb.dll'), binding);
  fs.mkdirSync(outside);
  for (const name of ['python311.dll', 'liblldb.dll', '_lldb' + suffix]) fs.copyFileSync(binding, path.join(outside, name));
  const run = maps => verifyCjdbPythonInstallation(root, root, async command => command === 'dumpbin' ? {stdout: 'python311.dll'}
    : {stdout: JSON.stringify({lldb: path.join(site, '__init__.py'), binding, suffix, valid: true, maps}), stderr: ''}, 'windows_x86_64');
  const identity = /CJDB_PYTHON_IMPORT.*loaded library identity/;
  await run([path.join(root, 'python311.dll'), binding]);
  // red cuts: LLDB or Python mapped from outside the install, or no LLDB module at all
  for (const maps of [[path.join(root, 'python311.dll'), binding, path.join(outside, '_lldb' + suffix)],
    [path.join(root, 'python311.dll'), binding, path.join(outside, 'liblldb.dll')],
    [path.join(outside, 'python311.dll'), binding], [path.join(root, 'python311.dll')]])
    await assert.rejects(run(maps), identity);
});

for (const {target,llvm_platform:platform} of PREPARE_HOSTS) test(target + ': combined CMake installation survives the native tar and both readers',async t=>{
  const {dir,root,native}=produced(t,target), install=path.join(root,'llvm'), ast=path.join(root,'ast');
  const factsFile=path.join(install,'BUILD-INPUTS.json'), facts=JSON.parse(fs.readFileSync(factsFile));
  facts.astInstallation=JSON.parse(fs.readFileSync(path.join(ast,'BUILD-INPUTS.json'))).astInstallation;
  for(const name of fs.readdirSync(ast).filter(n=>n!=='BUILD-INPUTS.json'))
    fs.cpSync(path.join(ast,name),path.join(install,name),{recursive:true,verbatimSymlinks:true});
  fs.rmSync(ast,{recursive:true});
  facts.commits.shim=SHIM;
  const put=(file,body)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,body);};
  const nativeRoot=path.join(install,'third_party/llvm'), libdir=path.join(nativeRoot,native.llvmDirectory);
  const liblldb=path.join(libdir,'liblldb'+native.shared);
  if(!fs.existsSync(liblldb))fs.copyFileSync(path.join(nativeRoot,'lib',pythonLayout(platform).lldb),liblldb);
  put(path.join(nativeRoot,'bin','clang'+native.exe),'clang');
  if(native.os==='win32')put(path.join(nativeRoot,'bin/lldb-argdumper.exe'),'argdumper');
  const libraries=['frontend','lsp'].map(key=>path.join(install,'tools',native.os==='win32'?'bin':'lib','libcangjie-'+key+native.shared));
  for(const lib of libraries)put(lib,'compiler dependency');
  const record=native.os==='win32'?'third_party/llvm/PYTHON-BUILD-INPUTS.json':'share/cjcj/build-inputs/python-original.json';
  const bytes=fs.readFileSync(path.join(install,PREPARE_PYTHON_RECORD));
  put(path.join(install,record),bytes);
  const sha256=crypto.createHash('sha256').update(bytes).digest('hex');
  if(native.os==='win32')facts.pythonInstallationInput={record,sha256};
  else {delete facts.pythonInstallationInput;facts.pythonSource={build:{originalInputs:{path:'/producer/python.json',sha256}}};}
  fs.writeFileSync(factsFile,JSON.stringify(facts));
  put(path.join(install,'include/cangjie/Utils/Casting.h'),'umbrella header');
  checkSuperbuildInstall(install,platform);
  for(const file of libraries){
    fs.renameSync(file,file+'.hold');
    assert.throws(()=>checkSuperbuildInstall(install,platform),e=>e.message==='PREPARE_NATIVE_FILE '+file);
    fs.renameSync(file+'.hold',file);
  }
  const input={root,target,env:{...env,CJCJ_NATIVE_LLVM_REF:LLVM,CJCJ_NATIVE_RUNTIME_REF:RUNTIME},pins:{...pins,COMPILER_REF:COMPILER}};
  assert.throws(()=>assembleNativeInputs({...input,pins}),/PREPARE_NATIVE_SOURCE_PAIR/);
  assembleNativeInputs(input);
  const received=path.join(dir,'receiver');fs.mkdirSync(received);
  packNativeInputs({root,out:path.join(received,'native-inputs.tar')});
  unpackNativeArtifact({directory:received,archive:'native-inputs.tar'});
  fs.rmSync(root,{recursive:true});
  const locations=JSON.parse(fs.readFileSync(path.join(received,'locations.json')));
  const resolved=await nativeInstallationLocations(received,locations,{});
  assert.equal(resolved.ast.install,resolved.llvm.install);
  assert.deepEqual(resolved.llvm.verification.python,{record:path.join(received,'llvm',record),sha256});
  assert.deepEqual(fs.readFileSync(resolved.llvm.verification.python.record),bytes);
  await readInstalledNativeAst({...resolved.ast,platform,commit:COMPILER,llvmCommit:LLVM});
  await readInstalledNativeShim(resolved.shim);
});

// eb7ad012 lldb/tools/debugserver/source/CMakeLists.txt:162-187, byte for byte
// (sha256 2dc3ba30c8de4aefc822746200d6e5bbcc0b38f08509d419cbaeb53b921ac3a2): the
// energy probe and the mig rule that macos-15 (CMake 4.5.0) configured in run 45420757561.
const DEBUGSERVER_MIG_PINNED=[
  'if(${CMAKE_OSX_SYSROOT} MATCHES ".Internal.sdk$")',
  '  message(STATUS "LLDB debugserver energy support is enabled")',
  '  add_definitions(-DLLDB_ENERGY)',
  '  set(ENERGY_LIBRARY -lpmenergy -lpmsample)',
  'else()',
  '  message(STATUS "LLDB debugserver energy support is disabled")',
  'endif()',
  '',
  'set(generated_mach_interfaces',
  '  ${CMAKE_CURRENT_BINARY_DIR}/mach_exc.h',
  '  ${CMAKE_CURRENT_BINARY_DIR}/mach_excServer.c',
  '  ${CMAKE_CURRENT_BINARY_DIR}/mach_excUser.c',
  '  )',
  '',
  'set(MIG_ARCH_FLAGS "")',
  'if (DEFINED MIG_ARCHS)',
  '  foreach(ARCH ${MIG_ARCHS})',
  '    set(MIG_ARCH_FLAGS "${MIG_ARCH_FLAGS} -arch ${ARCH}")',
  '  endforeach()',
  'endif()',
  'separate_arguments(MIG_ARCH_FLAGS_SEPARTED NATIVE_COMMAND "${MIG_ARCH_FLAGS}")',
  '',
  'add_custom_command(OUTPUT ${generated_mach_interfaces}',
  '  VERBATIM COMMAND mig ${MIG_ARCH_FLAGS_SEPARTED} -isysroot ${CMAKE_OSX_SYSROOT} ${CMAKE_CURRENT_SOURCE_DIR}/MacOSX/dbgnub-mig.defs',
  '  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/MacOSX/dbgnub-mig.defs',
  '  )',
].join('\n')+'\n';
function putDarwinDebugserver(work){
  const dir=path.join(work,'lldb/tools/debugserver/source'),file=path.join(dir,'CMakeLists.txt'),defs=path.join(dir,'MacOSX/dbgnub-mig.defs');
  fs.mkdirSync(path.dirname(defs),{recursive:true});
  fs.writeFileSync(defs,'subsystem dbgnub 2401;\n');
  fs.writeFileSync(file,'cmake_minimum_required(VERSION 3.20)\nproject(debugserver_mig NONE)\n'+DEBUGSERVER_MIG_PINNED+
    'add_custom_target(mach_interfaces ALL DEPENDS ${generated_mach_interfaces})\n');
  return {dir,file,defs};
}
// Configure and build the debugserver fixture with argv-recording mig/xcrun stubs
// first on PATH; an argv is null when that tool never ran.
function runDebugserverMig(t,{dir},{define,xcrun}){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'prepare-mig-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const bin=path.join(root,'bin'),build=path.join(root,'build'),migArgv=path.join(root,'mig.argv'),xcrunArgv=path.join(root,'xcrun.argv');
  const record=file=>`for a in "$@"; do printf '%s\\0' "$a"; done > '${file}'\n`;
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin,'mig'),'#!/bin/sh\n'+record(migArgv),{mode:0o755});
  fs.writeFileSync(path.join(bin,'xcrun'),'#!/bin/sh\n'+record(xcrunArgv)+
    (xcrun.out===undefined?'':`printf '%s\\n' '${xcrun.out}'\n`)+`exit ${xcrun.rc??0}\n`,{mode:0o755});
  const env={...process.env,PATH:bin+path.delimiter+process.env.PATH};
  const argv=file=>fs.existsSync(file)?fs.readFileSync(file,'utf8').split('\0').slice(0,-1):null;
  const configure=spawnSync('cmake',['-G','Unix Makefiles','-S',dir,'-B',build,...define],{env,encoding:'utf8'});
  if(configure.status===0){
    const built=spawnSync('cmake',['--build',build],{env,encoding:'utf8'});
    assert.equal(built.status,0,built.stdout+built.stderr);
  }
  return {configure,mig:argv(migArgv),xcrun:argv(xcrunArgv)};
}
function putDarwinLldbPlugins(work){
  const put=(file,body)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,body);};
  for(const plugin of ['ExpressionParser/Cangjie','Platform/OHOS'])
    put(path.join(work,'lldb/source/Plugins',plugin,'CMakeLists.txt'),'string(REPLACE "AMD64" "x86_64" ARCH_NAME "${CMAKE_SYSTEM_PROCESSOR}")\n');
  put(path.join(work,'lldb/source/API/CMakeLists.txt'),'target_link_options(liblldb PUBLIC "-Wl,-rpath,${CMAKE_SOURCE_DIR}/../utils/boundscheck/lib/${CMAKE_SYSTEM_PROCESSOR}")\n');
}

test('Darwin standalone LLDB uses the parent boundscheck architecture and a relocatable install name',async t=>{
  const {prepareDarwinLldbSource}=await import('../../../srcbuild/stages/fetch.mjs');
  const work=fs.mkdtempSync(path.join(os.tmpdir(),'prepare-darwin-'));
  t.after(()=>fs.rmSync(work,{recursive:true,force:true}));
  const api=path.join(work,'lldb/source/API/CMakeLists.txt'), files=['ExpressionParser/Cangjie','Platform/OHOS'].map(plugin=>
    path.join(work,'lldb/source/Plugins',plugin,'CMakeLists.txt'));
  const put=(file,body)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,body);};
  for(const file of files)put(file,'string(REPLACE "AMD64" "x86_64" ARCH_NAME "${CMAKE_SYSTEM_PROCESSOR}")\nfile(WRITE "${OUT}" "${ARCH_NAME}")\n');
  put(api,'target_link_options(liblldb PUBLIC "-Wl,-rpath,${CMAKE_SOURCE_DIR}/../utils/boundscheck/lib/${CMAKE_SYSTEM_PROCESSOR}")\n');
  putDarwinDebugserver(work);
  prepareDarwinLldbSource(work);
  const before=[...files,api].map(f=>fs.readFileSync(f,'utf8'));
  prepareDarwinLldbSource(work);
  assert.deepEqual([...files,api].map(f=>fs.readFileSync(f,'utf8')),before);
  for(const file of files)for(const [processor,want] of [['arm64','aarch64'],['x86_64','x86_64']]){
    const out=path.join(work,'arch'),r=spawnSync('cmake',['-DCMAKE_SYSTEM_PROCESSOR='+processor,'-DOUT='+out,'-P',file]);
    assert.equal(r.status,0,r.stderr?.toString());
    assert.equal(fs.readFileSync(out,'utf8'),want);
  }
  assert.match(before[2],/target_link_options\(liblldb PRIVATE "-Wl,-rpath,@loader_path"\)/);
  assert.ok(!before[2].includes('CMAKE_SOURCE_DIR'));
});

test('Darwin debugserver hands mig a resolved SDK when CMake 4 leaves CMAKE_OSX_SYSROOT empty',
  {skip:process.platform==='win32'&&'POSIX mig/xcrun stubs'},async t=>{
  const {prepareDarwinLldbSource}=await import('../../../srcbuild/stages/fetch.mjs');
  const work=fs.mkdtempSync(path.join(os.tmpdir(),'prepare-darwin-mig-'));
  t.after(()=>fs.rmSync(work,{recursive:true,force:true}));
  assert.equal(crypto.createHash('sha256').update(DEBUGSERVER_MIG_PINNED).digest('hex'),
    '2dc3ba30c8de4aefc822746200d6e5bbcc0b38f08509d419cbaeb53b921ac3a2');
  putDarwinLldbPlugins(work);
  const debugserver=putDarwinDebugserver(work),empty=['-DCMAKE_OSX_SYSROOT='];
  const sdk='/Applications/Xcode 16.4.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk';
  // The pinned rule with CMake 4's empty default: dbgnub-mig.defs becomes the
  // -isysroot value and mig is left without an input file.
  const pinned=runDebugserverMig(t,debugserver,{define:empty,xcrun:{out:sdk}});
  assert.equal(pinned.configure.status,0,pinned.configure.stderr);
  assert.deepEqual(pinned.mig,['-isysroot',debugserver.defs]);
  assert.equal(pinned.xcrun,null);
  const original=fs.readFileSync(debugserver.file,'utf8');
  prepareDarwinLldbSource(work);
  const patched=fs.readFileSync(debugserver.file,'utf8');
  prepareDarwinLldbSource(work);
  assert.equal(fs.readFileSync(debugserver.file,'utf8'),patched);
  assert.ok(patched.startsWith(original.slice(0,original.indexOf('add_custom_command('))));
  const resolved=runDebugserverMig(t,debugserver,{define:[...empty,'-DMIG_ARCHS=arm64'],xcrun:{out:sdk}});
  assert.equal(resolved.configure.status,0,resolved.configure.stderr);
  assert.deepEqual(resolved.xcrun,['--sdk','macosx','--show-sdk-path']);
  assert.deepEqual(resolved.mig,['-arch','arm64','-isysroot',sdk,debugserver.defs]);
  const explicit=runDebugserverMig(t,debugserver,{define:['-DCMAKE_OSX_SYSROOT=/custom/sdk'],xcrun:{rc:1}});
  assert.equal(explicit.configure.status,0,explicit.configure.stderr);
  assert.equal(explicit.xcrun,null);
  assert.deepEqual(explicit.mig,['-isysroot','/custom/sdk',debugserver.defs]);
  for(const xcrun of [{rc:1,out:sdk},{rc:0}]){
    const failed=runDebugserverMig(t,debugserver,{define:empty,xcrun});
    assert.notEqual(failed.configure.status,0,JSON.stringify(xcrun));
    assert.match(failed.configure.stderr.replace(/\s+/g,' '),/CMAKE_OSX_SYSROOT is empty and 'xcrun --sdk macosx --show-sdk-path' gave no SDK for mig/);
    assert.deepEqual(failed.xcrun,['--sdk','macosx','--show-sdk-path']);
    assert.equal(failed.mig,null);
  }
});

test('Darwin debugserver mig patch fails closed on a drifted rule',async t=>{
  const {prepareDarwinLldbSource}=await import('../../../srcbuild/stages/fetch.mjs');
  const work=fs.mkdtempSync(path.join(os.tmpdir(),'prepare-darwin-mig-drift-'));
  t.after(()=>fs.rmSync(work,{recursive:true,force:true}));
  putDarwinLldbPlugins(work);
  const {file}=putDarwinDebugserver(work);
  fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace('-isysroot ${CMAKE_OSX_SYSROOT} ','-isysroot ${SDKROOT} '));
  assert.throws(()=>prepareDarwinLldbSource(work),/patch shape drift/);
});

// eb7ad012 compiler-rt/lib/builtins/assembly.h:249-265, byte for byte (sha256
// pinned below): the private-function macro and the outline-atomic macro whose
// CFI frame Xcode 16.4 rejects (aarch64/lse.S, "non-private labels cannot appear
// between .cfi_startproc / .cfi_endproc pairs").
const ASSEMBLY_H_LINE = text => text.padEnd(79) + '\\';
const ASSEMBLY_H_EB7AD012 = [...['#define DEFINE_COMPILERRT_PRIVATE_FUNCTION_UNMANGLED(name)', '  DEFINE_CODE_STATE',
  '  .globl name SEPARATOR', '  SYMBOL_IS_FUNC(name) SEPARATOR', '  HIDDEN(name) SEPARATOR', '  DECLARE_FUNC_ENCODING'].map(ASSEMBLY_H_LINE),
  '  name:', '', ...['#define DEFINE_COMPILERRT_OUTLINE_FUNCTION_UNMANGLED(name)', '  DEFINE_CODE_STATE', '  FUNC_ALIGN',
  '  .globl name SEPARATOR', '  SYMBOL_IS_FUNC(name) SEPARATOR', '  DECLARE_SYMBOL_VISIBILITY_UNMANGLED(name) SEPARATOR',
  '  CFI_START SEPARATOR', '  DECLARE_FUNC_ENCODING'].map(ASSEMBLY_H_LINE), '  name: SEPARATOR BTI_C', ''].join('\n');
const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
const outlineMacro = text => /#define DEFINE_COMPILERRT_OUTLINE_FUNCTION_UNMANGLED\(name\)((?:.*\\\n)*.*)/.exec(text)[1]
  .split(/\s*\\\n\s*/).map(part => part.trim()).filter(Boolean);

// The xray x86_64 trampoline's branch targets, jump then definition, as eb7ad012 spells them.
async function writeXrayFixture(work) {
  const {DARWIN_XRAY_X86_64_LOCAL_LABELS} = await import('../../../srcbuild/stages/fetch.mjs');
  const file = path.join(work, 'compiler-rt/lib/xray/xray_trampoline_x86_64.S');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, DARWIN_XRAY_X86_64_LOCAL_LABELS.map(name => `\tje\t.L${name}\n.L${name}:\n`).join(''));
  return file;
}

test('Darwin compiler-rt outline atomics name their global label before opening the CFI frame', async t => {
  const {prepareDarwinCompilerRtSource} = await import('../../../srcbuild/stages/fetch.mjs');
  assert.equal(sha256(ASSEMBLY_H_EB7AD012), '981c94078f5ae46f9b8d165f71fc09b6d4ebff5734f78ac3f523db8aea21969f');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-darwin-crt-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const file = path.join(work, 'compiler-rt/lib/builtins/assembly.h');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, '#include "int_lib.h"\n' + ASSEMBLY_H_EB7AD012 + '#define END_COMPILERRT_FUNCTION(name)\n');
  assert.deepEqual(outlineMacro(fs.readFileSync(file, 'utf8')).slice(-3), ['CFI_START SEPARATOR', 'DECLARE_FUNC_ENCODING', 'name: SEPARATOR BTI_C']);
  await writeXrayFixture(work);
  prepareDarwinCompilerRtSource(work);
  const patched = fs.readFileSync(file, 'utf8');
  prepareDarwinCompilerRtSource(work);
  assert.equal(fs.readFileSync(file, 'utf8'), patched);
  // The same bytes the eb7ad012 header gives after this patch, which clang
  // --target=arm64-apple-macos11 assembles for all 100 lse.S helpers.
  assert.equal(sha256(patched.slice('#include "int_lib.h"\n'.length, -'#define END_COMPILERRT_FUNCTION(name)\n'.length)),
    '7afaaa9c522f2f7ecac67eb13fe8ee418fbc3ad4ae9450db74bb1351342a65be');
  const body = outlineMacro(patched);
  assert.deepEqual(body, ['DEFINE_CODE_STATE', 'FUNC_ALIGN', '.globl name SEPARATOR', 'SYMBOL_IS_FUNC(name) SEPARATOR',
    'DECLARE_SYMBOL_VISIBILITY_UNMANGLED(name) SEPARATOR', 'DECLARE_FUNC_ENCODING', 'name: SEPARATOR', 'CFI_START SEPARATOR BTI_C']);
  assert.ok(patched.split('\n').every(line => !line.endsWith('\\') || line.length === 80), 'continuations stay in column 80');
  assert.ok(patched.includes(ASSEMBLY_H_EB7AD012.split('\n\n')[0]), 'the private-function macro is untouched');
});

test('red cut: a drifted compiler-rt assembly.h anchor fails closed and stays untouched', async t => {
  const {prepareDarwinCompilerRtSource} = await import('../../../srcbuild/stages/fetch.mjs');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-darwin-crt-drift-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const file = path.join(work, 'compiler-rt/lib/builtins/assembly.h');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  for (const drifted of [ASSEMBLY_H_EB7AD012.replace('  CFI_START SEPARATOR ', '  CFI_START   SEPARATOR'),
    ASSEMBLY_H_EB7AD012.replace('  name: SEPARATOR BTI_C', '  name: SEPARATOR'), ASSEMBLY_H_EB7AD012.replaceAll(' '.repeat(10) + '\\', '\t\\')]) {
    assert.notEqual(drifted, ASSEMBLY_H_EB7AD012);
    fs.writeFileSync(file, drifted);
    assert.throws(() => prepareDarwinCompilerRtSource(work), /patch shape drift/);
    assert.equal(fs.readFileSync(file, 'utf8'), drifted);
  }
  fs.rmSync(file);
  assert.throws(() => prepareDarwinCompilerRtSource(work));
});

// Control arm on the real pinned sources: Mach-O rejects the unpatched trampoline
// exactly as Xcode 16.4 did (run 45385716455 step 5510/6066); the patched one
// assembles for x86_64-apple-macos and keeps assembling for x86_64 ELF.
const LLVM_SOURCE = process.env.CJCJ_LLVM_SOURCE || '/root/cj_build/llvm_rebase';
const XRAY_INPUTS = ['xray/xray_trampoline_x86_64.S', 'builtins/assembly.h', 'sanitizer_common/sanitizer_asm.h'];
test('Darwin xray x86_64 trampoline uses assembler-local labels that Mach-O and ELF both assemble', async t => {
  const {prepareDarwinCompilerRtSource} = await import('../../../srcbuild/stages/fetch.mjs');
  const real = XRAY_INPUTS.map(name => path.join(LLVM_SOURCE, 'compiler-rt/lib', name));
  if (!real.every(file => fs.existsSync(file))) return t.skip(`no compiler-rt sources under ${LLVM_SOURCE}`);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-darwin-xray-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  XRAY_INPUTS.forEach((name, i) => {
    const to = path.join(work, 'compiler-rt/lib', name);
    fs.mkdirSync(path.dirname(to), {recursive: true});
    fs.copyFileSync(real[i], to);
  });
  const file = path.join(work, 'compiler-rt/lib/xray/xray_trampoline_x86_64.S');
  const clang = spawnSync('clang', ['--version'], {encoding: 'utf8'}).status === 0;
  const assemble = target => spawnSync('clang', [`--target=${target}`, '-c', file, '-o', path.join(work, `${target}.o`)], {encoding: 'utf8'});
  if (clang) {
    const before = assemble('x86_64-apple-macos10.13');
    assert.notEqual(before.status, 0);
    assert.match(before.stderr, /invalid CFI advance_loc expression/);
  }
  prepareDarwinCompilerRtSource(work);
  const patched = fs.readFileSync(file, 'utf8');
  prepareDarwinCompilerRtSource(work);
  assert.equal(fs.readFileSync(file, 'utf8'), patched, 'idempotent');
  assert.deepEqual(patched.match(/\.L[A-Za-z_]\w*/g), null, 'no .L label is left');
  assert.equal(patched.split('LOCAL_LABEL(').length - 1, 14);
  if (!clang) return t.skip('clang is not installed');
  for (const target of ['x86_64-apple-macos10.13', 'x86_64h-apple-macos10.13', 'x86_64-unknown-linux-gnu']) {
    const after = assemble(target);
    assert.equal(after.status, 0, `${target}: ${after.stderr}`);
  }
});

test('prepare-native patches the private LLVM checkout\'s compiler-rt on Darwin hosts only', () => {
  const source = fs.readFileSync(path.join(import.meta.dirname, 'prepare_native_superbuild.mjs'), 'utf8');
  assert.match(source, /^import \{[^}]*\bprepareDarwinCompilerRtSource\b[^}]*\} from '\.\.\/\.\.\/\.\.\/srcbuild\/stages\/fetch\.mjs';$/m);
  const darwin = /\n  if\(platform\.startsWith\('darwin_'\)\) \{\n([^}]*)\n  \}\n/.exec(source);
  assert.ok(darwin, 'prepareNativeSuperbuild keeps its Darwin source-preparation block');
  assert.deepEqual(darwin[1].split('\n').map(line => line.trim()).filter(line => /^prepareDarwin/.test(line)),
    ['prepareDarwinLldbSource(sources.llvm);', 'prepareDarwinCompilerRtSource(sources.llvm);']);
  assert.equal(source.split('prepareDarwinCompilerRtSource(').length - 1, 1, 'called once, inside the Darwin block');
  assert.ok(source.indexOf(darwin[0]) < source.indexOf('await nativeCjdb('), 'patched before the superbuild configures');
});

test('prepare.yml persists the one native sccache session that covers runtime and the LLVM superbuild', () => {
  const steps = loadYaml(fs.readFileSync(path.join(import.meta.dirname, '../../../../.github/workflows/prepare.yml'), 'utf8'))
    .jobs['prepare-native'].steps;
  const sccache = steps.filter(step => step.uses === './.github/actions/sccache');
  assert.equal(sccache.length, 2, JSON.stringify(sccache));
  const [start, report] = sccache, at = step => steps.indexOf(step);
  assert.equal(start.with.mode ?? 'start', 'start');
  assert.equal(start.with['cache-size'], '5G');
  assert.equal(start.with.component, 'native-runtime');
  const superbuild = steps.findIndex(step => String(step.run || '').includes('prepare_native_superbuild.mjs'));
  const runtime = steps.findIndex(step => String(step.run || '').includes('build_runtime.mjs'));
  assert.ok(at(start) < runtime && runtime < superbuild && superbuild < at(report));
  assert.equal(at(report), steps.length - 1, 'the report closes out the job');
  assert.equal(report.if, 'always()');
  assert.deepEqual(report.with, {mode: 'report', component: start.with.component, platform: start.with.platform,
    'require-compiles': "${{ job.status == 'success' }}"});
});

// Compiles the Python-facing C++ that SWIG would paste from python-typemaps.swig
// (the %{...%} helper block plus each integer typemap body) against real Python 3
// headers, which declare no PyInt_*: SWIG 4.5 no longer supplies those macros.
const LLDB_TYPEMAPS = '/root/cj_build/llvm_rebase/lldb/bindings/python/python-typemaps.swig';
const PYTHON3_INCLUDE = spawnSync('python3', ['-c', 'import sysconfig;print(sysconfig.get_paths()["include"])'], {encoding:'utf8'}).stdout?.trim();
function typemapTranslationUnit(text) {
  const body = start => {let depth = 0; for (let i = start; i < text.length; i++) {
    if (text[i] === '{') depth++; else if (text[i] === '}' && --depth === 0) return text.slice(start + 1, i);} throw Error('unbalanced');};
  const helper = /%\{\n((?:(?!%\})[\s\S])*SetNumberFromPyObject(?:(?!%\})[\s\S])*)%\}/.exec(text);
  assert.ok(helper, 'SetNumberFromPyObject helper block');
  const units = ['#include <Python.h>', '#include <cstdint>', '#include <cstdlib>', helper[1],
    'bool useNumbers(PyObject *o) {uint64_t a; uint32_t b; int32_t c; double d;',
    '  return SetNumberFromPyObject(a, o) && SetNumberFromPyObject(b, o) && SetNumberFromPyObject(c, o) && SetNumberFromPyObject(d, o);}'];
  const maps = [['in', '(char *dst, size_t dst_len)'], ['in', '(char *dst_or_null, size_t dst_len)'], ['in', '(void *buf, size_t size)'],
    ['argout', '(uint32_t *versions, uint32_t num_versions)']];
  maps.forEach(([kind, sig], n) => {
    const at = text.indexOf(`%typemap(${kind}) ${sig} {`); assert.ok(at >= 0, sig);
    const [t1, t2] = sig.slice(1, -1).split(',').map(p => p.trim().replace(/\w+$/, ''));
    const code = body(text.indexOf('{', at)).replaceAll('$input', 'input').replaceAll('$result', 'resultObj')
      .replaceAll('$1', 'arg1').replaceAll('$2', 'arg2');
    units.push(`PyObject *typemap${n}(PyObject *input) {${t1} arg1{}; ${t2} arg2{}; uint32_t result = 0; PyObject *resultObj = nullptr; (void)result;`,
      code, '  return resultObj;}');
  });
  return units.join('\n');
}
function compileTypemaps(text, dir, name) {
  const file = path.join(dir, name + '.cpp'); fs.writeFileSync(file, typemapTranslationUnit(text));
  return spawnSync('clang++', ['-std=c++17', '-fsyntax-only', '-Wno-everything', '-I' + PYTHON3_INCLUDE, file], {encoding:'utf8'});
}

test('prepare-native spells LLDB\'s SWIG typemaps with the Python 3 API on every host', {skip:!fs.existsSync(LLDB_TYPEMAPS) && 'pinned llvm source absent'}, async t => {
  const {prepareLldbSwigPython3Source, LLDB_SWIG_PYTHON3_MARKER} = await import('../../../srcbuild/stages/fetch.mjs');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-lldb-swig-'));
  t.after(() => fs.rmSync(work, {recursive:true, force:true}));
  const file = path.join(work, 'lldb/bindings/python/python-typemaps.swig');
  fs.mkdirSync(path.dirname(file), {recursive:true});
  const original = fs.readFileSync(LLDB_TYPEMAPS, 'utf8');
  fs.writeFileSync(file, original);
  assert.equal((original.match(/PyInt_/g) || []).length, 9, 'the pinned file carries the nine Python 2 calls seen on macos-15');
  prepareLldbSwigPython3Source(work);
  const patched = fs.readFileSync(file, 'utf8');
  assert.equal((patched.match(/\bPy(Int|String|File)_/g) || []).length, 0);
  assert.ok(patched.includes(LLDB_SWIG_PYTHON3_MARKER));
  const numbers = /bool SetNumberFromPyObject\(T &number, PyObject \*obj\) \{\n([\s\S]*?)\n\}/.exec(patched)[1];
  assert.deepEqual(numbers.split('\n').map(line => line.trim()).filter(Boolean),
    ['if (PyLong_Check(obj))', 'number = PyLongAsT<T>(obj);', 'else', 'return false;', 'return true;']);
  const buffer = /%typemap\(in\) \(void \*buf, size_t size\) \{\n([\s\S]*?)\n\}/.exec(patched)[1];
  assert.equal(buffer.split('PyLong_Check(').length - 1, 1, 'one integer branch, no duplicated PyLong_Check');
  assert.match(buffer, /^  if \(PyLong_Check\(\$input\)\) \{\n    \$2 = PyLong_AsLong\(\$input\);\n  \} else \{/);
  assert.equal(patched.split('\n').length, original.split('\n').length - 4, 'only the dead Python 2 branches are removed');
  prepareLldbSwigPython3Source(work);
  assert.equal(fs.readFileSync(file, 'utf8'), patched, 'idempotent');
  const source = fs.readFileSync(path.join(import.meta.dirname, 'prepare_native_superbuild.mjs'), 'utf8');
  const verify = source.indexOf('await verifyNativeSource({source,commit});\n  }\n'), call = source.indexOf('  prepareLldbSwigPython3Source(sources.llvm);\n');
  assert.ok(verify > 0 && call > verify && call < source.indexOf("if(platform.startsWith('darwin_'))") && call < source.indexOf('await nativeCjdb('),
    'patched after source verification, outside the Darwin block, before the superbuild configures');
  assert.equal(source.split('prepareLldbSwigPython3Source(').length - 1, 1);
  // Control arm: the same harness rejects the pinned text without SWIG's PyInt_* macros.
  const before = compileTypemaps(original, work, 'unpatched'), after = compileTypemaps(patched, work, 'patched');
  assert.notEqual(before.status, 0);
  for (const name of ['PyInt_Check', 'PyInt_AsLong', 'PyInt_FromLong']) assert.match(before.stderr, new RegExp(`undeclared identifier '${name}'`));
  assert.equal(after.status, 0, after.stderr);
});

test('Python 2 typemap text that drifts from the pinned shape fails closed', async t => {
  const {prepareLldbSwigPython3Source} = await import('../../../srcbuild/stages/fetch.mjs');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-lldb-swig-drift-'));
  t.after(() => fs.rmSync(work, {recursive:true, force:true}));
  const file = path.join(work, 'lldb/bindings/python/python-typemaps.swig');
  fs.mkdirSync(path.dirname(file), {recursive:true});
  fs.writeFileSync(file, 'template <class T> bool SetNumberFromPyObject(T &number, PyObject *obj) {\n  if (PyLong_Check(obj))\n    number = PyLongAsT<T>(obj);\n}\nPyObject *x = PyString_FromString("");\n');
  assert.throws(() => prepareLldbSwigPython3Source(work), /Python 2 API remains/);
  fs.writeFileSync(file, '  if (!PyInt_Check(input)) {\n');
  assert.throws(() => prepareLldbSwigPython3Source(work), /patch shape drift/);
});
