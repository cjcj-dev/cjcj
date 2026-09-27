#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {platformizeCjcToml} from '../platform_matrix/link_option.mjs';

const [source, sdk] = process.argv.slice(2);
assert.equal(process.platform, 'darwin', 'native Darwin link preparation requires Darwin');
const file = path.join(source, 'packages/cjc/cjpm.toml');
fs.writeFileSync(file, platformizeCjcToml(fs.readFileSync(file, 'utf8'), process.platform, sdk));
console.log(`BOOTSTRAP_NATIVE_LINK_CONFIGURED file=${file} sdk=${sdk}`);
