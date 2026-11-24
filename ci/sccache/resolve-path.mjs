#!/usr/bin/env node
// Resolve the SCCACHE_PATH mozilla-actions/sccache-action exported to the
// executable that actually exists, in one spelling every later consumer accepts.
//
// On Windows sccache-action@v0.0.11 exports
//   C:\hostedtoolcache\windows\sccache\0.18.0\x64/sccache
// while the file on disk is sccache.exe. Node's Win32 fs.existsSync rejects that
// name, so native_runtime.mjs failed NATIVE_RUNTIME_SCCACHE_MISSING (prepare.yml
// run 45376721209). MSYS2/Git bash cannot see the problem: `test -f .../sccache`
// is true when only sccache.exe exists (Cygwin's transparent .exe lookup), so
// the existence check has to be made by Node, as this file does.
//
// The result is absolute, carries .exe when only the .exe exists, and uses
// forward slashes on Windows. C:/.../sccache.exe is accepted by Node fs and
// path.isAbsolute, cygpath -m, CMake launchers and bash. All-backslash
// C:\...\sccache.exe is not safe in bash, which runs a command word as a path
// only when it contains '/' and otherwise searches PATH for it; the original
// value reached the action's own "$SCCACHE_PATH" --start-server through its one '/'.
//
//   node ci/sccache/resolve-path.mjs        reads SCCACHE_PATH, prints the path
// exits 1 with SCCACHE_PATH_MISSING on stderr when no executable exists.

import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const isFile = candidate => fs.statSync(candidate, {throwIfNoEntry: false})?.isFile() === true;

export function resolveSccachePath(raw, {exists = isFile, platform = process.platform} = {}) {
  if (!raw) throw new Error('SCCACHE_PATH_MISSING: SCCACHE_PATH is empty');
  let candidate = raw;
  if (!exists(candidate) && exists(candidate + '.exe')) candidate += '.exe';
  if (!exists(candidate)) throw new Error(`SCCACHE_PATH_MISSING: neither ${raw} nor ${raw}.exe is a file`);
  if (platform === 'win32') return path.win32.resolve(candidate).replaceAll('\\', '/');
  return path.posix.resolve(candidate);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    process.stdout.write(resolveSccachePath(process.env.SCCACHE_PATH) + '\n');
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
