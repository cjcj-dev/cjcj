#!/usr/bin/env node
// Receive a native artifact that the phase=prepare producer transported as one
// tar (prepare_native_inputs.mjs pack / native_runtime_package.mjs package).
// Actions artifacts drop POSIX modes; the tar keeps them, so the downloaded
// directory must hold exactly that archive and nothing else. Members are
// listed first and an absolute or escaping member name is rejected before
// extraction; the archive itself is removed after a successful extraction.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const systemTar = () => process.platform === 'win32'
  ? path.join(process.env.SystemRoot || process.env.SYSTEMROOT || 'C:\\Windows', 'System32', 'tar.exe') : 'tar';
function tar(args, cwd) {
  const result = spawnSync(systemTar(), args, {cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw Object.assign(new Error(`NATIVE_ARTIFACT_TAR_RC ${result.status} ${result.stderr || ''}`.trim()),
    {rc: result.status || 1});
  return result.stdout;
}
export function unpackNativeArtifact({directory, archive}) {
  if (!/^[\w.-]+\.tar$/.test(archive || '')) throw new Error('NATIVE_ARTIFACT_ARCHIVE_NAME');
  directory = path.resolve(directory);
  const entries = fs.readdirSync(directory);
  if (entries.length !== 1 || entries[0] !== archive || !fs.lstatSync(path.join(directory, archive)).isFile())
    throw new Error(`NATIVE_ARTIFACT_SINGLE_ARCHIVE_REQUIRED ${archive}: ${entries.sort().join(',')}`);
  const members = tar(['-tf', archive], directory).split(/\r?\n/).filter(Boolean);
  for (const member of members) {
    const parts = member.replace(/\\/g, '/').split('/');
    if (member.startsWith('/') || /^[A-Za-z]:/.test(member) || parts.includes('..'))
      throw new Error(`NATIVE_ARTIFACT_MEMBER_PATH ${member}`);
  }
  if (!members.length) throw new Error('NATIVE_ARTIFACT_EMPTY');
  tar(['-xf', archive], directory);
  fs.rmSync(path.join(directory, archive));
  return {directory, members: members.length};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [mode, directory, archive] = process.argv.slice(2);
    if (mode !== 'unpack' || !directory || !archive) throw new Error('usage: native-artifact-archive.mjs unpack DIRECTORY ARCHIVE.tar');
    console.log(JSON.stringify(unpackNativeArtifact({directory, archive})));
  } catch (error) { console.error(error.message); process.exitCode = error.rc || 1; }
}
