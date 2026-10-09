import {canonical,readJson,reject} from './sdk-manifest.mjs';

// Platform boundaries, rather than a list of whichever files happened to
// survive a previous assembly. Windows retains all its declared payloads.
const windowsRoots=['lib/windows_x86_64_cjnative','runtime/lib/windows_x86_64_cjnative','modules/windows_x86_64_cjnative'];
export function officialPlatformPayload(lock,{platform,role,lockSha256}) {
  if(lock.schema!=='sharedbuild-official-sdk-v1'||!lock.version||!Object.keys(lock.files||{}).length)reject('OFFICIAL_PAYLOAD','sdk','authenticated full publisher inventory required');
  const excludedRoots=role==='target'&&platform.startsWith('linux_')?windowsRoots:[];
  const belongs=(rel,root)=>rel===root||rel.startsWith(`${root}/`);
  const files=Object.keys(lock.files).sort(), excluded=files.filter(rel=>excludedRoots.some(root=>belongs(rel,root)));
  return {schema:'sdk-official-platform-payload-v1',platform,role,version:lock.version,lockSha256,
    expected:files.filter(rel=>!excludedRoots.some(root=>belongs(rel,root))),excluded,
    exclusions:excludedRoots.map(root=>({root,reason:'Windows target libraries/modules belong to the Windows SDK'}))};
}
export async function verifyOfficialPayload(plan,manifest) {
  const declaration=plan.verification.officialPayload;if(!declaration)return;
  const expected=await readJson(declaration.path);
  const source=plan.components.find(component=>component.source.kind==='distribution'&&component.source.lockSha256===expected.lockSha256)?.source;
  if(!source)reject('OFFICIAL_PAYLOAD','sdk','publisher lock is outside this actual plan');
  const calculated=officialPlatformPayload(await readJson(source.lock),{platform:plan.platform,role:plan.role,lockSha256:source.lockSha256});
  if(canonical(expected)!==canonical(calculated))reject('OFFICIAL_PAYLOAD','sdk','platform expectation differs from the authenticated complete inventory');
  const missing=expected.expected.filter(rel=>!manifest.files[rel]);
  if(missing.length)reject('OFFICIAL_PAYLOAD_MISSING','sdk',`missing ${missing.length} required publisher paths: ${missing.join(', ')}`);
  const unexpected=expected.excluded.filter(rel=>manifest.files[rel]);
  if(unexpected.length)reject('OFFICIAL_PLATFORM','sdk',`Windows-only paths installed in Linux target: ${unexpected.join(', ')}`);
  console.log(`OFFICIAL_PLATFORM_PAYLOAD_ASSERT_REACHED expected=${expected.expected.length} excluded=${expected.excluded.length}`);
}
