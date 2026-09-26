#!/usr/bin/env zx
// zx owns argv parsing; its process.argv[1] is the zx launcher, not this script.
import {fileURLToPath} from 'node:url';
import {crossStdArguments} from './cross-std-arguments.mjs';
const root = argv['cross-root'];
if (typeof root !== 'string' || !root) throw new Error('--cross-root is required');
const args = crossStdArguments(process.env.CROSS_STD_ARTIFACTS ?? '[]', root);
// zx reparses argv and consumes the separator; retain the product arguments
// from the original process vector, including values containing spaces.
const separator = process.argv.indexOf('--');
if (separator < 0) throw new Error('package arguments must follow --');
const forwarded = process.argv.slice(separator + 1);
const script = fileURLToPath(new URL('../../scripts/package_sdk.mjs', import.meta.url));
await $({stdio: 'inherit'})`npx --yes zx@8 ${script} ${args} ${forwarded}`;
