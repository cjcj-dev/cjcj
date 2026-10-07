#!/usr/bin/env zx
// A deliberately narrow shell-source exporter, not a second runtime parser.
// Unsupported source syntax fails instead of silently dropping a branch.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function exportBranches(source) {
  const rows = [];
  const line = offset => source.slice(0, offset).split('\n').length;
  const add = (kind, offset, sourceText, inputs) => rows.push({kind, line: line(offset), source: sourceText, inputs});
  const cases = [...source.matchAll(/case\s+\$\{([^}]+)\}\s+in\n([\s\S]*?)\nesac/g)];
  const modeCase = cases.find(match => !/^\d/.test(match[1]));
  const argCase = cases.find(match => /^\d/.test(match[1]));
  if (!modeCase || !argCase) throw new Error('expected environment and argument cases');
  const mode = modeCase[1].replace(/-.*$/, '');
  const privateArm = [...modeCase[2].matchAll(/^\s*([^\n)]+)\)([\s\S]*?);;/gm)]
    .find(match => /private=1/.test(match[2]));
  if (!privateArm) throw new Error('missing private arm');
  const privateMode = privateArm[1].trim();
  const urlGuard = /\$\{(\w+)-\}\s+==\s+(\S+)/.exec(privateArm[2]);
  const shaGuard = /\$\{(\w+)-\}\s+=~\s+\^\[([^\]]+)\]\{(\d+)\}\$/.exec(privateArm[2]);
  if (!urlGuard || !shaGuard) throw new Error('unsupported private identity guards');
  const length = Number(shaGuard[3]);
  const sha = 'a'.repeat(length);
  const privateEnv = {[mode]: privateMode, [urlGuard[1]]: urlGuard[2], [shaGuard[1]]: sha};
  const operations = [...argCase[2].matchAll(/^\s*([^\n)]+)\)\s*operation=(\w+);\s*shift\s*;;/gm)];
  const check = operations.find(match => match[2] === 'check')?.[1].trim();
  if (!check) throw new Error('missing check operation');
  const input = (env = {}, args = [check, '$DEST'], fixture = 'absent') => ({env, args, fixture});
  for (const block of cases) {
    for (const arm of block[2].matchAll(/^\s*([^\n)]+)\)([\s\S]*?);;/gm)) {
      const label = arm[1].trim();
      const offset = block.index + block[0].indexOf(block[2]) + arm.index;
      let inputs;
      if (block === modeCase) {
        inputs = label === "''" ? [input(), input({[mode]: ''}),
          ...[...arm[2].matchAll(/runtime_\w+=\$(\w+)/g)].flatMap(item =>
            ['', 'inherited'].map(value => input({[item[1]]: value})))]
          : label === '*' ? [input({[mode]: '__unknown__'})]
          : [input({...privateEnv, [mode]: label})];
      } else {
        inputs = [input({}, [label, '$DEST']), input(privateEnv, [label, '$DEST'], 'clean'),
          input({}, [label]), input({}, [label, '']), input({}, [label, '$DEST', 'extra'])];
      }
      add('case-arm', offset, arm[0].trim(), inputs);
    }
  }
  // Each reject is discovered from the old source. The preceding predicate or
  // command determines its witnesses; messages are never used as input lists.
  for (const match of source.matchAll(/reject\s+'([^']+)'/g)) {
    if (modeCase[0].includes(`*) ${match[0]}`)) continue; // covered by its case row
    const before = source.slice(0, match.index);
    const predicate = /\[\[([\s\S]*?)\]\]\s*\\?\s*\|\|\s*$/.exec(before.slice(before.lastIndexOf('[[')));
    let inputs;
    if (predicate) {
      const expression = predicate[1].trim();
      const set = [...expression.matchAll(/!\s*\$\{(\w+)\+x\}/g)].map(item => item[1]);
      if (set.length) {
        const seed = before.lastIndexOf('private)') > before.lastIndexOf("'')") ? privateEnv : {};
        inputs = set.flatMap(name => ['', 'present'].map(value => input({...seed, [name]: value})));
      } else if (/\$#/.test(expression)) {
        const arity = Number(/\$#\s*==\s*(\d+)/.exec(expression)?.[1]);
        if (arity !== 1) throw new Error(`unsupported arity ${expression}`);
        inputs = [input({}, []), input({}, ['']), input({}, ['$DEST', 'extra'])];
      } else if (/=~/.test(expression)) {
        inputs = [undefined, '', sha.slice(1), `${sha}a`, sha.toUpperCase(), 'g'.repeat(length)]
          .map(value => input({...privateEnv, [shaGuard[1]]: value}));
      } else if (/==\s*https:/.test(expression)) {
        inputs = [undefined, '', 'https://example.invalid/runtime.git']
          .map(value => input({...privateEnv, [urlGuard[1]]: value}));
      } else if (/pwd -P/.test(expression)) {
        inputs = [input(privateEnv, [check, '$DEST'], 'subdirectory')];
      } else if (/-z\s+\$status/.test(expression)) {
        inputs = ['tracked-dirty', 'untracked-dirty'].map(fixture => input(privateEnv, [check, '$DEST'], fixture));
      } else if (/rev-parse HEAD/.test(expression)) {
        const verify = operations.find(item => item[2] === 'verify')[1].trim();
        inputs = [input({...privateEnv, [shaGuard[1]]: 'b'.repeat(length)}, [verify, '$DEST'], 'clean')];
      } else throw new Error(`unsupported predicate ${expression}`);
    } else if (/rev-parse --show-toplevel[^\n]*\)\s*\\?\s*\|\|\s*$/.test(before)) {
      inputs = [input(privateEnv, [check, '$DEST'], 'nongit')];
    } else if (/status --porcelain[^\n]*\)\s*\\?\s*\|\|\s*$/.test(before)) {
      inputs = [input(privateEnv, [check, '$DEST'], 'corrupt-index')];
    } else throw new Error(`unclassified reject at ${line(match.index)}`);
    add('guard-error', match.index, match[0], inputs);
  }
  for (const match of source.matchAll(/^(operation=\w+|private=\d+)$/gm)) {
    add('default', match.index, match[0], [input({}, ['$DEST']), input(privateEnv, ['$DEST']),
      ...(match[0].startsWith('operation=') ? [input({}, ['relative destination']), input({}, ['--unknown'])] : [])]);
  }
  // Expand condition axes mechanically, including both sides of && and the
  // operation's successful/unsuccessful exit routes.
  for (const match of source.matchAll(/(?:if |^)(\[\[\s*\$(?:private|operation)[^\n]+?\]\])/gm)) {
    const expression = match[1];
    let inputs;
    if (/-e \$dest/.test(expression)) {
      inputs = [input(), input(privateEnv), input(privateEnv, [check, '$DEST'], 'clean')];
    } else if (/operation/.test(expression)) {
      inputs = operations.flatMap(arm => [input({}, [arm[1].trim(), '$DEST']),
        input(privateEnv, [arm[1].trim(), '$DEST'], 'clean')]);
      inputs.push(input({}, ['$DEST']), input(privateEnv, ['$DEST']));
    } else inputs = [input({}, ['$DEST']), input(privateEnv, ['$DEST'])];
    add('control', match.index, expression, inputs);
  }
  return {mode, privateEnv, shaVariable: shaGuard[1], urlVariable: urlGuard[1], rows};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(exportBranches(fs.readFileSync(process.argv[2], 'utf8')), null, 2));
}
