#!/usr/bin/env zx
// Narrow source exporter for the retired publisher. Unknown decisions fail closed.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';

export function exportBranches(source) {
  const rows = [];
  const lines = source.split('\n');
  const array = source.match(/local -a (\w+)=\(([^)]+)\)/);
  if (!array) throw Error('missing payload array');
  const payloads = array[2].trim().split(/\s+/);
  let loop = null, manifest = false, sums = false;
  const add = (kind, index, text, inputs) => rows.push({kind, line: index + 1, source: text, inputs});
  for (const [index, text] of lines.entries()) {
    const value = text.trim();
    if (!value || value.startsWith('#')) continue;
    const defaultRoot = /local (\w+)=\$\{(\d+):-\$\{(\w+):-([^}]+)\}\}/.exec(value);
    if (defaultRoot) {
      const inputs = [
        {args: [], env: {[defaultRoot[3]]: null}, root: defaultRoot[4]},
        {args: [''], env: {[defaultRoot[3]]: null}, root: defaultRoot[4]},
        {args: [], env: {[defaultRoot[3]]: ''}, root: defaultRoot[4]},
        {args: [''], env: {[defaultRoot[3]]: ''}, root: defaultRoot[4]},
        {args: [], env: {[defaultRoot[3]]: '$DEPOT'}, root: '$DEPOT'},
        {args: [''], env: {[defaultRoot[3]]: '$DEPOT'}, root: '$DEPOT'},
        {args: ['$ARG'], env: {[defaultRoot[3]]: '$DEPOT'}, root: '$ARG'},
        {args: ['$ARG', 'ignored'], env: {[defaultRoot[3]]: '$DEPOT'}, root: '$ARG'},
      ];
      // Observe the absolute default in mkdir argv without writing outside the fixture.
      for (const input of inputs) if (input.root === defaultRoot[4]) {
        input.fail = {command: 'mkdir', occurrence: 1}; input.expected = 1;
      } else input.expected = 0;
      add('default:root', index, text, inputs);
      continue;
    }
    if (value.startsWith('[[')) {
      const guard = /^\[\[ -n \$\{(\w+):-\} && -n \$\{(\w+):-\} \]\] \|\| return 1$/.exec(value);
      if (!guard) throw Error(`unsupported guard at ${index + 1}`);
      add('guard:identities', index, text, guard.slice(1).flatMap(key => [
        {env: {[key]: null}, expected: 1}, {env: {[key]: ''}, expected: 1},
      ]).concat([{env: {}, expected: 0}]));
      continue;
    }
    const forLoop = /^for (\w+) in (.+); do$/.exec(value);
    if (forLoop) {
      loop = forLoop[2] === `"\${${array[1]}[@]}"` ? payloads : forLoop[2].trim().split(/\s+/);
      add('loop:payloads', index, text, loop.map(payload => ({payload, expected: 0})));
      continue;
    }
    if (value === 'done') { loop = null; continue; }
    if (value === '{') { manifest = true; continue; }
    if (value === '(') { sums = true; continue; }
    if (value.includes('|| return') || value.includes('|| exit')) {
      if (!/\|\| (?:return|exit) 1$/.test(value)) throw Error(`unsupported exit at ${index + 1}`);
      if (value.startsWith('recipe_sha=$(')) {
        const git = /^recipe_sha=\$\(git -C "\$(\w+)" rev-parse HEAD\) \|\| return 1$/.exec(value);
        if (!git) throw Error('unsupported recipe substitution');
        add('error:recipe', index, text, [
          {env: {[git[1]]: null}, fixture: 'cwd-repo', expected: 0},
          {env: {[git[1]]: ''}, fixture: 'cwd-repo', expected: 0},
          {env: {[git[1]]: '$NONGIT'}, expected: 1},
          {env: {[git[1]]: '$MISSING'}, expected: 1},
          {env: {[git[1]]: '$UNBORN'}, expected: 1},
          {fail: {command: 'git', occurrence: 1}, expected: 1},
        ]);
      } else if (/^(mkdir|cp|gzip|chmod|cd) /.test(value)) {
        const command = value.split(' ')[0];
        const inputs = (loop || [null]).map((payload, i) => ({fail: {command, occurrence: i + 1}, payload, expected: 1}));
        // The second cp site follows all copies in the first loop.
        if (command === 'cp' && !loop) inputs[0].fail.occurrence = payloads.length + 1;
        add(`error:${command}`, index, text, inputs);
      } else if (value.startsWith('} >')) {
        add('error:manifest-redirect', index, text, [{fixture: 'manifest-directory', expected: 1}]);
        manifest = false;
      } else if (value.startsWith(') ||')) {
        add('error:checksum-subshell', index, text, [
          {fail: {command: 'sha256sum', occurrence: 1}, expected: 1},
          {fixture: 'sums-directory', expected: 1},
        ]);
        sums = false;
      } else throw Error(`unrecognized error exit at ${index + 1}`);
      continue;
    }
    // The sha256sum is the subshell's final command; its status reaches || return.
    if (sums && (value.startsWith('sha256sum ') || value.startsWith('"./'))) continue;
    if (manifest && value.startsWith('printf ')) continue;
    if (/^(?:local |publish_fixed_tuple_to_depot\(\) \{|echo |\})/.test(value)) continue;
    throw Error(`unrecognized source at ${index + 1}: ${value}`);
  }
  if (!rows.some(row => row.kind === 'default:root')) throw Error('missing default root');
  return rows;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(exportBranches(fs.readFileSync(process.argv[2], 'utf8')), null, 2));
}
