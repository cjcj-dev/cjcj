import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const parent = process.env.RELEASE_EVIDENCE_TEST_ROOT;
if (!parent) throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
const entry = new URL('./receive_native_sdk.mjs', import.meta.url).pathname;
async function fixture(suffix='-cjcj') {
  await fs.mkdir(parent, {recursive: true});
  const root = await fs.mkdtemp(path.join(parent, 'receive-sdk-'));
  await fs.mkdir(root+'/artifact'); await fs.mkdir(root+'/cangjie');
  const archive = root+'/artifact/cangjie-sdk-linux-x64-test'+suffix+'.tar.gz';
  const pack = async target => {
    await fs.writeFile(root+'/cangjie/BUILD-MANIFEST.json', JSON.stringify({target,version:'test',consumption:{status:'EXECUTED',platform:'linux_x86_64'}}));
    await fs.writeFile(root+'/cangjie/STAGE-INPUTS.json', JSON.stringify({phase:'stage2-target-sdk',platform:'linux_x86_64',runtimeCommit:'a'.repeat(40),compilerFile:'compiler',compilerSha256:'0'.repeat(64)}));
    await fs.writeFile(root+'/cangjie/compiler', 'unqualified compiler fixture');
    const p=spawnSync('tar',['-czf',archive,'-C',root,'cangjie'],{encoding:'utf8'});assert.equal(p.status,0,p.stderr);
    const sha=createHash('sha256').update(await fs.readFile(archive)).digest('hex');
    await fs.writeFile(archive+'.sha256',sha+'  '+path.basename(archive)+'\n');
  };
  const run = label => spawnSync(process.execPath,[entry,root+'/artifact',root+'/'+label,'linux-x64'],
    {encoding:'utf8',env:{...process.env,CJCJ_NATIVE_RUNTIME_REF:'a'.repeat(40),CJCJ_NATIVE_SDK_VERSION:'test'}});
  return {root,archive,pack,run};
}
test('real package receiver verifies archive digest before extraction', async () => {
  const {root,archive,pack,run}=await fixture();await pack('linux-x64');
  await fs.appendFile(archive,'changed bytes');const bad=run('bad');
  console.log(`TARGET_ARCHIVE_DIGEST rc=${bad.status}`);
  assert.equal(bad.status,1);assert.match(bad.stderr,/NATIVE_SDK_ARCHIVE_DIGEST/);
  assert.equal(await fs.stat(root+'/bad').then(()=>true,()=>false),false);
});
test('real package receiver checks target, then actual compiler; restored archive cannot grant qualification', async () => {
  const {pack,run}=await fixture();await pack('linux-aarch64');const wrong=run('wrong-target');
  assert.equal(wrong.status,1);assert.match(wrong.stderr,/NATIVE_SDK_PACKAGE_INPUT_MISMATCH/);
  await pack('linux-x64');const restored=run('restored-target');
  console.log(`TARGET_INSTALLED_COMPILER rc=${restored.status}`);
  assert.equal(restored.status,1);assert.match(restored.stderr,/installed compiler differs from produced bytes/);
  assert.doesNotMatch(restored.stdout,/COLOUR_SDK /);
});

test('public package archive keeps its name and reaches the same actual consumer checks',async()=>{
 const {archive,pack,run}=await fixture('');await pack('linux-x64');
 const result=run('public');assert.equal(result.status,1);
 assert.match(result.stderr,/installed compiler differs from produced bytes/);
 await fs.copyFile(archive,archive.replace('.tar.gz','-cjcj.tar.gz'));
 const ambiguous=run('ambiguous');assert.equal(ambiguous.status,1);assert.match(ambiguous.stderr,/NATIVE_SDK_ARCHIVE_COUNT 2/);
});

// Both documented script launchers must enter the same public parser. Importing
// a reusable consumer stays side-effect free; no SDK fixture grants qualification.
for (const name of ['compose-package', 'receive_native_sdk', 'verify_native_release']) {
  test(`${name}: node and zx execute the actual public entry and preserve argument boundaries`, async () => {
    const root = await fs.mkdtemp(path.join(parent, 'public-entry-'));
    const script = new URL('./' + name + '.mjs', import.meta.url).pathname;
    const args = name === 'receive_native_sdk' ? [root + '/missing artifact with spaces', root + '/new install', 'linux-x64']
      : name === 'verify_native_release' ? ['--sdk', root + '/sdk with spaces'] : [];
    const expected = name === 'receive_native_sdk' ? /ENOENT.*missing artifact with spaces/
      : name === 'verify_native_release' ? /--platform required/ : /NATIVE_SDK_ARTIFACT_DIR required/;
    const env = {...process.env}; delete env.NODE_TEST_CONTEXT; delete env.NATIVE_SDK_ARTIFACT_DIR;
    for (const executable of [process.execPath, 'zx']) {
      const result = spawnSync(executable, [script, ...args], {env, encoding: 'utf8'});
      console.log(`PUBLIC_ENTRY_ASSERT ${JSON.stringify({name, executable, args, rc: result.status, signal: result.signal, stderr: result.stderr})}`);
      assert.equal(result.status, 1, `${name}: entry must reject missing input, never silently succeed`);
      assert.match(result.stderr, expected);
    }
    const imported = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(new URL('./' + name + '.mjs', import.meta.url).href)});`], {env, encoding:'utf8'});
    assert.equal(imported.status, 0, imported.stderr);
  });
}
