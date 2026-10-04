import {platformTestCells} from '../../build/lib/targets.mjs';
import { appendFileSync, readFileSync } from 'node:fs';

// Read the actual platform routing and runner list, so the summary cannot keep
// an obsolete copy when the matrix or its dispatch switches change.
const workflow = readFileSync('.github/workflows/platform-matrix.yml', 'utf8');
const platform = workflow.split(/^  platform:\s*$/m)[1]?.split(/^  [\w-]+:/m)[0];
if (!platform) throw new Error('platform job not found');
const condition = platform.match(/^    if: (.+)$/m)?.[1];
if (!condition) throw new Error('platform condition not found');
const switches = [...condition.matchAll(/!inputs\.(\w+_only)\b/g)].map(m => m[1]);
const runners = platformTestCells().map(cell => cell.runner);
if (!switches.length || !runners.length) throw new Error('platform routing or runners not found');
const inputs = JSON.parse(process.env.MATRIX_INPUTS || '{}');
const selected = switches.filter(key => inputs[key] === true || inputs[key] === 'true');
const lines = ['## Platform matrix coverage', ''];
if (selected.length) {
  lines.push('**Subset dispatch: this run does not establish a platform matrix pass.**', '',
    `Selected inputs: ${selected.map(key => `\`${key}\``).join(', ')}`, '',
    'The following platform jobs are skipped:', '',
    ...runners.map(runner => `- ${runner} / runtime + cjcj + smoke`));
} else {
  lines.push(`Full platform matrix requested (${runners.length} jobs).`, '',
    'This describes requested coverage only. Consult every runtime + cjcj + smoke job conclusion for results.');
}
appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${lines.join('\n')}\n`);
