#!/usr/bin/env zx
// Device-only fault arms: execute the actual bootstrap-input process each time.
import {fs, path, assert, repo, requireArgument, run, capture, exit, hash, diff, replace, equalFiles} from './entry-common.mjs';
const requiredArguments = {"0": [5, "empty evidence directory"]};
const required = index => requireArgument(index, ...requiredArguments[index]);
const work = path.resolve(required(0, 'empty evidence directory'));
fs.mkdirSync(work);
const consumer = 'ci/release/prepare_bootstrap_inputs.mjs';
const status = await capture(['git', 'status', '--porcelain', '--', consumer], {check: false});
process.stderr.write(status.stderr);
if (status.stdout.trim()) { console.error('consumer must be clean'); exit(1); }
fs.copyFileSync(path.join(repo, consumer), path.join(work, 'consumer.saved'));
function restore() {
  fs.copyFileSync(path.join(work, 'consumer.saved'), path.join(repo, consumer));
  equalFiles(path.join(work, 'consumer.saved'), path.join(repo, consumer));
}
for (const [signal, rc] of [['SIGINT', 130], ['SIGTERM', 143]]) process.once(signal, () => { restore(); process.exit(rc); });
async function arm(name) {
  const start = Date.now();
  const result = await run(['timeout', '-k', '5', '180', 'node', '--test', '--test-reporter=tap', 'ci/release/prepare_bootstrap_inputs.test.mjs'], {log: path.join(work, `${name}.log`), check: false});
  fs.writeFileSync(path.join(work, `${name}.rc`), `${result.exitCode}\n`);
  fs.writeFileSync(path.join(work, `${name}.wall`), `wall=${Math.floor((Date.now() - start) / 1000)}\n`);
  await run(['python3', '-', work, name], {input: validator});
}
const validator = String.raw`import json, re, sys
from pathlib import Path
work, arm = Path(sys.argv[1]), sys.argv[2]
text = (work / f'{arm}.log').read_text()
rc = int((work / f'{arm}.rc').read_text())
records = list(re.finditer(r'^(ok|not ok) ([0-9]+) - (.+)$', text, re.M))
plan = re.findall(r'^1\.\.([0-9]+)$', text, re.M)
assert records and len(plan) == 1 and int(plan[0]) == len(records), 'incomplete TAP plan'
names = [m[3] for m in records]
assert len(set(names)) == len(names), 'duplicate TAP names'
assert [int(m[2]) for m in records] == list(range(1, len(records)+1)), 'TAP numbering'
assert not re.search(r'^.*# (?:SKIP|TODO)\b', text, re.M), 'skipped/TODO record'
summary = {}
for key in ('tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'):
    values = re.findall(rf'^# {key} ([0-9]+)$', text, re.M)
    assert len(values) == 1, f'missing {key} terminator'
    summary[key] = int(values[0])
failed = [m[3] for m in records if m[1] == 'not ok']
assert summary['tests'] == len(records) and summary['fail'] == len(failed)
assert summary['pass'] == len(records)-len(failed)
assert all(summary[k] == 0 for k in ('cancelled', 'skipped', 'todo'))
result = {'rc': rc, 'names': names, 'failed': failed, 'summary': summary}
(work / f'{arm}.json').write_text(json.dumps(result, indent=2)+'\n')
expected = {
 'green': {}, 'restored': {},
 'selection-cut': {'ast artifact wins over an available fallback archive': 93,
                   'missing selected ast artifact cannot fall back': 108},
 'digest-cut': {'ast reviewed pin rejects changed bytes while tuple stays valid': 100},
}[arm]
assert set(failed) == set(expected), f'{arm}: unexpected failure set {failed}'
assert (rc == 0) == (not expected), f'{arm}: unexpected runner rc {rc}'
if arm == 'green':
    # Confirm the dynamic full-package controls in the actual normal TAP.
    required = ['explicit bare ast archive is rejected before bootstrap export']
    required += [f'explicit AST input missing {name} is rejected before export' for name in
      ('include/cangjie', 'include/flatbuffers/StdAstFormat_generated.h', 'schema/StdAstFormat.fbs',
       'third_party/flatbuffers/bin/flatc', 'third_party/flatbuffers/include',
       'third_party/flatbuffers/cangjie', 'third_party/flatbuffers/modules')]
    required += [f'bare {where} archive selects complete downloaded AST inputs consumed by installer'
                 for where in ('build', 'SDK')]
    assert set(required) <= set(names), 'missing full-package controls'
else:
    green = json.loads((work / 'green.json').read_text())
    assert names == green['names'], 'test collection changed'
for i, m in enumerate(records):
    if m[3] in expected:
        diagnostic = text[m.end():records[i+1].start() if i+1 < len(records) else len(text)]
        assert 'ERR_ASSERTION' in diagnostic, 'not an assertion failure'
        assert re.search(rf'prepare_bootstrap_inputs\.test\.mjs:{expected[m[3]]}:[0-9]+', diagnostic), 'target assertion not reached'
if arm in ('green', 'restored'):
    markers = sorted(re.findall(r'^# ASSERT .+$', text, re.M))
    assert markers, 'missing assertion markers'
    if arm == 'green':
        (work / 'green-markers.json').write_text(json.dumps(markers, indent=2)+'\n')
    else:
        assert markers == json.loads((work / 'green-markers.json').read_text()), 'restored markers changed'
print(f'{arm}: rc={rc} tests={len(names)} failures={failed}')`;
try {
  await hash([consumer, 'ci/release/prepare_bootstrap_inputs.test.mjs', 'ci/release/prepare_bootstrap_fixture.mjs'], path.join(work, 'inputs.sha256'));
  await hash([consumer], path.join(work, 'green.sha256'));
  await arm('green');
  replace(path.join(repo, consumer), 'pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || process.env.CJCJ_BOOTSTRAP_AST_SUPPORT,', 'pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_SUPPORT || process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT,');
  await diff(path.join(work, 'consumer.saved'), path.join(repo, consumer), path.join(work, 'selection-cut.diff'));
  await hash([consumer], path.join(work, 'selection-cut.sha256'));
  await arm('selection-cut');
  restore();
  await hash([consumer], path.join(work, 'selection-restored.sha256'));
  replace(path.join(repo, consumer), "astFallbacks, '', process.env.AST_SUPPORT_SHA256, 'ast-support archive SHA256');", "astFallbacks, '', sha256File(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || process.env.CJCJ_BOOTSTRAP_AST_SUPPORT || firstExisting(astFallbacks)), 'ast-support archive SHA256');");
  await diff(path.join(work, 'consumer.saved'), path.join(repo, consumer), path.join(work, 'digest-cut.diff'));
  await hash([consumer], path.join(work, 'digest-cut.sha256'));
  await arm('digest-cut');
  restore();
  await arm('restored');
  await hash([consumer], path.join(work, 'restored.sha256'));
  equalFiles(path.join(work, 'green.sha256'), path.join(work, 'restored.sha256'));
  console.log(`AST-WIRING green=0 selection-cut=${fs.readFileSync(path.join(work, 'selection-cut.rc'), 'utf8').trim()} digest-cut=${fs.readFileSync(path.join(work, 'digest-cut.rc'), 'utf8').trim()} restored=0`);
} finally {
  restore();
  await hash([consumer], path.join(work, 'exit.sha256'));
  const status = await capture(['git', 'status', '--porcelain', '--', consumer]);
  fs.writeFileSync(path.join(work, 'exit.status'), status.stdout);
  assert.equal(status.stdout, '');
}
