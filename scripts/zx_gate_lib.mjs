// Shared zx implementation for the fixture-backed golden transcript gates.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export function configureToolchain(home, heap = true) {
  process.env.CANGJIE_HOME = home;
  process.env.LD_LIBRARY_PATH = `${home}/third_party/llvm/lib:${home}/runtime/lib/linux_x86_64_cjnative:${home}/tools/lib:${process.env.LD_LIBRARY_PATH || ''}`;
  if (heap) process.env.cjHeapSize ||= '12GB';
}

export function parseGoldenMode(reference) {
  if (argv.self !== undefined) {
    const compiler = typeof argv.self === 'string' ? argv.self : argv._[0];
    if (!compiler) throw new Error('--self needs a cjc path');
    return {mode: 'self', compiler, label: 'selfhost', extra: ['--set-runtime-rpath']};
  }
  if (argv.check) return {mode: 'check', compiler: reference, label: 'reference-check', extra: []};
  if (argv.h || argv.help) return {mode: 'help', compiler: reference, label: 'reference', extra: []};
  if (argv._.length) {
    console.error(`unknown arg: ${argv._[0]}`);
    process.exit(2);
  }
  return {mode: 'golden', compiler: reference, label: 'reference', extra: []};
}

export async function executable(file) {
  try {
    await fs.access(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export function normalized(text, replacements) {
  let result = text.replace(/\n+$/, '').replace(/\x1b\[[0-9;]*m/g, '');
  for (const [from, to] of replacements) result = result.replaceAll(from, to);
  result = result.replace(/\/tmp\/cangjie-tmp-[^ '\n]*/g, '<TMP>');
  return result.split('\n').map(line => line.replace(/\s+$/, '')).join('\n');
}

export async function finishGolden({mode, label, name, compiler, home, goldenDir, results, pass, fail, includeHome = false}) {
  console.log('');
  console.log(`===== ${name} summary (${label}) =====`);
  console.log(`compiler: ${compiler}`);
  if (includeHome) console.log(`CANGJIE_HOME: ${home}`);
  for (const result of results) console.log(`  ${result}`);
  if (mode === 'golden') {
    console.log(`GOLDEN-ESTABLISHED: ${pass}${name === 'anno_gate' || name === 'macro_gate' || name === 'test_gate' ? ` fixtures written to ${goldenDir}` : ''}`);
    process.exitCode = 0;
  } else {
    console.log(`${label} COMPARISON: PASS=${pass} FAIL=${fail}`);
    process.exitCode = fail === 0 ? 0 : 1;
  }
}

export async function compareOrWrite({mode, label, fixture, transcript, golden, work, results}) {
  if (mode === 'golden') {
    await fs.copyFile(transcript, golden);
    results.push(`${fixture}: golden written`);
    return true;
  }
  try {
    await fs.access(golden);
  } catch {
    results.push(`${fixture}: NO-GOLDEN`);
    return false;
  }
  const diff = await $({nothrow: true, quiet: true})`diff -u ${golden} ${transcript}`;
  if (diff.exitCode === 0) {
    results.push(`${fixture}: PASS`);
    return true;
  }
  results.push(`${fixture}: FAIL (differs${label === 'selfhost' ? ' from golden' : ''})`);
  console.log(`----- ${fixture} diff (${label} vs golden) -----`);
  process.stdout.write(diff.stdout + diff.stderr);
  return false;
}

export async function runSingleFileGoldenGate(options) {
  const {name, fixtureDir, goldenDir, home, reference, fixtures, includeHome, copyAsProg = false, replaceCjcBuild = false} = options;
  configureToolchain(home);
  const state = parseGoldenMode(reference);
  if (state.mode === 'help') {
    console.log(`Usage: ${name}.mjs [--self <cjc>|--check]`);
    return;
  }
  if (!await executable(state.compiler)) {
    console.error(`FATAL: compiler not executable: ${state.compiler}`);
    process.exitCode = 2;
    return;
  }
  await fs.mkdir(goldenDir, {recursive: true});
  const names = fixtures || (await fs.readdir(fixtureDir)).filter(file => file.endsWith('.cj')).map(file => path.basename(file, '.cj')).sort();
  const results = [];
  let pass = 0;
  let fail = 0;
  for (const fixture of names) {
    const source = path.join(fixtureDir, `${fixture}.cj`);
    try {
      await fs.access(source);
    } catch {
      results.push(`${fixture}: NO-FIXTURE`);
      fail++;
      continue;
    }
    const work = await fs.mkdtemp(path.join(os.tmpdir(), `${name}-`));
    try {
      const localName = copyAsProg ? 'prog.cj' : `${fixture}.cj`;
      const localSource = path.join(work, localName);
      const transcript = path.join(work, 't.txt');
      await fs.copyFile(source, localSource);
      const compile = await $({cwd: work, nothrow: true, quiet: true})`${state.compiler} ${localSource} -o ${path.join(work, copyAsProg ? 'app' : `${fixture}.app`)} ${state.extra}`;
      const replacements = [[work, copyAsProg ? '<BUILD>' : '<WORK>'], [home, '<HOME>']];
      if (replaceCjcBuild) replacements.push(['/root/cj_build/', '<CJC>/']);
      let contents = `[compile] rc=${compile.exitCode}\n${normalized(compile.stdout + compile.stderr, replacements)}\n`;
      const app = path.join(work, copyAsProg ? 'app' : `${fixture}.app`);
      if (compile.exitCode === 0 && await executable(app)) {
        const run = await $({nothrow: true, quiet: true})`timeout 30 ${app}`;
        if (copyAsProg) contents += `[run] exit=${run.exitCode}\n`;
        else contents += `[run] exit=${run.exitCode}\n${normalized(run.stdout, replacements)}\n`;
      }
      await fs.writeFile(transcript, contents);
      const ok = await compareOrWrite({mode: state.mode, label: state.label, fixture, transcript, golden: path.join(goldenDir, `${fixture}.golden`), work, results});
      if (ok) pass++; else fail++;
    } finally {
      await fs.rm(work, {recursive: true, force: true});
    }
  }
  await finishGolden({mode: state.mode, label: state.label, name, compiler: state.compiler, home, goldenDir, results, pass, fail, includeHome});
}
