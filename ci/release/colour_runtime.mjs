import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

export const runtimeFiles = [
  'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
  'runtime/lib/linux_x86_64_cjnative/libboundscheck.so',
  'lib/linux_x86_64_cjnative/libcangjie-runtime.a',
];
export const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function regularFile(root, relative) {
  let current = root;
  for (const part of relative.split('/')) {
    current = path.join(current, part);
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`COLOUR_RT_SYMLINK: ${current}`);
  }
  if (!fs.statSync(current).isFile()) throw new Error(`COLOUR_RT_FILE: ${current}`);
  return current;
}
export function prepareRuntime(source, dest, env = process.env) {
  const sourceSha = fs.readFileSync(path.join(source, 'SOURCE_SHA'), 'utf8').trim();
  if (!/^[a-f0-9]{40}$/.test(env.RUNTIME_REF || '') || sourceSha !== env.RUNTIME_REF) {
    throw new Error('COLOUR_RT_SOURCE_MISMATCH');
  }
  if (!/^\d+$/.test(env.GITHUB_RUN_ID || '') || !/^\d+$/.test(env.GITHUB_RUN_ATTEMPT || '')) {
    throw new Error('COLOUR_RT_RUN_MISSING');
  }
  function walk(dir) {
    return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
      const file = path.join(dir, entry.name);
      return entry.isDirectory() ? walk(file) : [path.relative(source, file)];
    });
  }
  const stdFiles = [...walk(path.join(source, 'lib')), ...walk(path.join(source, 'runtime/lib'))]
    .filter(rel => /^(libcangjie-std-|lib.*FFI\.)/.test(path.basename(rel)));
  if (!stdFiles.includes('lib/linux_x86_64_cjnative/libcangjie-std-core.a')) {
    throw new Error('COLOUR_RT_STD_MISSING');
  }
  const moduleFiles = walk(path.join(source, 'modules'));
  const files = {};
  for (const rel of [...runtimeFiles, ...stdFiles, ...moduleFiles]) {
    const input = regularFile(source, rel);
    const output = path.join(dest, rel);
    fs.mkdirSync(path.dirname(output), {recursive: true});
    fs.copyFileSync(input, output);
    files[rel] = digest(output);
  }
  const manifest = {runtime_sha: sourceSha, platform: 'linux_x86_64',
    run_id: env.GITHUB_RUN_ID, run_attempt: env.GITHUB_RUN_ATTEMPT, files};
  fs.writeFileSync(path.join(dest, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  const sha = digest(path.join(dest, 'manifest.json'));
  if (env.GITHUB_OUTPUT) fs.appendFileSync(env.GITHUB_OUTPUT, `sha256=${sha}\n`);
  console.log(`COLOUR_RT_MANIFEST_SHA256=${sha}`);
}
export function verifyRuntime(env = process.env) {
  const root = env.CJCJ_BOOTSTRAP_COLOUR_RT;
  if (!root) throw new Error('COLOUR_RT_INPUT_MISSING');
  if (!/^\d+$/.test(env.COLOUR_RT_RUN_ID || '') || !/^\d+$/.test(env.COLOUR_RT_ARTIFACT_ID || '')
      || !/^\d+$/.test(env.COLOUR_RT_RUN_ATTEMPT || '')) throw new Error('COLOUR_RT_PIN_MISSING');
  const pin = env.COLOUR_RT_MANIFEST_SHA256 || '';
  const actual = digest(regularFile(root, 'manifest.json'));
  if (!/^[a-f0-9]{64}$/.test(pin) || actual !== pin) {
    throw new Error(`COLOUR_RT_SHA256_MISMATCH expected=${pin} actual=${actual}`);
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  if (manifest.runtime_sha !== env.RUNTIME_REF || manifest.platform !== 'linux_x86_64'
      || manifest.run_id !== env.COLOUR_RT_RUN_ID || manifest.run_attempt !== env.COLOUR_RT_RUN_ATTEMPT) {
    throw new Error('COLOUR_RT_MANIFEST_MISMATCH');
  }
  for (const rel of new Set([...runtimeFiles, ...Object.keys(manifest.files || {})])) {
    if (digest(regularFile(root, rel)) !== manifest.files?.[rel]) {
      throw new Error(`COLOUR_RT_FILE_SHA256_MISMATCH: ${rel}`);
    }
  }
  console.log(`COLOUR_RT_VERIFIED run=${manifest.run_id} artifact=${env.COLOUR_RT_ARTIFACT_ID} runtime=${manifest.runtime_sha} sha256=${actual}`);
  return root;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  prepareRuntime(process.argv[2], process.argv[3]);
}
