import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {download, resolveTarballMirror} from '../lib/archive.mjs';

test('download gives IPv4 fallback enough time on dual-stack hosts', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-archive-'));
  const destination = path.join(root, 'fixture.bin');
  const originalTimeout = net.getDefaultAutoSelectFamilyAttemptTimeout();
  fs.writeFileSync(destination, 'cached archive fixture');
  t.after(() => {
    net.setDefaultAutoSelectFamilyAttemptTimeout(originalTimeout);
    fs.rmSync(root, {recursive: true, force: true});
  });

  await download('https://example.invalid/fixture.bin', destination);

  assert.equal(net.getDefaultAutoSelectFamilyAttemptTimeout(), 2_000);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'cached archive fixture');
});

test('tarball mirrors copy file:// mappings and fail closed when required', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-tarball-mirror-'));
  const source = path.join(root, 'ncurses-6.5.tar.gz');
  const destination = path.join(root, 'dest', 'ncurses-6.5.tar.gz');
  fs.writeFileSync(source, 'mirror-bytes');
  const url = 'https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.5.tar.gz';
  const previousMirrors = process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS;
  const previousRequired = process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS;
  const originalWrite = process.stderr.write;
  let output = '';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  t.after(() => {
    process.stderr.write = originalWrite;
    if (previousMirrors === undefined) delete process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS;
    else process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS = previousMirrors;
    if (previousRequired === undefined) delete process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS;
    else process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS = previousRequired;
    fs.rmSync(root, {recursive: true, force: true});
  });

  delete process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS;
  process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS = '1';
  assert.throws(() => resolveTarballMirror(url), /tarball mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1/);
  assert.match(output, /TARBALL-MIRROR none, falling back to /);

  process.env.CJCJ_SRCBUILD_TARBALL_MIRRORS = `${url}=file://${source}`;
  delete process.env.CJCJ_SRCBUILD_REQUIRE_MIRRORS;
  await download(url, destination);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'mirror-bytes');
});
