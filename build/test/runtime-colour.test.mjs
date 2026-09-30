import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {test} from 'node:test';
import {assertColouredRuntime} from '../../ci/srcbuild/lib/runtime-colour.mjs';

// Real ELF inputs exercise nm and the shared Python predicate, not a symbol mock.
test('runtime colour uses defined export difference, independent of retired markers', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'runtime-colour-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const compile = async (name, source, extra = []) => {
    const input = path.join(root, `${name}.c`);
    const output = path.join(root, `${name}.so`);
    await fs.writeFile(input, source);
    execFileSync('cc', ['-shared', '-fPIC', input, '-o', output, ...extra]);
    return output;
  };
  const host = await compile('host', 'int common;');
  const colour = await compile('colour', 'int common; int colour_only;');
  const marker = await compile('marker', 'int common; static const char retired[] __attribute__((used))="MRT_GCV2_";');
  const undefined = await compile('undefined', 'extern int colour_only; int common; static int *ref __attribute__((used))=&colour_only;');
  await t.test('defined colour export passes without marker', async () => {
    await assertColouredRuntime(colour, host);
    console.log('COLOUR_ASSERT_REACHED defined=accepted');
  });
  await t.test('official export set is rejected', async () => {
    await assert.rejects(assertColouredRuntime(host, host), /empty colour-only runtime export set/);
    console.log('COLOUR_ASSERT_REACHED official=rejected');
  });
  await t.test('retired marker cannot admit stock exports', async () => {
    await assert.rejects(assertColouredRuntime(marker, host), /empty colour-only runtime export set/);
    console.log('COLOUR_ASSERT_REACHED marker=rejected');
  });
  await t.test('undefined colour reference is not a runtime definition', async () => {
    await assert.rejects(assertColouredRuntime(undefined, host), /empty colour-only runtime export set/);
    console.log('COLOUR_ASSERT_REACHED undefined=rejected');
  });
  await fs.writeFile(path.join(root, 'versions'), 'VERSION_1 { global: *; };');
  const versionedHost = await compile('host-versioned', 'int common;', [`-Wl,--version-script=${path.join(root, 'versions')}`]);
  const versionedColour = await compile('colour-versioned', 'int common; int colour_only;', [`-Wl,--version-script=${path.join(root, 'versions')}`]);
  await t.test('versioned symbol names use the same export difference', async () => {
    await assertColouredRuntime(versionedColour, versionedHost);
    await assert.rejects(assertColouredRuntime(versionedHost, versionedHost), /empty colour-only runtime export set/);
    console.log('COLOUR_ASSERT_REACHED versioned=accepted-and-rejected');
  });
});
