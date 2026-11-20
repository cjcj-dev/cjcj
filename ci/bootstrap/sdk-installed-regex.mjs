#!/usr/bin/env zx
import {execFile} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {cleanSdkEnvironment, sdkPlatform} from './sdk-platform.mjs';

const execute = promisify(execFile);
const source = fileURLToPath(new URL('./fixtures/installed-regex.cj', import.meta.url));

// A successful match alone cannot distinguish the SDK library from the OS
// fallback. Observe glibc initializing both DSOs in the actual regex process.
export async function verifyInstalledRegex({sdk, work, platform}) {
  sdk = await fs.realpath(sdk);
  const env = cleanSdkEnvironment(sdk, platform);
  delete env.LD_DEBUG_OUTPUT;
  const lib = path.join(sdk, 'runtime/lib', sdkPlatform(platform).tuple);
  await fs.mkdir(work, {recursive:true});
  const exe = path.resolve(work, 'regex');
  await execute(path.join(sdk, 'bin/cjc'), ['--dy-std', source, '-o', exe], {cwd:work, env});
  const {stdout, stderr} = await execute(exe, [], {cwd:work, env:{...env, LD_DEBUG:'libs', LC_ALL:'C'}});
  if (stdout.trim() !== 'SDK_REGEX_MATCH_PASS') throw Error('SDK_REGEX_VALUE ' + stdout);
  const initialized = [...stderr.matchAll(/^\s*\d+:\s+calling init: (.+)$/gm)].map(match => path.normalize(match[1].trim()));
  for (const relative of ['libcangjie-std-regex.so', 'pcre2/libpcre2-8.so.0']) {
    const expected = path.join(lib, relative);
    const paths = initialized.filter(file => path.basename(file) === path.basename(expected));
    console.log('SDK_REGEX_LOADED ' + JSON.stringify({expected, paths}));
    if (paths.length !== 1 || paths[0] !== expected ||
        path.dirname(await fs.realpath(expected)) !== path.dirname(expected))
      throw Error('SDK_REGEX_ORIGIN ' + relative);
  }
  console.log(stdout.trim());
}
