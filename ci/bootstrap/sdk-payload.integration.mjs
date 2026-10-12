import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {officialPlatformPayload} from './sdk-official-payload.mjs';
import {fileDigest} from './sdk-manifest.mjs';
const repository=fileURLToPath(new URL('../..',import.meta.url));
async function inputs(){const plan=JSON.parse(await fs.readFile(process.env.SDK_OFFICIAL_PLAN,'utf8')),source=plan.components[0].source;return {plan,source,lock:JSON.parse(await fs.readFile(source.lock,'utf8'))};}
test('the real publisher inventory enters the exact Linux platform expectation',async()=>{
  const {source,lock}=await inputs();
  const actual=officialPlatformPayload(lock,{platform:'linux_x86_64',role:'target',lockSha256:source.lockSha256});
  const roots=['lib/windows_x86_64_cjnative/','runtime/lib/windows_x86_64_cjnative/','modules/windows_x86_64_cjnative/'];
  const expected=Object.keys(lock.files).filter(rel=>!roots.some(root=>rel.startsWith(root))).sort();
  console.log(`PLATFORM_PAYLOAD_PRODUCER_ASSERT_REACHED exported=${actual.expected.length} publisher=${expected.length}`);
  assert.deepEqual(actual.expected,expected,'product export must retain every actual publisher path within the Linux boundary');
  assert.equal(actual.exclusions.length,3);
});
test('the real resolver rejects an incomplete publisher tool installation',async()=>{
  const {plan,source,lock}=await inputs();
  const root=await fs.mkdtemp(path.join(process.env.SDK_OFFICIAL_EVIDENCE,'payload-'));
  const projection=officialPlatformPayload(lock,{platform:plan.platform,role:plan.role,lockSha256:source.lockSha256});
  const expected=path.join(root,'expected.json');await fs.writeFile(expected,JSON.stringify(projection));
  plan.verification.officialPayload={path:expected,sha256:await fileDigest(expected)};
  plan.buildRoot=path.join(root,'builds');plan.components[0].install=[{from:'',to:'',exclude:['tools/bin/cjdb']}];
  const input=path.join(root,'plan.json');await fs.writeFile(input,JSON.stringify(plan));
  const child=spawnSync(process.execPath,[path.join(repository,'ci/bootstrap/toolchain-sdk.mjs'),'--plan',input,'--resolve'],{encoding:'utf8',maxBuffer:32*1024*1024});
  await fs.writeFile(path.join(root,'resolver.log'),child.stdout+child.stderr);
  await fs.writeFile(path.join(root,'result.json'),JSON.stringify({rc:child.status,signal:child.signal}));
  console.log(`PLATFORM_PAYLOAD_CONSUMER_ASSERT_REACHED actual_rc=${child.status} evidence=${root}`);
  assert.equal(child.status,1,'actual resolver must reject the missing publisher path');
  assert.match(child.stderr,/OFFICIAL_PAYLOAD_MISSING.*tools\/bin\/cjdb/);
  assert.match(child.stdout,/SDK_COMPONENT_READY component=official-current/,'producer must finish before target completeness check');
});
