import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {run} from '../lib/runner.mjs';
import {baseEnv} from '../srcbuild/stages/common.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import {shouldRunGcUnitLanguageTests} from '../srcbuild/stages/stdlib.mjs';
import {parseArguments, runSdkUsability, STATES} from '../../scripts/check_sdk_usable.mjs';
import {
  VERIFIER_DIAGNOSTIC_MARKER,
  assertNoVerifierReportArtifacts,
  markDiagnosticWorkspace,
  scanVerifierReportArtifacts,
  writeDiagnosticInventory,
} from '../../scripts/verifier_artifact_gate.mjs';

const repoRoot = path.resolve('.');
const srcbuildPath = path.join(repoRoot, 'tools', 'srcbuild-kkk2.mjs');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'verifier-report-mode-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  return root;
}

async function withEnvironment(values, action) {
  const saved = new Map(Object.keys(values).map(name => [name, process.env[name]]));
  for (const [name, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  try { return await action(); } finally {
    for (const [name, value] of saved) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

test('formal source-build children force strict mode and delete a residual report path', async t => {
  const root = fixture(t);
  const config = buildConfig({workspace: root, buildRoot: path.join(root, 'build')});
  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: '1',
    CJ_IR_VERIFIER_MODE: 'report',
    CJ_IR_VERIFIER_REPORT: '/residual/report.tsv',
    CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE: undefined,
  }, async () => {
    const env = baseEnv(config);
    assert.equal(env.CJ_IR_VERIFIER_MODE, 'strict');
    assert.equal(env.CJ_IR_VERIFIER_REPORT, null);
  });

  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: '1',
    CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE: reportPath(root),
  }, async () => {
    const env = baseEnv(config);
    assert.equal(env.CJ_IR_VERIFIER_MODE, 'report');
    assert.equal(env.CJ_IR_VERIFIER_REPORT, reportPath(root));
  });

  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: undefined,
    CJ_IR_VERIFIER_MODE: 'report',
    CJ_IR_VERIFIER_REPORT: '/residual/report.tsv',
  }, async () => {
    const observed = path.join(root, 'observed-env');
    await run([
      process.execPath, '-e',
      'require("node:fs").writeFileSync(process.argv[1], `${process.env.CJ_IR_VERIFIER_MODE}|${process.env.CJ_IR_VERIFIER_REPORT ?? "absent"}`)',
      observed,
    ], {
      envOverlay: {CJ_IR_VERIFIER_MODE: 'strict', CJ_IR_VERIFIER_REPORT: null},
      capture: true,
      logOutput: false,
    });
    assert.equal(fs.readFileSync(observed, 'utf8'), 'strict|absent');
  });
});

function reportPath(root) {
  return path.join(root, 'verifier.tsv');
}

test('removed diagnostic step options reject at the public launcher and diagnostic workspaces cannot package', t => {
  const root=fixture(t),report=path.join(root,'rejects.tsv');
  const rejected=spawnSync(process.execPath,[srcbuildPath,'--lane','finite-test',
    '--source','/root/finite-test/source','--config','/root/finite-test/config.json',
    '--verifier-report',report,'--to','19'],{encoding:'utf8'});
  assert.equal(rejected.status,1);assert.match(rejected.stderr,/Unknown option '--verifier-report'/);
  assert.equal(shouldRunGcUnitLanguageTests({}),true);
  assert.equal(shouldRunGcUnitLanguageTests({CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE:report}),false);
  const output=path.join(root,'cangjie_compiler/output');fs.mkdirSync(output,{recursive:true});
  fs.writeFileSync(path.join(output,VERIFIER_DIAGNOSTIC_MARKER),'{}\n');
  const packaged=spawnSync(process.execPath,[path.join(repoRoot,'build/cli.mjs'),
    '--workspace',root,'--build-root',root+'/build','--cangjie-version','finite','package'],{encoding:'utf8'});
  assert.notEqual(packaged.status,0);assert.match(packaged.stderr,/workspace is not a formal artifact source/);
});

test('artifact lineage gate inventories report metadata and rejects it or its diagnostic marker', t => {
  const root = fixture(t);
  const generated = path.join(root, 'generated');
  const source = path.join(root, 'source');
  fs.mkdirSync(generated);
  fs.mkdirSync(source);
  const clean = path.join(generated, 'clean.bc');
  const marked = path.join(generated, 'marked.bc');
  const markedObject = path.join(generated, 'marked.o');
  const incompatibleSourceFixture = path.join(source, 'invalid.ll.bc');
  fs.writeFileSync(clean, 'clean fixture');
  fs.writeFileSync(marked, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  fs.writeFileSync(markedObject, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  fs.writeFileSync(incompatibleSourceFixture, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  const llvmDis = path.join(root, 'llvm-dis');
  fs.writeFileSync(llvmDis, [
    '#!/usr/bin/env bash',
    'if [[ $(basename "$1") == invalid.ll.bc ]]; then exit 1; fi',
    'if [[ $(basename "$1") == marked.bc || $(basename "$1") == marked.o ]]; then',
    "  printf '%s\\n' '!cj.verifier.mode = !{!7}' '!7 = !{!\"report\"}'",
    'else',
    "  printf '%s\\n' '; clean module'",
    'fi',
    '',
  ].join('\n'));
  fs.chmodSync(llvmDis, 0o755);
  const report = path.join(root, 'rejects.tsv');
  const inventory = path.join(root, 'artifacts.tsv');
  const result = writeDiagnosticInventory({workspace: root, report, inventory, artifactRoots: [generated], llvmDis});
  assert.deepEqual(result.matches.map(match => path.basename(match.path)), ['marked.bc', 'marked.o']);
  assert.match(fs.readFileSync(inventory, 'utf8'), /marked\.bc/);
  assert.match(fs.readFileSync(inventory, 'utf8'), /marked\.o/);
  assert.throws(
    () => assertNoVerifierReportArtifacts([generated], {llvmDis, checkAncestors: false}),
    /rejected 2 file.*cj\.verifier\.mode=report/,
  );

  fs.rmSync(marked);
  fs.rmSync(markedObject);
  fs.rmSync(path.join(root, VERIFIER_DIAGNOSTIC_MARKER));
  assert.throws(
    () => assertNoVerifierReportArtifacts([source], {llvmDis}),
    /llvm-dis could not inspect.*invalid\.ll\.bc/,
  );
  assert.equal(assertNoVerifierReportArtifacts([generated], {llvmDis}).matches.length, 0);
  assert.equal(assertNoVerifierReportArtifacts([clean], {llvmDis, checkAncestors: false}).matches.length, 0);
  markDiagnosticWorkspace({workspace: root, report, inventory});
  assert.throws(() => assertNoVerifierReportArtifacts([root], {llvmDis}), /workspace is not a formal artifact source/);
});

// These executable stand-ins exercise selection and process arguments only;
// their magic-prefixed inputs are not claimed to be valid LLVM bitcode.
function selectionTool(root, name, {ir = '; clean module\n', rc = 0} = {}) {
  const tool = path.join(root, name);
  fs.mkdirSync(path.dirname(tool), {recursive: true});
  fs.writeFileSync(tool, `#!${process.execPath}\n`
    + 'import fs from "node:fs";\n'
    + `fs.appendFileSync(${JSON.stringify(path.join(root, 'tool-calls.jsonl'))}, `
    + `JSON.stringify({tool: ${JSON.stringify(name)}, args: process.argv.slice(2)}) + "\\n");\n`
    + `process.stdout.write(${JSON.stringify(ir)});\n`
    + `process.stderr.write(${JSON.stringify(rc ? 'selection fixture failure' : '')});\n`
    + `process.exitCode = ${rc};\n`);
  fs.chmodSync(tool, 0o755);
  return tool;
}

function selectionInput(root) {
  const artifacts = path.join(root, 'artifacts');
  fs.mkdirSync(artifacts);
  fs.writeFileSync(path.join(artifacts, 'input.bc'), Buffer.from([0x42, 0x43, 0xc0, 0xde, 1]));
  return artifacts;
}

function observeScan(action) {
  try {
    const result = action();
    return {llvmDis: result.llvmDis, matches: result.matches.length};
  } catch (error) {
    return {error: error.message};
  }
}

// A failed target must not hide another real product call in the same matrix.
// Await each subtest because the fixtures and process environment are shared.
async function selectionObservation(t, name, action) {
  await t.test(name, async observation => {
    observation.diagnostic(`OBSERVATION_BEGIN ${name}`);
    try {
      await action(observation);
      observation.diagnostic(`OBSERVATION_STATUS ${name} PASS`);
    } catch (error) {
      observation.diagnostic(`OBSERVATION_STATUS ${name} FAIL ${error.message}`);
      throw error;
    }
  });
}

test('verifier tool selection consumes environment through every public wrapper and CLI', async t => {
  const root = fixture(t);
  const artifacts = selectionInput(root);
  const envTool = selectionTool(root, 'environment.mjs');
  const report = path.join(root, 'report.tsv');
  const inventory = path.join(root, 'inventory.tsv');
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: envTool}, async () => {
    for (const [label, options] of [
      ['omitted', {}], ['undefined', {llvmDis: undefined}],
      ['empty', {llvmDis: ''}], ['null', {llvmDis: null}],
    ]) {
      for (const [entry, action] of [
        ['scan', () => scanVerifierReportArtifacts([artifacts], options)],
        ['assert', () => assertNoVerifierReportArtifacts([artifacts], options)],
        ['inventory', () => writeDiagnosticInventory({workspace: root, report, inventory, artifactRoots: [artifacts], ...options})],
      ]) {
        await selectionObservation(t, `${entry}/${label}`, observation => {
          const observed = observeScan(action);
          fs.rmSync(path.join(root, VERIFIER_DIAGNOSTIC_MARKER), {force: true});
          observation.diagnostic(`ENV_SELECTION_ASSERT ${entry}/${label} ${JSON.stringify(observed)}`);
          assert.deepEqual(observed, {llvmDis: envTool, matches: 0}, `environment tool selection: ${entry}/${label}`);
        });
      }
    }
    for (const args of [[], ['--llvm-dis', '']]) {
      for (const mode of ['gate', 'inventory']) {
        await selectionObservation(t, `CLI/${mode}/${args.length ? 'empty' : 'omitted'}`, observation => {
          const result = spawnSync(process.execPath, [path.join(repoRoot, 'scripts', 'verifier_artifact_gate.mjs'),
            '--root', artifacts, ...args,
            ...(mode === 'inventory' ? ['--write-inventory', '--report', report, '--inventory', inventory] : []),
          ], {encoding: 'utf8'});
          if (mode === 'inventory') fs.rmSync(path.join(artifacts, VERIFIER_DIAGNOSTIC_MARKER), {force: true});
          observation.diagnostic(`ENV_SELECTION_ASSERT CLI/${mode} status=${result.status} signal=${result.signal} error=${result.error?.code || 'none'} ${result.stdout.trim()} ${result.stderr.trim()}`);
          assert.equal(result.status, 0, `environment tool selection: CLI/${mode}: ${result.stderr}`);
          assert.match(result.stdout, mode === 'inventory' ? /matches=0/ : /pass candidates=1 matches=0/);
        });
      }
    }
  });
  await selectionObservation(t, 'wrapper process arguments and inventory', observation => {
    const callsFile = path.join(root, 'tool-calls.jsonl');
    const calls = fs.existsSync(callsFile) ? fs.readFileSync(callsFile, 'utf8').trim().split('\n').map(JSON.parse) : [];
    observation.diagnostic(`SELECTED_TOOL_PROCESS_CALLS ${JSON.stringify(calls)}`);
    assert.equal(calls.length, 16, 'each wrapper/CLI must actually execute the selected tool');
    assert.ok(calls.every(call => call.tool === 'environment.mjs'
      && JSON.stringify(call.args) === JSON.stringify([path.join(artifacts, 'input.bc'), '-o', '-'])));
    assert.equal(fs.readFileSync(inventory, 'utf8'), 'sha256\tpath\n');
  });
});

test('verifier tool selection preserves explicit override and ordered root discovery', async t => {
  const root = fixture(t);
  const artifacts = selectionInput(root);
  const envTool = selectionTool(root, 'environment.mjs', {rc: 19});
  const explicit = selectionTool(root, 'explicit.mjs');
  const paths = [
    'third_party/llvm/bin/llvm-dis', 'output/third_party/llvm/bin/llvm-dis',
    'cangjie_compiler/output/third_party/llvm/bin/llvm-dis', 'source-host-sdk/third_party/llvm/bin/llvm-dis',
  ];
  const discovered = paths.map(name => selectionTool(root, name));
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: envTool}, async () => {
    for (const action of [
      () => scanVerifierReportArtifacts([artifacts], {llvmDis: explicit}),
      () => assertNoVerifierReportArtifacts([artifacts], {llvmDis: explicit}),
      () => writeDiagnosticInventory({workspace: root, report: reportPath(root), inventory: path.join(root, 'inventory.tsv'), artifactRoots: [artifacts], llvmDis: explicit}),
    ]) {
      assert.deepEqual(observeScan(action), {llvmDis: explicit, matches: 0});
      fs.rmSync(path.join(root, VERIFIER_DIAGNOSTIC_MARKER), {force: true});
    }
    const cli = spawnSync(process.execPath, [path.join(repoRoot, 'scripts', 'verifier_artifact_gate.mjs'),
      '--root', artifacts, '--llvm-dis', explicit], {encoding: 'utf8'});
    assert.equal(cli.status, 0, cli.stderr);
    // An invalid explicit path retains root discovery, without consulting the
    // environment after an explicit nonempty declaration.
    assert.equal(scanVerifierReportArtifacts([root], {llvmDis: path.join(root, 'absent')}).llvmDis, discovered[0]);
    await selectionObservation(t, 'environment priority over root discovery', observation => {
      observation.diagnostic(`ENV_PRIORITY_ASSERT ${JSON.stringify(observeScan(() => scanVerifierReportArtifacts([root])))}`);
      assert.throws(() => scanVerifierReportArtifacts([root]), /rc=19.*selection fixture failure/);
    });
  });
  fs.rmSync(path.join(root, VERIFIER_DIAGNOSTIC_MARKER), {force: true});
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: undefined}, async () => {
    for (const tool of discovered) {
      await selectionObservation(t, `root discovery/${path.relative(root, tool)}`, observation => {
        const observed = assertNoVerifierReportArtifacts([root]);
        observation.diagnostic(`ROOT_DISCOVERY_ASSERT ${JSON.stringify({llvmDis: observed.llvmDis, matches: observed.matches.length})}`);
        assert.equal(observed.llvmDis, tool);
        assert.equal(observed.matches.length, 0);
      });
      fs.rmSync(tool);
    }
  });
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: path.join(root, 'missing-env')}, async () => {
    await selectionObservation(t, 'missing environment tool', observation => {
      observation.diagnostic(`MISSING_ENV_ASSERT ${JSON.stringify(observeScan(() => scanVerifierReportArtifacts([artifacts])))}`);
      assert.throws(() => scanVerifierReportArtifacts([artifacts]), /llvm-dis not found/);
    });
  });
});

test('verifier tool selection retains fail-closed and artifact controls', async t => {
  const root = fixture(t);
  const artifacts = selectionInput(root);
  const reportTool = selectionTool(root, 'report.mjs', {ir: '!cj.verifier.mode = !{!7}\n!7 = !{!"report"}\n'});
  const failing = selectionTool(root, 'failing.mjs', {rc: 23});
  const nonExecutable = path.join(root, 'non-executable');
  fs.writeFileSync(nonExecutable, 'not executable');
  const empty = path.join(root, 'empty');
  fs.mkdirSync(empty);
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: undefined}, async () => {
    assert.throws(() => assertNoVerifierReportArtifacts([artifacts]), /llvm-dis not found/);
    assert.deepEqual(assertNoVerifierReportArtifacts([empty]), {candidates: [], matches: [], llvmDis: ''});
    assert.throws(() => assertNoVerifierReportArtifacts([path.join(root, 'absent')]), /input does not exist/);
  });
  assert.throws(() => assertNoVerifierReportArtifacts([artifacts], {llvmDis: failing}), /rc=23.*selection fixture failure/);
  assert.throws(() => assertNoVerifierReportArtifacts([artifacts], {llvmDis: nonExecutable}), /could not inspect.*rc=null/);
  fs.writeFileSync(path.join(artifacts, 'wrapped.o'), Buffer.from([0xde, 0xc0, 0x17, 0x0b, 1]));
  fs.writeFileSync(path.join(artifacts, 'native.o'), 'native object');
  fs.writeFileSync(path.join(artifacts, 'ignored.txt'), Buffer.from([0x42, 0x43, 0xc0, 0xde, 1]));
  const scan = scanVerifierReportArtifacts([artifacts, artifacts], {llvmDis: reportTool});
  assert.equal(scan.candidates.length, 3, 'only .bc/.o, deduplicated');
  assert.deepEqual(scan.matches.map(match => path.basename(match.path)), ['input.bc', 'wrapped.o']);
  assert.ok(scan.matches.every(match => /^[a-f0-9]{64}$/.test(match.sha256)));
  assert.throws(() => assertNoVerifierReportArtifacts([artifacts], {llvmDis: reportTool}), /rejected 2 file.*cj\.verifier\.mode=report/);
  const inventory = path.join(root, 'inventory.tsv');
  const result = writeDiagnosticInventory({workspace: root, report: reportPath(root), inventory, artifactRoots: [artifacts], llvmDis: reportTool});
  assert.equal(result.matches.length, 2);
  assert.equal(JSON.parse(fs.readFileSync(result.marker, 'utf8')).artifactCount, 2);
  assert.equal(fs.readFileSync(inventory, 'utf8').trim().split('\n').length, 3);
  assert.throws(() => assertNoVerifierReportArtifacts([artifacts], {llvmDis: reportTool}), /workspace is not a formal artifact source/);
  fs.rmSync(result.marker);
  const markerCli = spawnSync(process.execPath, [path.join(repoRoot, 'scripts', 'verifier_artifact_gate.mjs'),
    '--root', root, '--mark-running', '--report', reportPath(root), '--inventory', inventory], {encoding: 'utf8'});
  assert.equal(markerCli.status, 0, markerCli.stderr);
  assert.match(markerCli.stdout, /VERIFIER_DIAGNOSTIC_MARKER=/);
  assert.equal(JSON.parse(fs.readFileSync(result.marker, 'utf8')).status, 'running');
});

test('verifier tool selection qualifies real bitcode through environment and CLI', async t => {
  const root = fixture(t);
  let fixtures = process.env.CJCJ_VERIFIER_TEST_BITCODE_ROOT;
  let llvmDis = process.env.CJCJ_VERIFIER_TEST_LLVM_DIS;
  if (!fixtures) {
    // Find an existing matched assembler/disassembler pair; never install tools.
    let llvmAs = process.env.CJCJ_VERIFIER_TEST_LLVM_AS;
    if (!llvmAs || !llvmDis) {
      for (const suffix of ['', '-20', '-19', '-18', '-17', '-16', '-15', '-14']) {
        const as = spawnSync(`llvm-as${suffix}`, ['--version'], {encoding: 'utf8'});
        const dis = spawnSync(`llvm-dis${suffix}`, ['--version'], {encoding: 'utf8'});
        if (as.status === 0 && dis.status === 0) {
          const located = spawnSync('sh', ['-c', `command -v llvm-as${suffix}; command -v llvm-dis${suffix}`], {encoding: 'utf8'});
          [llvmAs, llvmDis] = located.stdout.trim().split('\n');
          break;
        }
      }
    }
    assert.ok(llvmAs && llvmDis, 'real bitcode qualification requires existing LLVM tools');
    fixtures = path.join(root, 'bitcode');
    fs.mkdirSync(fixtures);
    for (const [name, metadata] of [['clean', ''], ['report', '!cj.verifier.mode = !{!0}\n!0 = !{!"report"}\n']]) {
      const ir = path.join(fixtures, `${name}.ll`);
      fs.writeFileSync(ir, `define void @fixture() { ret void }\n${metadata}`);
      const built = spawnSync(llvmAs, [ir, '-o', path.join(fixtures, `${name}.bc`)], {encoding: 'utf8'});
      assert.equal(built.status, 0, built.stderr);
    }
  }
  assert.ok(llvmDis, 'prepared real fixtures require their matching disassembler');
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: llvmDis}, async () => {
    const clean = path.join(fixtures, 'clean.bc');
    const report = path.join(fixtures, 'report.bc');
    // Match the existing single-file artifact test: ancestor markers apply to
    // workspace roots; this test qualifies bitcode inspection on individual files.
    await selectionObservation(t, 'real clean file environment selection', observation => {
      const observed = observeScan(() => assertNoVerifierReportArtifacts([clean], {checkAncestors: false}));
      observation.diagnostic(`REAL_ENV_SELECTION_ASSERT ${JSON.stringify(observed)}`);
      assert.deepEqual(observed, {llvmDis, matches: 0}, 'real environment tool selection');
    });
    await selectionObservation(t, 'real report file rejection', observation => {
      observation.diagnostic(`REAL_REPORT_ASSERT ${JSON.stringify(observeScan(() => assertNoVerifierReportArtifacts([report], {checkAncestors: false})))}`);
      assert.throws(() => assertNoVerifierReportArtifacts([report], {checkAncestors: false}), /rejected 1 file.*cj\.verifier\.mode=report/);
    });
    const inventory = path.join(root, 'inventory.tsv');
    await selectionObservation(t, 'real directory inventory', observation => {
      const listed = writeDiagnosticInventory({workspace: root, report: reportPath(root), inventory, artifactRoots: [fixtures]});
      fs.rmSync(listed.marker);
      observation.diagnostic(`REAL_INVENTORY_ASSERT ${JSON.stringify({llvmDis: listed.llvmDis, matches: listed.matches})}`);
      assert.deepEqual(listed.matches.map(match => match.path), [report]);
    });
    const gate = path.join(repoRoot, 'scripts', 'verifier_artifact_gate.mjs');
    for (const [input, status, output] of [[clean, 0, /pass candidates=1 matches=0/], [report, 1, /rejected 1 file.*cj\.verifier\.mode=report/]]) {
      await selectionObservation(t, `real CLI/${path.basename(input)}`, observation => {
        const cli = spawnSync(process.execPath, [gate, '--root', input, '--no-ancestor-markers'], {encoding: 'utf8'});
        observation.diagnostic(`REAL_BITCODE_CLI input=${input} status=${cli.status} signal=${cli.signal} error=${cli.error?.code || 'none'} ${cli.stdout.trim()} ${cli.stderr.trim()}`);
        assert.equal(cli.status, status, cli.stdout + cli.stderr);
        assert.match(cli.stdout + cli.stderr, output);
      });
    }
    const incompatible = path.join(root, 'incompatible.bc');
    fs.writeFileSync(incompatible, Buffer.from([0x42, 0x43, 0xc0, 0xde, 1]));
    await selectionObservation(t, 'real incompatible file rejection', observation => {
      observation.diagnostic(`REAL_INCOMPATIBLE_RESULT ${JSON.stringify(observeScan(() => assertNoVerifierReportArtifacts([incompatible], {checkAncestors: false})))}`);
      assert.throws(() => assertNoVerifierReportArtifacts([incompatible], {checkAncestors: false}), /llvm-dis could not inspect/);
    });
  });
});

test('verifier tool selection reaches package, SDK usability and performance consumers', async t => {
  const root = fixture(t);
  const workspace = path.join(root, 'workspace');
  const output = path.join(workspace, 'cangjie_compiler', 'output');
  fs.mkdirSync(output, {recursive: true});
  fs.writeFileSync(path.join(output, 'report.bc'), Buffer.from([0x42, 0x43, 0xc0, 0xde, 1]));
  const llvmDis = selectionTool(root, 'report.mjs', {ir: '!cj.verifier.mode = !{!7}\n!7 = !{!"report"}\n'});
  await withEnvironment({CJCJ_VERIFIER_LLVM_DIS: llvmDis}, async () => {
    const config = buildConfig({workspace, buildRoot: path.join(root, 'build')});
    await selectionObservation(t, 'consumer/package', async observation => {
      let message = '';
      try { await packageStage.run(config); } catch (error) { message = error.message; }
      observation.diagnostic(`PACKAGE_ENV_SELECTION_ASSERT ${message}`);
      assert.match(message, /rejected 1 file.*cj\.verifier\.mode=report/, 'package environment selection reaches metadata rejection');
      assert.deepEqual(fs.readdirSync(config.softwareDir), [], 'reject before archive staging');
    });
    await selectionObservation(t, 'consumer/usability', observation => {
      const usability = runSdkUsability(parseArguments(['--sdk', output]));
      observation.diagnostic(`USABILITY_ENV_SELECTION_ASSERT ${JSON.stringify(usability.results)}`);
      assert.equal(usability.results[0].id, 'U0_VERIFIER_ARTIFACTS');
      assert.equal(usability.results[0].state, STATES.FAIL);
      assert.match(usability.results[0].detail, /rejected 1 file.*cj\.verifier\.mode=report/);
      assert.ok(usability.results.slice(1).every(entry => entry.state === STATES.UNKNOWN));
    });
    const compiler = path.join(output, 'bin', 'cjc');
    fs.mkdirSync(path.dirname(compiler));
    fs.writeFileSync(compiler, `#!${process.execPath}\nprocess.exitCode = 0;\n`);
    fs.chmodSync(compiler, 0o755);
    const work = path.join(root, 'performance-work');
    await selectionObservation(t, 'consumer/performance', observation => {
      const performance = spawnSync('bash', [path.join(repoRoot, 'scripts', 'perfincr_cycle_smoke.sh'), compiler, work, '1'], {encoding: 'utf8'});
      observation.diagnostic(`PERFORMANCE_ENV_SELECTION_ASSERT status=${performance.status} signal=${performance.signal} error=${performance.error?.code || 'none'} ${performance.stderr.trim()}`);
      assert.equal(performance.status, 1, performance.stdout + performance.stderr);
      assert.match(performance.stderr, /rejected 1 file.*cj\.verifier\.mode=report/);
      assert.equal(fs.existsSync(work), false);
    });

    const python = path.join(root, 'python');
    const isolated = path.join(root, 'isolated-llvm');
    fs.mkdirSync(python);
    fs.mkdirSync(isolated);
    const inputs = Object.fromEntries([
      'llvm-manifest', 'base-sdk-archive', 'base-sdk-provenance', 'gate-host-runtime',
      'gate-apparatus-provenance', 'cjpm-provenance',
    ].map(name => {
      const file = path.join(root, name);
      fs.writeFileSync(file, 'fixture');
      return [name, file];
    }));
    const outdir = path.join(root, 'release-out');
    const args = Object.entries({sdk: output, binary: compiler, version: 'fixture', platform: 'linux-x64',
      outdir, 'python-bundle': python, 'isolated-llvm-bin': isolated, ...inputs,
      'cjpm-source-repo': 'https://example.invalid/cjpm.git', 'cjpm-source-sha': 'a'.repeat(40),
    }).flatMap(([name, value]) => [`--${name}`, value]);
    await selectionObservation(t, 'consumer/release', observation => {
      const release = spawnSync('zx', [path.join(repoRoot, 'scripts', 'package_sdk.mjs'), ...args], {encoding: 'utf8', timeout: 30_000});
      observation.diagnostic(`RELEASE_ENV_SELECTION_ASSERT status=${release.status} signal=${release.signal} error=${release.error?.code || 'none'} ${release.stderr?.trim()}`);
      assert.equal(release.status, 1, release.stdout + release.stderr);
      assert.match(release.stderr, /rejected 1 file.*cj\.verifier\.mode=report/);
      assert.equal(fs.existsSync(outdir), false);
    });
  });
  await selectionObservation(t, 'consumer process calls', observation => {
    const callsFile = path.join(root, 'tool-calls.jsonl');
    const calls = fs.existsSync(callsFile) ? fs.readFileSync(callsFile, 'utf8').trim().split('\n').map(JSON.parse) : [];
    observation.diagnostic(`CONSUMER_TOOL_PROCESS_CALLS ${JSON.stringify(calls)}`);
    assert.equal(calls.length, 4, 'all four real consumers execute the environment tool');
  });
});

test('source-build package entry rejects a diagnostic workspace before archiving', async t => {
  const root = fixture(t);
  const workspace = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'output'), {recursive: true});
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace, report, inventory: `${report}.artifacts.tsv`});
  const config = buildConfig({workspace, buildRoot: path.join(root, 'build')});
  await assert.rejects(() => packageStage.run(config), /workspace is not a formal artifact source/);
});

test('release package entry rejects a diagnostic SDK before constructing its stage', t => {
  const root = fixture(t);
  const sdk = path.join(root, 'sdk');
  const pythonBundle = path.join(root, 'python');
  fs.mkdirSync(path.join(sdk, 'bin'), {recursive: true});
  fs.mkdirSync(pythonBundle);
  const makeFile = name => {
    const file = path.join(root, name);
    fs.writeFileSync(file, 'fixture');
    return file;
  };
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  fs.mkdirSync(path.join(root, 'isolated-llvm'), {recursive: true});
  const zxProbe = spawnSync('sh', ['-c', 'command -v zx'], {encoding: 'utf8'});
  const command = zxProbe.status === 0 ? zxProbe.stdout.trim() : 'npx';
  const prefix = zxProbe.status === 0 ? [] : ['--yes', 'zx@8'];
  const result = spawnSync(command, [...prefix, path.join(repoRoot, 'scripts', 'package_sdk.mjs'),
    '--sdk', sdk,
    '--binary', makeFile('cjc'),
    '--version', 'fixture',
    '--platform', 'linux-x64',
    '--outdir', path.join(root, 'out'),
    '--python-bundle', pythonBundle,
    '--llvm-manifest', makeFile('llvm.manifest'),
    // The packager reads the source-built tuple from outside the SDK; the
    // diagnostic-workspace gate below must be what rejects this invocation, so
    // every other required argument is present and the gate is the only trigger.
    '--isolated-llvm-bin', path.join(root, 'isolated-llvm'),
    '--base-sdk-archive', makeFile('base.tar'),
    '--base-sdk-provenance', makeFile('base.json'),
    '--gate-host-runtime', makeFile('runtime.so'),
    '--gate-apparatus-provenance', makeFile('gate.json'),
    '--cjpm-provenance', makeFile('cjpm.json'),
    '--cjpm-source-repo', 'https://example.invalid/cjpm.git',
    '--cjpm-source-sha', 'a'.repeat(40),
  ], {encoding: 'utf8', timeout: 300_000});
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /diagnostic verifier workspace is not a formal artifact source/);
  assert.equal(fs.existsSync(path.join(root, 'out')), false);
});

test('SDK usability entry records verifier diagnostic rejection before running probes', t => {
  const sdk = fixture(t);
  const report = path.join(sdk, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  const result = runSdkUsability(parseArguments(['--sdk', sdk]));
  assert.equal(result.results[0].id, 'U0_VERIFIER_ARTIFACTS');
  assert.equal(result.results[0].state, STATES.FAIL);
  assert.match(result.results[0].detail, /workspace is not a formal artifact source/);
  assert.ok(result.results.slice(1).every(entry => entry.state === STATES.UNKNOWN));
});

test('performance entry rejects a compiler from a diagnostic SDK before creating workload output', t => {
  const root = fixture(t);
  const sdk = path.join(root, 'sdk');
  const compiler = path.join(sdk, 'bin', 'cjc');
  const work = path.join(root, 'work');
  fs.mkdirSync(path.dirname(compiler), {recursive: true});
  fs.writeFileSync(compiler, '#!/usr/bin/env bash\nexit 0\n');
  fs.chmodSync(compiler, 0o755);
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  const result = spawnSync('bash', [path.join(repoRoot, 'scripts', 'perfincr_cycle_smoke.sh'), compiler, work, '1'], {
    encoding: 'utf8',
  });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /diagnostic verifier workspace is not a formal artifact source/);
  assert.equal(fs.existsSync(work), false);
});
