import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {g4SourcePhases} from './release-gates.mjs';

const workflows = path.resolve(import.meta.dirname, '../.github/workflows');
const release = fs.readFileSync(path.join(workflows, 'release.yml'), 'utf8');
const prepare = fs.readFileSync(path.join(workflows, 'prepare.yml'), 'utf8');

const mustReplace = (text, from, to) => {
  assert.ok(text.includes(from), `fixture anchor missing: ${from}`);
  return text.replace(from, to);
};

test('G4 accepts the four parallel stages: one source call, one 15-cell package matrix, prepare.yml', () => {
  const graph = g4SourcePhases(release, prepare);
  assert.deepEqual(graph.problems, []);
  assert.equal(graph.ok, true);
  assert.equal(graph.sdkCalls, 1);
  assert.equal(graph.packageCalls, 1);
  assert.equal(graph.packageCells, 15);
  assert.equal(graph.prepareCalls, 1);
});

// Each red cut is applied to the real workflow text and must be named precisely.
const releaseCuts = [
  ['a second, serial source call', text => mustReplace(text, '  # The 15 release assets', [
    '  source-p2:', '    needs: package', '    uses: ./.github/workflows/sdk-build.yml', '    with:', '      targets: linux-aarch64', '',
    '  # The 15 release assets'].join('\n')), /exactly one sdk-build\.yml source call, found 2/],
  ['source split to one host', text => mustReplace(text, '      targets: all\n', '      targets: linux-x64\n'), /targets: all/],
  ['a cross std left off', text => mustReplace(text, '      build_ios: true\n', '      build_ios: false\n'), /must set build_ios: true/],
  ['package detached from source', text => mustReplace(text, '    needs: source\n', '    needs: plan\n'), /package must need only source/],
  ['package matrix serialised', text => mustReplace(text, '      fail-fast: false\n      matrix:', '      fail-fast: false\n      max-parallel: 1\n      matrix:'), /every cell in parallel/],
  ['a package cell dropped', text => text.replace(/\n {10}- \{release_key: darwin-arm64-ios,[^\n]*/, ''), /15 distinct release cells, found 14\/14/],
  ['publish detached from package', text => mustReplace(text, 'needs: [plan, package]', 'needs: [plan]'), /publish does not need package/],
  ['the 22-call serial layout restored', text => text.replace('  # The 15 release assets', Array.from({length: 21}, (_, i) =>
    `  source-extra-${i}:\n    needs: plan\n    uses: ./.github/workflows/sdk-build.yml\n    with:\n      targets: linux-x64\n`).join('\n') + '\n  # The 15 release assets'),
    /exactly one sdk-build\.yml source call, found 22/],
  ['phase input restored', text => mustReplace(text, '    if: ${{ !inputs.dry_run }}', "    if: inputs.phase == 'publish' && !inputs.dry_run"), /still reads inputs\.phase/],
];
for (const [name, cut, expected] of releaseCuts) {
  test(`G4 red cut: ${name} is NOT_MET`, () => {
    const graph = g4SourcePhases(cut(release), prepare);
    assert.equal(graph.ok, false);
    assert.match(graph.problems.join('\n'), expected);
  });
}

const prepareCuts = [
  ['a prepare source build not bound to the same-run inputs', text => mustReplace(text, '      native_inputs_run_id: ${{ github.run_id }}', '      native_inputs_run_id: ${{ inputs.native_inputs_run_id }}'),
    /prepare-srcbuild-linux-x64 native_inputs_run_id must be \$\{\{ github\.run_id \}\}/],
  ['a prepare source build for every target', text => mustReplace(text, '      targets: linux-x64', '      targets: all'), /must build only linux-x64/],
  ['a native host dropped', text => mustReplace(text, '          - target: darwin-x64\n', '          - target: darwin-x64-dropped\n'), /must cover the five native hosts/],
  ['prepare-native routed back through sdk-build-target.yml', text => mustReplace(text, '  prepare-srcbuild-linux-x64:', '  extra:\n    uses: ./.github/workflows/sdk-build-target.yml\n\n  prepare-srcbuild-linux-x64:'),
    /exactly one same-run linux-x64 sdk-build\.yml call, found 2/],
];
for (const [name, cut, expected] of prepareCuts) {
  test(`G4 red cut: ${name} is NOT_MET`, () => {
    const graph = g4SourcePhases(release, cut(prepare));
    assert.equal(graph.ok, false);
    assert.match(graph.problems.join('\n'), expected);
  });
}
