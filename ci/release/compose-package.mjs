#!/usr/bin/env zx
// zx owns argv parsing; its process.argv[1] is the zx launcher, not this script.
import {fileURLToPath} from 'node:url';
import {crossStdArguments} from './cross-std-arguments.mjs';
const root = argv['cross-root'];
if (typeof root !== 'string' || !root) throw new Error('--cross-root is required');
const args = crossStdArguments(process.env.CROSS_STD_ARTIFACTS ?? '[]', root);
const script = fileURLToPath(new URL('../../scripts/package_sdk.mjs', import.meta.url));
await $({stdio: 'inherit'})`npx --yes zx@8 ${script} ${args} ${argv._}`;
