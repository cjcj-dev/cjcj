import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {g4SourcePhases} from './release-gates.mjs';

const release = fs.readFileSync(path.resolve(import.meta.dirname, '../.github/workflows/release.yml'), 'utf8');

test('G4 counts five source phases among the 20 sdk-build calls of the real release.yml', () => {
  const graph = g4SourcePhases(release);
  assert.deepEqual(graph.problems, []);
  assert.equal(graph.ok, true);
  assert.equal(graph.sdkCalls, 20);
  assert.equal(graph.sourcePhases, 5);
  assert.equal(graph.packageCalls, 15);
});

test('G4 red cut: a missing source phase is NOT_MET', () => {
  const start = release.indexOf('  source-p3-windows-x64:');
  const end = release.indexOf('  source-p4-darwin-arm64:');
  const graph = g4SourcePhases(release.slice(0, start) + release.slice(end));
  assert.equal(graph.ok, false);
  assert.ok(graph.problems.includes('missing source phase 3'), JSON.stringify(graph.problems));
});

test('G4 red cut: a broken phase dependency is NOT_MET', () => {
  const mutated = release.replace('    needs: package-p3-windows-x64\n', '    needs: plan\n');
  assert.notEqual(mutated, release);
  const graph = g4SourcePhases(mutated);
  assert.equal(graph.ok, false);
  assert.ok(graph.problems.includes('source-p4-darwin-arm64 does not need package-p3-windows-x64'), JSON.stringify(graph.problems));
});

test('G4 red cut: a package job detached from its source phase is NOT_MET', () => {
  const mutated = release.replace('    needs: [source-p2-linux-aarch64]\n', '    needs: [plan]\n');
  assert.notEqual(mutated, release);
  const graph = g4SourcePhases(mutated);
  assert.ok(graph.problems.includes('package-p2-linux-aarch64 does not need source-p2-linux-aarch64'), JSON.stringify(graph.problems));
});
