import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../../', import.meta.url);
// Wiring checks only: these do not stand in for a macOS cross compilation.
test('iOS producer consumes the shared Xcode probe and builds all three upstream targets', async () => {
  const source = await fs.readFile(new URL('ci/srcbuild/steps/build-ios-final-std.mjs', root), 'utf8');
  assert.match(source, /probeRequirement\('xcode-ios'\)/);
  for (const [target, tuple] of [
    ['ios-aarch64', 'ios_aarch64_cjnative'],
    ['ios-simulator-aarch64', 'ios_simulator_aarch64_cjnative'],
    ['ios-simulator-x86_64', 'ios_simulator_x86_64_cjnative'],
  ]) assert.ok(source.includes(`target: '${target}', tuple: '${tuple}'`), tuple);
  assert.ok(source.includes('python3 build.py build -t release --target ${target.target}'));
  assert.ok(source.includes('python3 build.py build -t release -j ${jobs} --target ${target.target}'));
  assert.ok(source.includes('await assertBootstrapCompiler({sdk, command})'));
});

test('source workflow publishes the complete iOS bundle only for the requested Darwin source cell', async () => {
  const workflow = await fs.readFile(new URL('.github/workflows/srcbuild.yml', root), 'utf8');
  const start = workflow.indexOf('      - name: Install and probe iOS SDKs');
  const end = workflow.indexOf('      - name: Upload final source-built std install root', start);
  const block = workflow.slice(start, end);
  assert.equal(block.match(/if: matrix.target == 'darwin-arm64' && inputs.build_ios/g)?.length, 3);
  assert.ok(block.includes('requirement: xcode-ios'));
  assert.ok(block.includes('run: npx --yes zx@8 ci/srcbuild/steps/build-ios-final-std.mjs'));
  assert.ok(block.includes('name: final-std-ios'));
  assert.ok(block.includes('path: ${{ env.CANGJIE_WORKSPACE }}/software/final-std-ios'));
});
