import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  installPythonBundle,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';

async function executable(file, content) {
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, content);
  await fs.chmod(file, 0o755);
}

async function fixture() {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'python-bundle-'));
  const source = path.join(work, 'source');
  const stage = path.join(work, 'stage');
  await executable(path.join(source, 'bin', 'python3.11'), [
    '#!/bin/sh',
    'case "$3" in',
    '  *CJDB-PYTHON-IMPORT*)',
    ...[...CJDB_PYTHON_MODULES, ...CJDB_PYTHON_UNIX_MODULES]
      .map(name => `    printf 'CJDB-PYTHON-IMPORT=${name}\\n'`),
    '    exit 0',
    '    ;;',
    'esac',
    `printf '${RELEASE_PYTHON_VERSION}\\n%s\\n' "$PYTHONHOME"`,
    '',
  ].join('\n'));
  await fs.mkdir(path.join(source, 'lib', 'python3.11'), {recursive: true});
  await fs.writeFile(path.join(source, 'lib', 'libpython3.11.so.1.0'), 'fixture libpython\n');
  await fs.writeFile(path.join(source, 'lib', 'python3.11', 'os.py'), '# fixture stdlib\n');
  await fs.writeFile(path.join(source, 'LICENSE.txt'), 'PSF LICENSE AGREEMENT fixture\n');
  await fs.writeFile(path.join(source, 'PYTHON-BUNDLE.json'), `${JSON.stringify({
    schema: 1,
    platform: 'linux-x64',
    version: RELEASE_PYTHON_VERSION,
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: '--prefix=<bundle> --enable-shared --without-ensurepip',
    configure_environment: 'LDFLAGS=-Wl,-rpath,$ORIGIN/../lib',
    required_modules: [...CJDB_PYTHON_MODULES],
    required_unix_modules: [...CJDB_PYTHON_UNIX_MODULES],
  }, null, 2)}\n`);
  await executable(path.join(stage, 'third_party', 'llvm', 'bin', 'lldb'), [
    '#!/bin/sh',
    'printf "PYTHONHOME=%s\\nPYTHONPATH=%s\\nARGS=%s\\n" "$PYTHONHOME" "$PYTHONPATH" "$*"',
    '',
  ].join('\n'));
  return {work, source, stage};
}

test('Linux cjdb launcher uses only the packaged Python by relative path', async () => {
  const {work, source, stage} = await fixture();
  try {
    const installed = await installPythonBundle({
      source, stage, platform: 'linux-x64', runtimeDir: 'linux_x86_64_cjnative',
    });
    assert.equal(installed.version, RELEASE_PYTHON_VERSION);
    assert.equal(installed.artifact, path.join(stage, 'third_party', 'python', 'bin', 'python3.11'));
    assert.equal(await fs.readFile(installed.license, 'utf8'), 'PSF LICENSE AGREEMENT fixture\n');
    const session = spawnSync(installed.launcher, ['--batch', '-o', 'quit'], {
      encoding: 'utf8', env: {...process.env, PYTHONHOME: '/host/python', PYTHONPATH: '/host/modules'},
    });
    assert.equal(session.status, 0, session.stderr);
    assert.match(session.stdout,
      new RegExp(`PYTHONHOME=${path.join(stage, 'third_party', 'python').replaceAll('\\', '\\\\')}`));
    assert.match(session.stdout,
      new RegExp(`PYTHONPATH=${path.join(stage, 'third_party', 'llvm', 'lib', 'python3.11', 'site-packages').replaceAll('\\', '\\\\')}`));
    assert.match(session.stdout, /ARGS=--batch -o quit/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('missing Python bundle directory fails closed', async () => {
  const {work, stage} = await fixture();
  try {
    await assert.rejects(installPythonBundle({
      source: path.join(work, 'missing'),
      stage,
      platform: 'linux-x64',
      runtimeDir: 'linux_x86_64_cjnative',
    }), /Python 3\.11\.9 bundle directory is missing/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});
