import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import crypto from 'node:crypto';
import {manifestSdkFixture} from './fixtures/manifest-sdk.mjs';
import {fileDigest} from '../../ci/bootstrap/sdk-manifest.mjs';
import {publishBootstrapStdOutput} from '../../ci/bootstrap/std-output.mjs';
import {prepareBootstrapHandoff, assertBootstrapCompiler} from '../../ci/srcbuild/lib/bootstrap-handoff.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(process.env.SDK_CONSUMER_TEST_ROOT || os.tmpdir(), 'bootstrap-handoff-'));
  if (!process.env.SDK_CONSUMER_TEST_ROOT) t.after(() => fs.rm(root, {recursive: true, force: true}));
  const work = path.join(root, 'bootstrap-work');
  const sdk = path.join(root, 'software', 'cangjie');
  await fs.mkdir(path.dirname(sdk), {recursive: true});
  const source = path.join(root, 'source');
  const tuple = 'linux_x86_64_cjnative';
  const write = async (name, contents) => {
    await fs.mkdir(path.dirname(name), {recursive: true});
    await fs.writeFile(name, contents, {mode: 0o755});
  };
  const inputSdk = path.join(work, 'sdk-stage1');
  await write(path.join(work, 'cjcj-stage2'), '#!/bin/bash\nprintf "compiler home=%s ld=%s\\n" "$CANGJIE_HOME" "$LD_LIBRARY_PATH"\n');
  await write(path.join(work, 'stdlib-stage2', 'lib', tuple, 'libcangjie-std-core.a'), 'coloured std');
  await write(path.join(inputSdk, 'lib', tuple, 'libcangjie-std-core.a'), 'bootstrap std');
  await write(path.join(inputSdk, '.stage1-host', 'binding.txt'), 'host_ld=/host/runtime:/host/llvm\n');
  await write(path.join(inputSdk, 'tools', 'bin', 'cjpm-stage1'), '#!/bin/bash\nprintf "cjpm home=%s ld=%s\\n" "$CANGJIE_HOME" "$LD_LIBRARY_PATH"\n"$CANGJIE_HOME/bin/cjc"\n');
  for (const name of ['cjselfhost_llvmshim.o', 'cjc_runtime_config.o']) await write(path.join(work, 'cjcj-src-stage1', 'runtime_shim', name), name);
  await fs.symlink('libcangjie-std-core.a', path.join(inputSdk, 'lib', tuple, 'core-relative.a'));
  await write(path.join(inputSdk, 'bin', 'cjc'), '#!/bin/bash\nprintf "old-stage1 compiler\\n"\n');
  await write(path.join(work, 'stdlib-stage2', 'modules', 'consumer-std.txt'), 'coloured std');
  await write(path.join(work, 'cjcj-stage1'), 'stage1 compiler');
  await write(path.join(work, 'stdlib-stage2', 'std-producer.json'), JSON.stringify({compiler_sha256: crypto.createHash('sha256').update('stage1 compiler').digest('hex')}));
  const f = {root, work, sdk, source, tuple};
  f.publish = async () => {
    // Preserve the mutable scenario script separately from its native ELF.
    const bytes = await fs.readFile(path.join(work, 'cjcj-stage2'));
    if (bytes.subarray(0, 2).toString() === '#!') f.compilerScript = bytes;
    await fs.writeFile(path.join(work, 'cjcj-stage2'), f.compilerScript);
    const native = await manifestSdkFixture({root, compiler: path.join(work, 'cjcj-stage2'),
      prefix: path.join(work, 'stdlib-stage2'), inputSdk, shimSource: path.join(work, 'cjcj-src-stage1/runtime_shim')});
    f.plans = native.plans; f.producer = path.join(work, 'cjcj-stage2'); f.producerSha256 = native.compilerSha256;
    await fs.copyFile(f.producer, path.join(work, 'cjcj-stage1'));
    await publishBootstrapStdOutput({...f, prefix: path.join(work, 'stdlib-stage2'), compiler: path.join(work, 'cjcj-stage1')});
  };
  f.consumerEnv = targetLd => ({...process.env, CANGJIE_HOME: sdk, LD_LIBRARY_PATH: targetLd});
  await write(path.join(work, 'stdlib-stage2', 'lib', tuple, 'core-relative.a'), 'bootstrap std');
  await f.publish();
  return f;
}

test('bootstrap handoff consumes stage2 std and compiler and rebinds host and target processes', async t => {
  const f = await fixture(t);
  const result = await prepareBootstrapHandoff(f);
  assert.equal(result.compiler, path.join(f.work, 'cjcj-stage2'));
  assert.equal((await fs.lstat(path.join(f.sdk, 'lib', f.tuple, 'core-relative.a'))).isFile(), true);
  assert.equal(await fs.readFile(path.join(f.sdk, 'lib', f.tuple, 'core-relative.a'), 'utf8'), 'bootstrap std');
  assert.equal(await fileDigest(path.join(f.sdk, 'lib', f.tuple, 'libcangjie-std-core.a')), await fileDigest(path.join(f.work, 'stdlib-stage2/lib', f.tuple, 'libcangjie-std-core.a')));
  await assert.rejects(fs.stat(path.join(f.sdk, 'stale-sdk')), {code: 'ENOENT'});
  const run = spawnSync(path.join(f.sdk, 'tools', 'bin', 'cjpm'), {encoding: 'utf8', env: f.consumerEnv(result.targetLd)});
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout, `cjpm home=${f.sdk} ld=${result.targetLd}\ncompiler home=${f.sdk} ld=${result.targetLd}\n`);
  for (const name of ['opt', 'llc']) {
    const backend = spawnSync(path.join(f.sdk, 'third_party', 'llvm', 'bin', name), ['--version'], {encoding: 'utf8', env: f.consumerEnv(result.targetLd)});
    assert.equal(backend.status, 0, backend.stderr);
    assert.match(backend.stdout, /LLVM version/);
    const installed = JSON.parse(await fs.readFile(path.join(f.sdk,'SDK.manifest.json'),'utf8'));
    const entry = installed.files[`third_party/llvm/bin/${name}`];
    assert.equal(await fileDigest(path.join(f.sdk,'third_party/llvm/bin',name)),entry.sha256,'actual target backend producer bytes');
    assert.equal(installed.components[entry.component].source.kind,'git');
  }
  assert.equal(await fs.readFile(path.join(f.source, 'runtime_shim', 'cjselfhost_llvmshim.o'), 'utf8'), 'cjselfhost_llvmshim.o');
  assert.match(await fs.readFile(path.join(f.work, 'sdk-stage1', 'bin', 'cjc'), 'utf8'), /old-stage1 compiler/);
});

test('missing bootstrap stage2 compiler cannot consume an unrelated old product', async t => {
  const f = await fixture(t);
  await fs.mkdir(f.sdk, {recursive: true});
  await fs.writeFile(path.join(f.sdk, 'stale-sdk'), 'old pipeline');
  await fs.rm(path.join(f.work, 'cjcj-stage2'));
  await assert.rejects(prepareBootstrapHandoff(f), {code: 'ENOENT'});
  assert.equal(await fs.readFile(path.join(f.sdk, 'stale-sdk'), 'utf8'), 'old pipeline');
});

for (const mutation of ['none', 'entry', 'installed', 'producer', 'command']) {
  test(`bootstrap compiler identity validates real handoff: ${mutation}`, async t => {
    const f = await fixture(t);
    await prepareBootstrapHandoff(f);
    let command = path.join(f.sdk, 'bin', 'cjc');
    const files = {
      entry: command,
      installed: path.join(f.sdk, 'bin', 'cjcj-stage1'),
      producer: path.join(f.work, 'cjcj-stage2'),
    };
    if (files[mutation]) await fs.appendFile(files[mutation], '\n# replaced input\n');
    if (mutation === 'command') command = path.join(f.work, 'sdk-stage1', 'bin', 'cjc');
    if (mutation === 'none') {
      const identity = await assertBootstrapCompiler({...f, command});
      assert.equal(identity.producer, path.join(f.work, 'cjcj-stage2'));
      const result = spawnSync(command, {encoding: 'utf8', env: f.consumerEnv('/fixture/target')});
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /compiler home=/);
    } else {
      await assert.rejects(assertBootstrapCompiler({...f, command}), /bootstrap compiler independent producer mismatch/);
    }
  });
}

test('bootstrap producer reaches actual stdx and tools subprocess entries', async t => {
  const {buildConfig} = await import('../lib/config.mjs');
  const tools = await import('../srcbuild/stages/tools.mjs');
  const stdx = await import('../srcbuild/stages/stdx.mjs');
  const packageStage = await import('../srcbuild/stages/package.mjs');
  const f = await fixture(t);
  const retained = JSON.parse(await fs.readFile(process.env.SDK_CONSUMER_INPUT_PLAN, 'utf8'));
  const host = retained.components.find(c => c.source.kind === 'distribution').source.root;
  const fakeBin = path.join(f.root, 'external-fixtures');
  const trace = path.join(f.root, 'compiler-invocations.jsonl');
  const write = async (file, data, mode = 0o755) => {
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, data, {mode});
  };
  f.compilerScript = Buffer.from(f.compilerScript.toString() + 'cat "$CANGJIE_HOME/modules/consumer-std.txt"\n');
  await f.publish();
  await prepareBootstrapHandoff(f);
  const pin = (await fs.readFile(new URL('../../ci/cjpm_pin.env', import.meta.url), 'utf8')).match(/^CJPM_FORK_REF=(.+)$/m)[1];
  await write(path.join(fakeBin, 'git'), `#!/bin/sh\ncase "$1" in rev-parse) printf '%s\\n' '${pin}' ;; esac\n`);
  const previous = Object.fromEntries(['PATH', 'CJCJ_SRCBUILD_HOST_SDK', 'CANGJIE_BUILD_DRY_RUN', 'CJCJ_VERIFIER_LLVM_DIS'].map(key => [key, process.env[key]]));
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  });
  process.env.PATH = `${fakeBin}:${process.env.PATH}`;
  process.env.CJCJ_SRCBUILD_HOST_SDK = host;
  if (!process.env.CJCJ_VERIFIER_LLVM_DIS) {
    const dis = spawnSync('sh', ['-c', 'command -v llvm-dis || command -v llvm-dis-18 || command -v llvm-dis-17 || command -v llvm-dis-16 || command -v llvm-dis-15 || command -v llvm-dis-14'], {encoding: 'utf8'});
    assert.equal(dis.status, 0, 'package verifier needs a real llvm-dis input');
    process.env.CJCJ_VERIFIER_LLVM_DIS = dis.stdout.trim();
  }
  console.log(`SDK_PACKAGE_LLVM_DIS path=${process.env.CJCJ_VERIFIER_LLVM_DIS} sha256=${await fileDigest(process.env.CJCJ_VERIFIER_LLVM_DIS)}`);
  delete process.env.CANGJIE_BUILD_DRY_RUN;
  const officialSdkRoot = host;
  const original = buildConfig({workspace: f.root, buildRoot: f.root, consumerSdk: f.sdk, officialSdkRoot});
  const dependencies = path.join(f.root, 'dependencies');
  await fs.mkdir(dependencies);
  const config = {...original, target: {...original.target, spec: {...original.target.spec,
    llvmBinDir: dependencies, opensslLibDir: dependencies}}};
  // Keep an executable old output available: a disconnected consumer must reach
  // the origin assertion, rather than fail merely because a file is absent.
  await write(path.join(config.repoPath('compiler'), 'output', 'bin', 'cjc'), '#!/bin/sh\nprintf "old output compiler\\n"\n');
  await write(path.join(config.repoPath('compiler'), 'output', 'lib', f.tuple, 'libcangjie-std-core.a'), 'old std');
  const oldRuntime = path.join(config.repoPath('compiler'), 'output', 'runtime', 'lib', f.tuple, 'libcangjie-runtime.so');
  await fs.mkdir(path.dirname(oldRuntime), {recursive: true});
  await fs.copyFile(path.join(f.sdk, 'runtime', 'lib', f.tuple, 'libcangjie-runtime.so'), oldRuntime);
  const python = `import json, os, pathlib, subprocess, sys\nif sys.argv[1] == 'build':\n r = subprocess.run(['cjc'], text=True, capture_output=True)\n r.check_returncode()\n with open(${JSON.stringify(trace)}, 'a') as out: out.write(json.dumps({'cwd': os.getcwd(), 'compiler': r.stdout}) + '\\n')\n p = pathlib.Path('build_temp/build/build.ninja')\n p.parent.mkdir(parents=True, exist_ok=True)\n p.write_text('LD_LIBRARY_PATH=' + os.environ['LD_LIBRARY_PATH'] + ' cjc file.cj\\n')\n`;
  await write(path.join(config.repoPath('stdx'), 'build.py'), python);
  const products = {
    cjpm: ['cjpm/dist/cjpm'], cjfmt: ['cjfmt/build/build/bin/cjfmt', 'cjfmt/config/default.toml'],
    hle: ['hyperlangExtension/target/bin/main', 'hyperlangExtension/src/dtsparser/keep.txt'],
    lsp: ['cangjie-language-server/output/bin/LSPServer'], cjcov: ['cjcov/dist/cjcov'],
    'cjtrace-recover': ['cjtrace-recover/dist/bin/cjtrace-recover'],
  };
  for (const [name, directory] of tools.toolsFor(config)) {
    const destinations = products[name].map(relative => path.join(config.repoPath('tools'), relative));
    const install = `if sys.argv[1] == 'install':\n for name in ${JSON.stringify(destinations)}:\n  p = pathlib.Path(name)\n  p.parent.mkdir(parents=True, exist_ok=True)\n  p.write_text('fixture tool from ' + pathlib.Path('compiler-result.txt').read_text())\n`;
    await write(path.join(config.repoPath('tools'), directory, 'build.py'), python + "if sys.argv[1] == 'build': pathlib.Path('compiler-result.txt').write_text(r.stdout)\n" + install);
  }
  await stdx.run(config);
  await tools.run(config);
  await fs.mkdir(path.join(config.repoPath('stdx'), 'target', f.tuple), {recursive: true});
  // The package gate supports a disassembler inside its actual candidate root.
  // Bind a real llvm-dis and assemble legal bitcode, rather than fake metadata
  // output or relying on the #922 environment-default path.
  const disassembler = process.env.CJCJ_VERIFIER_LLVM_DIS;
  const assembler = disassembler.replace('llvm-dis','llvm-as');
  // Package itself needs the completed Cangjie producers, independently of
  // the small-C child-process apparatus above. Preserve every input receipt.
  assert.ok(retained.components.every(c => c.producer.receipt));
  retained.buildRoot = path.join(f.root, 'package-builds');
  const packagePlan = path.join(f.root, 'package.plan.json');
  await fs.writeFile(packagePlan, JSON.stringify(retained));
  const packageSdk = path.join(f.root, 'package-sdk');
  const assembly = spawnSync('bash', [new URL('../../ci/bootstrap/sdk_build.sh', import.meta.url).pathname,
    '--plan', packagePlan, '--to', packageSdk], {encoding:'utf8'});
  console.log(`SDK_PACKAGE_REAL_INPUT_ASSERT rc=${assembly.status} sdk=${packageSdk}`);
  assert.equal(assembly.status,0,assembly.stdout+assembly.stderr);
  const beforePackageStd = await fileDigest(path.join(packageSdk,'lib',f.tuple,'libcangjie-std-core.a'));
  const bc = path.join(packageSdk,'modules','package-input.bc');
  const assembled = spawnSync(assembler,['-o',bc],{input:'define i32 @package_input() { ret i32 0 }\n',encoding:'utf8'});
  assert.equal(assembled.status,0,assembled.stderr);
  await fs.copyFile(disassembler,path.join(packageSdk,'third_party/llvm/bin/llvm-dis'));
  console.log(`SDK_PACKAGE_BITCODE path=${bc} sha256=${await fileDigest(bc)} assembler=${assembler}`);
  await packageStage.run({...config,consumerSdk:packageSdk});
  console.log('SDK_PACKAGE_ORIGIN_ASSERT_REACHED');
  assert.equal(await fileDigest(path.join(f.sdk, 'lib', f.tuple, 'libcangjie-std-core.a')), beforePackageStd);
  assert.ok((await fs.readFile(path.join(f.sdk, 'tools', 'bin', 'cjpm'), 'utf8')).includes(`compiler home=${f.sdk}`));
  const invocations = (await fs.readFile(trace, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(invocations.length, 1 + tools.toolsFor(config).length);
  for (const row of invocations) {
    console.log(`CONSUMER_ORIGIN_ASSERT_REACHED ${row.cwd}`);
    assert.ok(row.compiler.includes(`compiler home=${f.sdk}`), JSON.stringify(row));
    assert.ok(row.compiler.endsWith('coloured std'), JSON.stringify(row));
  }
});

for (const hostHeap of ['12288MB', '10752MB', '5376MB']) {
  test(`handoff passes recipe heap ${hostHeap} to host and compiler`, async t => {
    const f = await fixture(t);
    await fs.writeFile(path.join(f.work, 'cjcj-stage2'),
      '#!/bin/bash\nprintf "compiler heap=%s\\n" "$cjHeapSize"\n');
    await fs.writeFile(path.join(f.work, 'sdk-stage1', 'tools', 'bin', 'cjpm-stage1'),
      '#!/bin/bash\nprintf "host heap=%s\\n" "$cjHeapSize"\n"$CANGJIE_HOME/bin/cjc"\n');
    await f.publish();
    await prepareBootstrapHandoff(f);
    const run = spawnSync(path.join(f.sdk, 'tools', 'bin', 'cjpm'), {
      encoding: 'utf8', env: {...f.consumerEnv('/fixture/target'), cjHeapSize: hostHeap},
    });
    assert.equal(run.status, 0, run.stderr);
    console.log(`HEAP_BOUNDARY_ASSERT_REACHED ${JSON.stringify(run.stdout)}`);
    assert.equal(run.stdout, `host heap=${hostHeap}\ncompiler heap=${hostHeap}\n`);
  });
}

for (const heap of ['20GB', '', undefined]) {
  test(`handoff preserves explicit heap ${JSON.stringify(heap)}`, async t => {
    const f = await fixture(t);
    await fs.writeFile(path.join(f.work, 'cjcj-stage2'),
      '#!/bin/bash\nprintf "set=%s heap=%s\\n" "${cjHeapSize+x}" "$cjHeapSize"\n');
    await f.publish();
    await prepareBootstrapHandoff(f);
    await assertBootstrapCompiler({...f, command: path.join(f.sdk, 'bin', 'cjc')});
    const env = f.consumerEnv('/fixture/target');
    if (heap === undefined) delete env.cjHeapSize; else env.cjHeapSize = heap;
    const run = spawnSync(path.join(f.sdk, 'bin', 'cjc'), {encoding: 'utf8', env});
    assert.equal(run.status, 0, run.stderr);
    console.log(`HEAP_PRESENCE_ASSERT_REACHED ${JSON.stringify(run.stdout)}`);
    assert.equal(run.stdout, `set=${heap === undefined ? '' : 'x'} heap=${heap ?? ''}\n`);
  });
}

test('same handoff SDK inherits each invocation heap without capturing generation environment', async t => {
  const f = await fixture(t);
  await fs.writeFile(path.join(f.work, 'cjcj-stage2'),
    '#!/bin/bash\nprintf "%s\\n" "$cjHeapSize"\n');
  await f.publish();
  await prepareBootstrapHandoff(f);
  for (const heap of ['5376MB', '10752MB']) {
    const run = spawnSync(path.join(f.sdk, 'bin', 'cjc'), {
      encoding: 'utf8', env: {...f.consumerEnv('/fixture/target'), cjHeapSize: heap},
    });
    assert.equal(run.status, 0, run.stderr);
    console.log(`HEAP_PER_INVOCATION_ASSERT_REACHED expected=${heap} actual=${run.stdout.trim()}`);
    assert.equal(run.stdout, `${heap}\n`);
  }
});

test('stage3 final cjpm build consumes the resource-limited host environment', async () => {
  const stage = await fs.readFile(new URL('../../ci/srcbuild/steps/build-stage3.mjs', import.meta.url), 'utf8');
  const call = stage.split('\n').find(line => line.includes('`cjpm build -j 1`'));
  assert.ok(call, 'final build call exists');
  console.log(`STAGE3_HEAP_CONTRACT_ASSERT_REACHED ${call.trim()}`);
  assert.match(call, /env: stageEnv\}/);
  assert.match(stage, /cjHeapSize: resources\.STD_BUILD_HEAP/);
});

test('legacy stage2 inherits the caller heap', async () => {
  const stage = await fs.readFile(new URL('../../ci/srcbuild/steps/build-stage2.mjs', import.meta.url), 'utf8');
  assert.match(stage, /await \$`cjpm build -j 1`/);
  assert.doesNotMatch(stage, /cjHeapSize:/);
});


for (const topology of ['overlapping-links', 'stage33-regular-sdk']) {
test(`handoff materializes ${topology} on two consecutive promotions`, async t => {
  const f = await fixture(t);
  const relative = path.join('lib', f.tuple);
  for (const [tree, content] of [['sdk-stage1', 'old pcre'], ['stdlib-stage2', 'stage2 pcre']]) {
    const directory = path.join(f.work, tree, relative);
    await fs.writeFile(path.join(directory, 'libpcre2-8.so.0.14.0'), content);
    for (const [name, target] of [['libpcre2-8.so', 'libpcre2-8.so.0'], ['libpcre2-8.so.0', 'libpcre2-8.so.0.14.0']]) {
      const isLink = topology === 'overlapping-links' || tree === 'stdlib-stage2';
      if (isLink) await fs.symlink(target, path.join(directory, name));
      else await fs.writeFile(path.join(directory, name), content);
      assert.equal((await fs.lstat(path.join(directory, name))).isSymbolicLink(), isLink);
    }
  }
  const links = async directory => {
    const result = [];
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      const file = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) result.push(file);
      else if (entry.isDirectory()) result.push(...await links(file));
    }
    return result;
  };
  await f.publish();
  for (let pass = 1; pass <= 2; pass++) {
    let failure;
    try { await prepareBootstrapHandoff(f); } catch (error) { failure = error; }
    console.log(`HANDOFF_COMPLETION_ASSERT_REACHED pass=${pass} code=${failure?.code ?? 'OK'}`);
    assert.equal(failure, undefined, `handoff must complete: ${failure?.stack}`);
    for (const name of ['libpcre2-8.so', 'libpcre2-8.so.0']) {
      const file = path.join(f.sdk, relative, name);
      assert.equal((await fs.lstat(file)).isFile(), true, name);
      assert.equal(await fs.readFile(file, 'utf8'), 'stage2 pcre', name);
    }
    assert.deepEqual((await links(f.sdk)).sort(), ['cjc', 'cjc-frontend'].map(name => path.join(f.sdk, 'bin', name)).sort());
    await assertBootstrapCompiler({...f, command: path.join(f.sdk, 'bin', 'cjc')});
    console.log(`HANDOFF_REGULAR_CONTENT_ASSERT_PASS pass=${pass}`);
    // Reuse is authenticated; a corrupt installed payload must be rejected.
    await fs.writeFile(path.join(f.sdk, relative, 'libpcre2-8.so.0'), 'stale consumer');
    await assert.rejects(prepareBootstrapHandoff(f), /PAYLOAD/);
    await fs.writeFile(path.join(f.sdk, relative, 'libpcre2-8.so.0'), 'stage2 pcre');
    assert.equal(await fs.readFile(path.join(f.work, 'stdlib-stage2', relative, 'libpcre2-8.so'), 'utf8'), 'stage2 pcre');
  }
});
}
