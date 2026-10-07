#!/usr/bin/env zx
// Recipe contract plus the dynamic-section check. Fixture text is not a linker.
import {fs, path, assert, repo, required, run, hash, diff, equalFiles, cliArgs, isMain} from './script-common.mjs';
process.env.LC_ALL = 'C';
const work = path.resolve(required(0, 'EMPTY_WORK_DIRECTORY'));
const bad = cliArgs[1] || '', good = cliArgs[2] || '';
fs.mkdirSync(work);
const yml = '.github/workflows/build-llvm-tools.yml', src = 'ci/platform_tuples/build_tuple.sh', checker = 'ci/assert_no_libxml2_needed.sh';
// Source-build now acquires a tuple; the active producer owns this flag.
const token = '-DLLVM_ENABLE_LIBXML2=OFF';
for (const [file, name] of [[yml, 'yml'], [src, 'src'], [checker, 'checker']]) fs.copyFileSync(path.join(repo, file), path.join(work, `${name}.saved`));
function restore() {
  for (const [file, name] of [[yml, 'yml'], [src, 'src'], [checker, 'checker']]) fs.copyFileSync(path.join(work, `${name}.saved`), path.join(repo, file));
}
function recipe(log) {
  let error;
  for (const file of [yml, src]) {
    if (error) break;
    const source = fs.readFileSync(path.join(repo, file), 'utf8');
    if (!source.includes(token)) error = `MISSING_LIBXML2_OFF ${file}`;
    else if (file === yml && !source.includes('assert_no_libxml2_needed.sh')) error = `MISSING_NEEDED_CHECK ${file}`;
  }
  fs.writeFileSync(path.join(work, log), `${error || 'RECIPE_LIBXML2_OFF_PRESENT'}\n`);
  return error ? 1 : 0;
}
function drop(file) {
  const source = fs.readFileSync(path.join(repo, file), 'utf8');
  const lines = source.match(/[^\n]*\n|[^\n]+$/g) || [];
  const kept = lines.filter(line => !line.includes(token));
  assert.notEqual(kept.length, lines.length);
  fs.writeFileSync(path.join(repo, file), kept.join(''));
}
const check = (file, arm) => run(['bash', checker, file], {log: path.join(work, `${arm}.log`), check: false});
try {
  assert.equal(recipe('recipe-green.log'), 0);
  await hash([yml, src, checker], path.join(work, 'green.sha256'));
  drop(yml);
  await diff(path.join(work, 'yml.saved'), path.join(repo, yml), path.join(work, 'yml-cut.diff'));
  const ymlCut = recipe('recipe-yml-cut.log');
  assert.notEqual(ymlCut, 0);
  assert(fs.readFileSync(path.join(work, 'recipe-yml-cut.log'), 'utf8').includes(`MISSING_LIBXML2_OFF ${yml}`));
  console.log(`MISSING_LIBXML2_OFF ${yml}`);
  restore();
  drop(src);
  await diff(path.join(work, 'src.saved'), path.join(repo, src), path.join(work, 'src-cut.diff'));
  const srcCut = recipe('recipe-src-cut.log');
  assert.notEqual(srcCut, 0);
  assert(fs.readFileSync(path.join(work, 'recipe-src-cut.log'), 'utf8').includes(`MISSING_LIBXML2_OFF ${src}`));
  console.log(`MISSING_LIBXML2_OFF ${src}`);
  restore();
  assert.equal(recipe('recipe-restored.log'), 0);
  equalFiles(path.join(work, 'recipe-green.log'), path.join(work, 'recipe-restored.log'));
  let badRc = 'skipped', badCutRc = 'skipped', goodRc = 'skipped';
  if (bad) {
    const rejected = await check(bad, 'bad'); badRc = rejected.exitCode;
    assert.equal(badRc, 1); assert(rejected.stdall.includes(`DT_NEEDED libxml2 in ${bad}`));
    const file = path.join(repo, checker), source = fs.readFileSync(file, 'utf8');
    const old = "if printf '%s\\n' \"$deps\" | grep -F libxml2 >/dev/null; then\n    echo \"DT_NEEDED libxml2 in $tool\" >&2\n    printf '%s\\n' \"$deps\" >&2\n    exit 1\nfi\n";
    assert(source.includes(old), 'checker rejection block missing');
    fs.writeFileSync(file, source.replace(old, ''));
    await diff(path.join(work, 'checker.saved'), file, path.join(work, 'checker-cut.diff'));
    const accepted = await check(bad, 'bad-cut'); badCutRc = accepted.exitCode;
    assert.equal(badCutRc, 0); assert.match(accepted.stdall, /NO_LIBXML2/);
    restore();
    const restored = await check(bad, 'bad-restored');
    assert.equal(restored.exitCode, 1); assert(restored.stdall.includes(`DT_NEEDED libxml2 in ${bad}`));
  }
  if (good) {
    const accepted = await check(good, 'good'); goodRc = accepted.exitCode;
    assert.equal(goodRc, 0); assert.match(accepted.stdall, /NO_LIBXML2/);
  }
  await hash([yml, src, checker], path.join(work, 'restored.sha256'));
  equalFiles(path.join(work, 'green.sha256'), path.join(work, 'restored.sha256'));
  console.log(`libxml2 recipe green=0 yml_cut=${ymlCut} src_cut=${srcCut} restored=0 bad=${badRc} bad_cut=${badCutRc} good=${goodRc}`);
} finally { restore(); }
