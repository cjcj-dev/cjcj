import fs from 'node:fs';
import {llvmToolMatrix} from '../build/lib/targets.mjs';

const matrix = llvmToolMatrix(process.env.REQUESTED || 'all', {
  platformSet: process.env.PLATFORM_SET || '',
  publishTuple: process.env.PUBLISH_TUPLE === 'true',
});
const output = JSON.stringify(matrix);
console.log(output);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `matrix=${output}\n`);
const tuplePlatforms = matrix.include.filter(cell => /^(linux|darwin)_/.test(cell.platform)).map(cell => cell.platform);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `tuple_platforms=${JSON.stringify(tuplePlatforms)}\n`);
const dylibMatrix = {include: matrix.include.filter(cell => /^(linux|darwin)_/.test(cell.platform))
  .map(cell => ({runner: cell.runner, platform: cell.platform,
    library: cell.platform.startsWith('darwin_') ? 'libLLVM.dylib' : 'libLLVM-15.so'}))};
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `dylib_matrix=${JSON.stringify(dylibMatrix)}\n`);
