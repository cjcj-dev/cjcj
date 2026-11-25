import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {load} from './vendor/js-yaml/js-yaml.mjs';

const {jobs} = load(readFileSync(new URL('../.github/workflows/sdk-build-target.yml', import.meta.url), 'utf8'));
const directNeeds = job => [job.needs ?? []].flat();
const followsStage0 = job => directNeeds(job).some(id => id === 'source-stage0' || followsStage0(jobs[id]));

test('source-stage0 feeds the initial std and SDK package jobs', () => {
  assert.ok(directNeeds(jobs['source-stage1-initial-std']).includes('source-stage0'));
  assert.ok(followsStage0(jobs.srcbuild));
});

for (const [id, job] of Object.entries(jobs).filter(([, job]) => followsStage0(job))) {
  test(`${id} explicitly gates its direct dependencies after source-stage0`, () => {
    assert.match(job.if ?? '', /(?:!cancelled|always)\(\)/, `${id}: missing explicit status function`);
    for (const need of directNeeds(job)) {
      assert.ok(job.if.includes(`needs.${need}.result == 'success'`), `${id}: missing result check for ${need}`);
    }
  });
}
