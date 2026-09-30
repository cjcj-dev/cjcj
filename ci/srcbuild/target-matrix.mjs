import fs from 'node:fs';
import {parseArgs} from 'node:util';
import {sourceBuildCells} from '../../build/lib/targets.mjs';

try {
  const {values} = parseArgs({options: {
    targets: {type: 'string', default: 'all'},
    single: {type: 'boolean', default: false},
    'require-ready': {type: 'boolean', default: false},
  }});
  const cells = sourceBuildCells();
  const requested = values.targets.trim();
  const wanted = !requested || requested === 'all'
    ? cells.map(cell => cell.target) : requested.split(',').map(key => key.trim());
  const unknown = wanted.filter(key => !cells.some(cell => cell.target === key));
  if (unknown.length) throw new Error(`unknown source target(s): ${unknown.join(', ')}`);
  const selected = cells.filter(cell => wanted.includes(cell.target));
  if (values.single && selected.length !== 1) throw new Error('source target workflow requires exactly one target');
  const runnable = selected.filter(cell => cell.status === 'runnable');
  const blocked = selected.filter(cell => cell.status === 'blocked');
  const summary = ['| Source target | Status | Reason / follow-up |', '|---|---|---|',
    ...selected.map(cell => `| ${cell.target} | ${cell.status} | ${cell.reasons.join('; ') || 'Inputs declared'} |`)].join('\n') + '\n';
  process.stdout.write(summary);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  const outputs = {
    cells: JSON.stringify({include: selected}),
    matrix: JSON.stringify({include: runnable}),
    blocked: JSON.stringify({include: blocked}),
    has_runnable: String(runnable.length > 0),
    has_blocked: String(blocked.length > 0),
    llvm_platforms: runnable.map(cell => cell.llvm_platform).join(','),
  };
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`).join(''));
  }
  if (values['require-ready'] && blocked.length) {
    throw new Error(blocked.map(cell => `${cell.target} blocked: ${cell.reasons.join('; ')}`).join('\n'));
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
