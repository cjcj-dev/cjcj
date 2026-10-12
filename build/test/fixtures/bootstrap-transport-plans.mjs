#!/usr/bin/env zx
// Complete schema-valid inputs for transport tests. No producer is executed,
// and these selectors are deliberately not receipts or compiler evidence.
import fs from 'node:fs/promises';
import path from 'node:path';
import {BOOTSTRAP_PHASES, validateBootstrapPlans} from '../../../ci/bootstrap/freeze-bootstrap-plans.mjs';
import {ROLES, canonical} from '../../../ci/bootstrap/sdk-manifest.mjs';

export async function writeTransportPlans(root) {
  const input = {path: path.join(root, 'unexecuted-input'), sha256: 'a'.repeat(64)};
  const tools = Object.fromEntries(['python3', 'node', 'git', 'bash', 'tar', 'cmake', 'clang', 'clang++', 'cc', 'ar', 'compilerIdentity']
    .map(name => [name, input]));
  tools.builder = {...input, path: path.join(root, 'unexecuted-builder.mjs')};
  const official = {id: 'official', roles: ['official-host'], domain: 'host',
    source: {kind: 'distribution', root, lock: path.join(root, 'unexecuted-lock.json'), lockSha256: 'a'.repeat(64),
      version: 'transport-fixture', reason: 'schema-only transport input; never assembled'},
    config: {host: 'linux_x86_64', target: 'linux_x86_64', options: {}, tools: {}},
    producer: {adapter: 'official', version: 'a'.repeat(40)}, dependencies: [], install: [{from: 'host', to: 'host'}]};
  const native = {id: 'native', roles: ROLES.filter(role => role !== 'official-host'), domain: 'target',
    source: {kind: 'git', repo: root, commit: 'b'.repeat(40), tree: 'c'.repeat(40)},
    config: {host: 'linux_x86_64', target: 'linux_x86_64', tools,
      options: {parameters: {}, optimization: 'Release', sdkDependency: 'official', inputBindings: {},
        outputs: ['bin/cjc'], jobs: 64, heap: '32GB'}},
    producer: {adapter: 'sharedbuild-runtime-default', version: 'a'.repeat(40), repository: root,
      engine: path.join(root, 'unexecuted-engine.py'), engineSha256: 'a'.repeat(64), recipe: path.join(root, 'unexecuted-recipe.json')},
    dependencies: ['official'], install: [{from: '', to: ''}]};
  const phases = Object.fromEntries(BOOTSTRAP_PHASES.map(phase => [phase, {
    schema: 'toolchain-sdk-plan-v1', lane: 'bootstrap-transport', platform: 'linux_x86_64',
    role: ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? 'host' : 'target',
    stage: phase === 'stage3' ? 'final' : ['stage2', 'stage3-std'].includes(phase) ? 'stage2' : 'stage1',
    buildRoot: path.join(root, 'unexecuted-builds', phase), components: [official, native],
    verification: {runtimePin: input, colourRuntime: input, hostRuntime: input, hostRuntimeDir: root},
  }]));
  const bundle = validateBootstrapPlans({schema: 'bootstrap-sdk-plans-v1', phases});
  const file = path.join(root, 'transport-plans.json');
  await fs.writeFile(file, canonical(bundle));
  return {file, bundle};
}
