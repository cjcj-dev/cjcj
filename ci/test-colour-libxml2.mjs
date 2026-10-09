#!/usr/bin/env zx
// Preserve the recipe guards and optional real-linker fault arms.
import {fs, path, assert, repo, requireArgument, run, hash, diff, equalFiles, cliArgs, exit} from './entry-common.mjs';
const requiredArguments = {"0": [7, "usage: test-colour-libxml2.mjs EMPTY_WORK_DIRECTORY [BAD_LD_LLD] [GOOD_LD_LLD]"]};
const required = index => requireArgument(index, ...requiredArguments[index]);
process.env.LC_ALL = 'C';
const work = path.resolve(required(0, 'usage: test-colour-libxml2.mjs EMPTY_WORK_DIRECTORY [BAD_LD_LLD] [GOOD_LD_LLD]'));
const bad = cliArgs[1] || '', good = cliArgs[2] || '';
await run(['mkdir', work]);
const yml = '.github/workflows/build-llvm-tools.yml', src = 'tools/srcbuild_kkk2.sh', checker = 'ci/assert_no_libxml2_needed.sh';
const token = '-DLLVM_ENABLE_LIBXML2=OFF';
for (const [file, name] of [[yml, 'yml'], [src, 'src'], [checker, 'checker']])
  await run(['cp', file, path.join(work, `${name}.saved`)]);
async function restore() {
  for (const [file, name] of [[yml, 'yml'], [src, 'src'], [checker, 'checker']])
    await run(['cp', path.join(work, `${name}.saved`), file]);
}
const recipe = log => run(['python3', '-', token, yml, src, 'ci/platform_tuples/build_tuple.sh'],
  {input: RECIPE, log: path.join(work, log), check: false});
const drop = file => run(['python3', '-', file, token], {input: DROP});
const check = (file, arm) => run(['bash', checker, file], {log: path.join(work, `${arm}.log`), check: false});
function grep(text, token) { assert(text.includes(token)); process.stdout.write(text.split('\n').filter(line => line.includes(token)).join('\n') + '\n'); }
const RECIPE = String.raw`import sys
from pathlib import Path
token, yml, src, anchor = sys.argv[1:]
anchor_text = Path(anchor).read_text()
if token not in anchor_text:
    raise SystemExit("MISSING_LIBXML2_OFF anchor")
for path in (yml, src):
    text = Path(path).read_text()
    if token not in text:
        raise SystemExit(f"MISSING_LIBXML2_OFF {path}")
    if "assert_no_libxml2_needed.sh" not in text:
        raise SystemExit(f"MISSING_NEEDED_CHECK {path}")
print("RECIPE_LIBXML2_OFF_PRESENT")`;
const DROP = String.raw`import sys
from pathlib import Path
path, token = sys.argv[1:]
file = Path(path)
lines = file.read_text().splitlines(keepends=True)
kept = [line for line in lines if token not in line]
if len(kept) == len(lines):
    raise SystemExit(f"token not found in {path}")
file.write_text(''.join(kept))`;
const CUT = String.raw`import sys
from pathlib import Path
file = Path(sys.argv[1])
text = file.read_text()
old = '''if printf '%s\\n' "$deps" | grep -F libxml2 >/dev/null; then
    echo "DT_NEEDED libxml2 in $tool" >&2
    printf '%s\\n' "$deps" >&2
    exit 1
fi
'''
if old not in text:
    raise SystemExit("checker rejection block missing")
file.write_text(text.replace(old, "", 1))`;
try {
  const green = await recipe('recipe-green.log');
  if (green.exitCode !== 0) { process.stderr.write(green.stderr); exit(green.exitCode); }
  await hash([yml, src, checker], path.join(work, 'green.sha256'));
  await drop(yml); await diff(path.join(work, 'yml.saved'), path.join(repo, yml), path.join(work, 'yml-cut.diff'));
  const ymlCut = await recipe('recipe-yml-cut.log'); assert.notEqual(ymlCut.exitCode, 0); grep(ymlCut.stdall, `MISSING_LIBXML2_OFF ${yml}`);
  await restore();
  await drop(src); await diff(path.join(work, 'src.saved'), path.join(repo, src), path.join(work, 'src-cut.diff'));
  const srcCut = await recipe('recipe-src-cut.log'); assert.notEqual(srcCut.exitCode, 0); grep(srcCut.stdall, `MISSING_LIBXML2_OFF ${src}`);
  await restore(); assert.equal((await recipe('recipe-restored.log')).exitCode, 0);
  equalFiles(path.join(work, 'recipe-green.log'), path.join(work, 'recipe-restored.log'));
  let badRc = 'skipped', badCutRc = 'skipped', goodRc = 'skipped';
  if (bad) {
    const rejected = await check(bad, 'bad'); badRc = rejected.exitCode; assert.equal(badRc, 1); grep(rejected.stdall, `DT_NEEDED libxml2 in ${bad}`);
    await run(['python3', '-', checker], {input: CUT});
    await diff(path.join(work, 'checker.saved'), path.join(repo, checker), path.join(work, 'checker-cut.diff'));
    const accepted = await check(bad, 'bad-cut'); badCutRc = accepted.exitCode; assert.equal(badCutRc, 0); grep(accepted.stdall, 'NO_LIBXML2');
    await restore(); const restored = await check(bad, 'bad-restored'); assert.equal(restored.exitCode, 1); grep(restored.stdall, `DT_NEEDED libxml2 in ${bad}`);
  }
  if (good) { const accepted = await check(good, 'good'); goodRc = accepted.exitCode; assert.equal(goodRc, 0); grep(accepted.stdall, 'NO_LIBXML2'); }
  await hash([yml, src, checker], path.join(work, 'restored.sha256'));
  equalFiles(path.join(work, 'green.sha256'), path.join(work, 'restored.sha256'));
  console.log(`libxml2 recipe green=0 yml_cut=${ymlCut.exitCode} src_cut=${srcCut.exitCode} restored=0 bad=${badRc} bad_cut=${badCutRc} good=${goodRc}`);
} finally { await restore(); }
