#!/usr/bin/env zx

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
if (!workspace) throw new Error('CANGJIE_WORKSPACE is required');

const pins = [
  ['compiler', 'cangjie_compiler', 'COMPILER_SRC_URL', 'COMPILER_REF'],
  ['runtime', 'cangjie_runtime', 'RUNTIME_SRC_URL', 'RUNTIME_REF'],
  ['tools', 'cangjie_tools', 'TOOLS_SRC_URL', 'TOOLS_REF'],
  ['stdx', 'cangjie_stdx', 'STDX_SRC_URL', 'STDX_REF'],
];

for (const [component, directory, urlVariable, refVariable] of pins) {
  const expectedUrl = process.env[urlVariable];
  const expectedRef = process.env[refVariable];
  if (!expectedUrl || !/^https:\/\//.test(expectedUrl)) {
    throw new Error(`${urlVariable} must be an HTTPS repository URL`);
  }
  if (!expectedRef || !/^[0-9a-f]{40}$/.test(expectedRef)) {
    throw new Error(`${refVariable} must be a lowercase 40-character commit SHA`);
  }

  const source = `${workspace}/${directory}`;
  const actualUrl = (await $({stdio: 'pipe'})`git -C ${source} remote get-url origin`).stdout.trim();
  if (actualUrl !== expectedUrl) {
    throw new Error(`${component} URL mismatch: expected ${expectedUrl}, got ${actualUrl}`);
  }
  const actualRef = (await $({stdio: 'pipe'})`git -C ${source} rev-parse HEAD`).stdout.trim();
  if (actualRef !== expectedRef) {
    throw new Error(`${component} ref mismatch: expected ${expectedRef}, got ${actualRef}`);
  }
  console.log(`SOURCE_PIN_PASS component=${component} url=${actualUrl} ref=${actualRef}`);
}

console.log(`SOURCE_PINS_PASS checked=${pins.length}`);
