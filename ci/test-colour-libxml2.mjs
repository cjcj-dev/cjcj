#!/usr/bin/env zx
// Actual producer recipe guards, srcbuild acquisition and optional real linkers.
import {fs, path, assert, repo, requireArgument, run, hash, diff, equalFiles, cliArgs, exit, entry, replace, cleanupOnSignals} from './entry-common.mjs';
const requiredArguments = {0: [7, 'usage: test-colour-libxml2.mjs EMPTY_WORK_DIRECTORY [BAD_LD_LLD] [GOOD_LD_LLD]']};
await entry(async () => {
  process.env.LC_ALL = 'C';
  const work = path.resolve(requireArgument(0, ...requiredArguments[0]));
  const bad = cliArgs[1] || '', good = cliArgs[2] || '';
  await run(['mkdir', work]);
  const yml = '.github/workflows/build-llvm-tools.yml';
  // Updated contract: srcbuild now acquires verified bytes. This is the active
  // tuple producer; its flag cut is new relative to the retired Bash test data.
  const src = 'ci/platform_tuples/build_tuple.mjs';
  const checker = 'ci/assert_no_libxml2_needed.sh';
  const token = '-DLLVM_ENABLE_LIBXML2=OFF';
  const files = [[yml, 'yml'], [src, 'src'], [checker, 'checker']];
  for (const [file, name] of files) fs.copyFileSync(path.join(repo, file), path.join(work, `${name}.saved`));
  const restore = () => {
    for (const [file, name] of files) fs.copyFileSync(path.join(work, `${name}.saved`), path.join(repo, file));
  };
  const removeSignalHandlers = cleanupOnSignals(restore);
  const recipe = log => run([process.execPath, path.join(repo, 'ci/g1-colour-recipe.mjs'), token, yml, src],
    {log: path.join(work, log), check: false});
  const drop = file => {
    const text = fs.readFileSync(path.join(repo, file), 'utf8');
    assert(text.includes(token), `missing producer anchor ${file}`);
    fs.writeFileSync(path.join(repo, file), text.split('\n').filter(line => !line.includes(token)).join('\n'));
  };
  const check = (file, arm) => run(['bash', checker, file], {log: path.join(work, `${arm}.log`), check: false});
  const grep = (text, token) => {
    assert(text.includes(token));
    process.stdout.write(text.split('\n').filter(line => line.includes(token)).join('\n') + '\n');
  };
  try {
    const green = await recipe('recipe-green.log');
    if (green.exitCode !== 0) { process.stderr.write(green.stdall); exit(green.exitCode); }
    await hash([yml, src, checker], path.join(work, 'green.sha256'));
    const cuts = [];
    for (const [file, name, control] of [[yml, 'yml', src], [src, 'src', yml]]) {
      drop(file);
      await diff(path.join(work, `${name}.saved`), path.join(repo, file), path.join(work, `${name}-cut.diff`));
      const cut = await recipe(`recipe-${name}-cut.log`);
      fs.writeFileSync(path.join(work, `${name}-cut.rc`), `${cut.exitCode}\n`);
      assert.equal(cut.exitCode, 1);
      grep(cut.stdall, `MISSING_LIBXML2_OFF ${file}`);
      assert.match(cut.stdall, /RECIPE_TARGET_ASSERT_REACHED/);
      assert.match(cut.stdall, /ERR_ASSERTION/);
      assert(cut.stdall.includes(`LIBXML2_PRODUCER_CONTROL_PRESENT ${control}`));
      assert(cut.stdall.includes('LIBXML2_CHECKER_CALL_CONTROL_PRESENT'));
      cuts.push(cut.exitCode);
      restore();
    }
    assert.equal((await recipe('recipe-restored.log')).exitCode, 0);
    equalFiles(path.join(work, 'recipe-green.log'), path.join(work, 'recipe-restored.log'));
    let badRc = 'skipped', badCutRc = 'skipped', goodRc = 'skipped';
    if (bad) {
      const rejected = await check(bad, 'bad'); badRc = rejected.exitCode;
      assert.equal(badRc, 1); grep(rejected.stdall, `DT_NEEDED libxml2 in ${bad}`);
      const rejection = String.raw`if printf '%s\n' "$deps" | grep -F libxml2 >/dev/null; then
    echo "DT_NEEDED libxml2 in $tool" >&2
    printf '%s\n' "$deps" >&2
    exit 1
fi
`;
      replace(path.join(repo, checker), rejection, '');
      await diff(path.join(work, 'checker.saved'), path.join(repo, checker), path.join(work, 'checker-cut.diff'));
      const accepted = await check(bad, 'bad-cut'); badCutRc = accepted.exitCode;
      assert.equal(badCutRc, 0); grep(accepted.stdall, 'NO_LIBXML2');
      restore();
      const restored = await check(bad, 'bad-restored');
      assert.equal(restored.exitCode, 1); grep(restored.stdall, `DT_NEEDED libxml2 in ${bad}`);
    }
    if (good) {
      const accepted = await check(good, 'good'); goodRc = accepted.exitCode;
      assert.equal(goodRc, 0); grep(accepted.stdall, 'NO_LIBXML2');
    }
    await hash([yml, src, checker], path.join(work, 'restored.sha256'));
    equalFiles(path.join(work, 'green.sha256'), path.join(work, 'restored.sha256'));
    console.log(`libxml2 recipe green=0 yml_cut=${cuts[0]} src_cut=${cuts[1]} restored=0 bad=${badRc} bad_cut=${badCutRc} good=${goodRc}`);
  } finally { try { restore(); } finally { removeSignalHandlers(); } }
});
