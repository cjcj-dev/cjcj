import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const ex=promisify(execFile),entry=new URL('./native-cjdb-job.mjs',import.meta.url).pathname;

test('public package preserves original Python input without rebuilding the native graph',async()=>{
  const root=await fs.mkdtemp(path.join(process.env.TMPDIR||os.tmpdir(),'native-package-'));
  const install=root+'/install',work=root+'/package',original=root+'/python-original.json';
  await fs.mkdir(install);await fs.writeFile(original,'{"producer":"original Python build"}\n');
  const facts={configuration:{pythonInputs:{record:original}},pythonSource:{build:{originalInputs:{path:original}}}};
  await fs.writeFile(install+'/BUILD-INPUTS.json',JSON.stringify(facts));
  const before=await fs.readFile(install+'/BUILD-INPUTS.json');
  const result=await ex(process.execPath,[entry,'package',install,work]);
  console.log('ORIGINAL_PYTHON_INPUT_CARRIED_ASSERTION_REACHED');
  assert.equal(await fs.access(install+'/share/cjcj/build-inputs/python-original.json').then(()=>true,()=>false),true,'original Python input must be carried');
  assert.equal(await fs.readFile(install+'/share/cjcj/build-inputs/python-original.json','utf8'),await fs.readFile(original,'utf8'));
  assert.deepEqual(await fs.readFile(install+'/BUILD-INPUTS.json'),before);
  const members=(await ex('tar',['-tf',work+'/native-install.tar'])).stdout;
  assert.match(members,/share\/cjcj\/build-inputs\/python-original\.json/);
  const commands=JSON.parse(await fs.readFile(work+'/commands.json'));
  assert.equal(commands.length,1);assert.deepEqual(commands[0].argv.slice(0,2),['tar','-cf']);assert.equal(commands[0].rc,0);
  assert.ok(!result.stderr.includes('NATIVE_JOB_SOURCE_PAIR'));
});

test('public package rejects absent original Python facts before creating an archive',async()=>{
  const root=await fs.mkdtemp(path.join(process.env.TMPDIR||os.tmpdir(),'native-package-bad-'));
  await fs.mkdir(root+'/install');await fs.writeFile(root+'/install/BUILD-INPUTS.json','{}');
  await assert.rejects(ex(process.execPath,[entry,'package',root+'/install',root+'/package']),e=>e.code===1&&e.stderr.includes('NATIVE_JOB_PYTHON_SOURCE_REQUIRED'));
  await assert.rejects(fs.access(root+'/package/native-install.tar'),{code:'ENOENT'});
});
