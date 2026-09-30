import fs from 'node:fs';
import {llvmToolMatrix} from '../build/lib/targets.mjs';

const matrix = llvmToolMatrix(process.env.REQUESTED || 'all', {
  platformSet: process.env.PLATFORM_SET || '',
  publishTuple: process.env.PUBLISH_TUPLE === 'true',
});
const output = JSON.stringify(matrix);
console.log(output);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `matrix=${output}\n`);
