#!/usr/bin/env zx
// Append one compact terminal error line after all executable job stages.

import fs from 'node:fs/promises';
import path from 'node:path';

const root = process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci');
const summaryFile = path.join(root, 'step-summary.md');
await fs.mkdir(root, {recursive: true});

let lastError = '';
for (const stage of ['runtime', 'cjcj', 'test']) {
  const log = path.join(root, 'logs', `${stage}.log`);
  let text;
  try { text = await fs.readFile(log, 'utf8'); } catch (error) {
    if (error.code === 'ENOENT') continue;
    throw error;
  }
  for (const line of text.split(/\r?\n/)) {
    if (/(^|[^A-Za-z])error:/i.test(line)) lastError = line;
  }
}
lastError = lastError.replace(/\x1b\[[0-9;]*[A-Za-z]/, '') || 'no error: line captured';
const escapedError = lastError.replaceAll('`', "'");
const summary = `\n### Final key error\n\n- runner: \`${process.env.MATRIX_RUNNER || 'local'}\`\n- last \`error:\` line: \`${escapedError}\`\n`;
await fs.appendFile(summaryFile, summary);
if (process.env.GITHUB_STEP_SUMMARY) await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, summary);
console.log(`final_error=${lastError}`);
