#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {colourEnvironment} from './prepare-colour-sdk.mjs';
const [mode, separator, command, ...args] = process.argv.slice(2);
if (!['build', 'run'].includes(mode) || separator !== '--' || !command) {
  throw new Error('usage: with-colour-sdk.mjs build|run -- command [args...]');
}
const result = spawnSync(command, args, {stdio: 'inherit', env: await colourEnvironment(mode)});
process.exitCode = result.status ?? 1;
