#!/usr/bin/env zx
// Controlled executor for adapter qualification only. It intentionally stops
// before sharedbuild completion/sealing; it cannot publish a native receipt.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
const args = process.argv.slice(2);
if (args.includes('sdk-publish')) {
  // Exercise the existing real publisher on the small official fixture; this
  // is a physical host copy, not a native/product success receipt.
  const main = path.join(process.env.STAGE1_TOOLS_REPO, 'ts/src/sharedbuild/main.py');
  const result = await new Promise((resolve, reject) => {
    const p = spawn('/usr/bin/python3', [main, ...args], {stdio: 'inherit'});
    p.once('error', reject); p.once('exit', (rc, signal) => resolve({rc, signal}));
  });
  process.exit(result.rc ?? 1);
}
const spec = JSON.parse(await fs.readFile(args[args.indexOf('--recipe') + 1], 'utf8'));
const directory = path.dirname(args[args.indexOf('--recipe') + 1]);
const work = path.join(directory, 'fixture-work'), inputs = path.join(work, 'inputs'), output = path.join(work, 'artifacts');
await fs.mkdir(inputs, {recursive: true}); await fs.mkdir(output);
for (const [name, input] of Object.entries(spec.inputs)) await fs.copyFile(input, path.join(inputs, name));
await fs.writeFile(path.join(work, 'parameters.json'), JSON.stringify(spec.parameters));
const tuple = 'linux_x86_64_cjnative';
const hostLd = [path.join(spec.sdk, 'runtime/lib', tuple), path.join(spec.sdk, 'lib', tuple),
  path.join(spec.sdk, 'third_party/llvm/lib'), path.join(spec.sdk, 'tools/lib')].join(':');
const env = {PATH: `${spec.sdk}/bin:${spec.sdk}/tools/bin:/usr/bin:/bin`,
  HOME: work, TMPDIR: work, LANG: 'C.UTF-8', CANGJIE_HOME: spec.sdk,
  LD_LIBRARY_PATH: process.env.STAGE1_FIXTURE_WRONG_DOMAIN ? `${directory}/wrong-loader` : hostLd,
  SB_SOURCE: spec.repo, SB_INPUTS: inputs, SB_OUTPUT: output, SB_PARAMETERS: path.join(work, 'parameters.json'),
  SB_SHA: spec.sha, SB_OPTIMIZATION: spec.optimization};
const result = await new Promise((resolve, reject) => {
  const p = spawn(process.execPath, [spec.builder], {env, cwd: spec.repo, stdio: 'inherit'});
  p.once('error', reject); p.once('exit', (rc, signal) => resolve({rc, signal}));
});
await fs.writeFile(path.join(directory, 'fixture-adapter-result.json'), JSON.stringify({...result, work, spec})+'\n');
console.log(`CONTROLLED_STAGE1_ADAPTER_RESULT rc=${result.rc} signal=${result.signal}`);
// A fixed stop, after observation. Never enter product completion or sealOutput.
process.exit(73);
