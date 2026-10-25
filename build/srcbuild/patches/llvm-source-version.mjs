#!/usr/bin/env zx
// Normal compiler POST_BUILD output; the archive commit is an explicit source
// input, not a substitute Git repository or an installation authority record.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [source, output, commit] = process.argv.slice(2);
if (!source || !output) throw Error('LLVM_VERSION_ARGUMENTS');
const gitEntry = fs.existsSync(path.join(source, '.git'));
let text;
if (gitEntry) {
  const git = args => {
    const result = spawnSync('git', ['-C', source, ...args], {encoding:'utf8'});
    if (result.status !== 0) throw Error('LLVM_VERSION_GIT: ' + (result.stderr || result.error?.message));
    return result.stdout;
  };
  const head = git(['rev-parse', 'HEAD']).trim();
  if (commit && head !== commit) throw Error('LLVM_VERSION_SOURCE_MISMATCH');
  text = git(['log', '-1', '--oneline', '--decorate']);
} else {
  if (!/^[0-9a-f]{40}$/.test(commit || '')) throw Error('LLVM_VERSION_ARCHIVE_COMMIT_REQUIRED');
  text = commit + '\n';
}
fs.writeFileSync(output, text);
