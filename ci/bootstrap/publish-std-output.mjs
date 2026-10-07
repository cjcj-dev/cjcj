#!/usr/bin/env zx
import {publishBootstrapStdOutput} from './std-output.mjs';

const [work, prefix, compiler, tuple] = argv._;
if (!work || !prefix || !compiler || !tuple || argv._.length !== 4) {
  throw new Error('usage: publish-std-output.mjs WORK PREFIX COMPILER TUPLE');
}
await publishBootstrapStdOutput({work, prefix, compiler, tuple});
