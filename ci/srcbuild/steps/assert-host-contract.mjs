#!/usr/bin/env node

import {assertHostContract} from '../../../build/lib/targets.mjs';

function usage() {
  return 'usage: assert-host-contract.mjs --target TARGET [--profile generic|kkk2]';
}

let target;
let profile = 'generic';
for (let index = 2; index < process.argv.length; index += 1) {
  const option = process.argv[index];
  if (option === '--target' || option === '--profile') {
    const value = process.argv[index + 1];
    if (!value) {
      console.error(`${option} requires a value`);
      process.exit(2);
    }
    if (option === '--target') target = value;
    else profile = value;
    index += 1;
    continue;
  }
  console.error(`unknown option: ${option}`);
  console.error(usage());
  process.exit(2);
}

if (!target) {
  console.error('--target requires a value');
  process.exit(2);
}
if (!['generic', 'kkk2'].includes(profile)) {
  console.error(`unknown host profile '${profile}'; valid: generic, kkk2`);
  process.exit(2);
}

try {
  const contract = assertHostContract(target, {profile});
  console.log([
    'HOST_CONTRACT',
    `target=${contract.target}`,
    `required_host=${contract.requiredHost.replaceAll(' ', '_')}`,
    `sdk=${contract.sdkName}`,
    `cross=${contract.crossCompile ? 'yes' : 'no'}`,
    `profile=${profile}`,
  ].join(' '));
} catch (error) {
  console.error(error.message);
  process.exit(2);
}
