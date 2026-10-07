#!/usr/bin/env zx
// Export the retired Bash entry's decisions, not a separately maintained argv list.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
export function exportBranches(source) {
  const rows = [];
  const line = index => source.slice(0, index).split('\n').length;
  const add = (kind, match, triggers) => rows.push({kind, line: line(match.index), source: match[0], triggers});
  const cases = source.matchAll(/^        ([^\n]+)\)\n([\s\S]*?)            ;;/gm);
  for (const match of cases) {
    const [ , labels, body] = match;
    const assignment = body.match(/\b(\w+)=\$2/);
    if (assignment) {
      if (!body.includes('(($# < 2))') || !body.includes('[[ -z $2 ]]')) throw Error('unrecognized value guard');
      add('case:value', match, [{args: [labels], target: 'missing_value'}, {args: [labels, ''], target: 'empty_value'},
        {args: [labels, 'VALUE'], target: 'assignment', key: assignment[1]},
        {args: [labels, '--help'], target: 'flag_as_value', key: assignment[1]},
        {args: [labels, ''], target: 'duplicate_last_empty', key: assignment[1]}]);
    } else if (body.includes('usage') && body.includes('exit 0')) {
      add('case:help', match, labels.split('|').map(label => ({args: [label], target: 'help'})));
    } else if (labels === '*' && body.includes('exit 2')) {
      add('case:unknown', match, ['--unknown', '', 'two words', "a'b", '$x', 'é'].map(value => ({args: [value], target: 'unknown'})));
    } else throw Error(`unrecognized case: ${labels}`);
  }
  for (const match of source.matchAll(/^(llvm_repo|llvm_ref|runtime_repo|runtime_ref)=$/gm)) {
    add('default:empty', match, [{args: [], target: 'all_defaults'}, {omit: match[1], target: 'unset_default'}]);
  }
  const required = /for required in ([\w ]+); do\n([\s\S]*?)\ndone/.exec(source);
  if (!required || !required[2].includes('[[ -z ${!required} ]]')) throw Error('unrecognized required loop');
  for (const key of required[1].trim().split(/ +/)) add('required', required, [{omit: key, target: 'missing_required'}]);
  for (const match of source.matchAll(/if ! (\w+)_commit=\$\(resolve_ref[^\n]+\); then\n([\s\S]*?)\nfi/g)) {
    add('resolve', match, [{side: match[1], mode: 'bad-ref'}, {side: match[1], mode: 'bad-repo'}]);
  }
  const temporary = /work=\$\(mktemp[^\n]+/.exec(source);
  if (!temporary || !temporary[0].includes('${TMPDIR:-/tmp}') || !temporary[0].includes('exit 2')) throw Error('unrecognized temporary guard');
  add('temporary', temporary, [{tmp: 'unset'}, {tmp: ''}, {tmp: 'valid'}, {tmp: 'invalid'}]);
  for (const match of source.matchAll(/printf 'ABI_PAIR=(SOURCE_ERROR|CODEGEN_MISMATCH|OK|MISMATCH)[^\n]+/g)) {
    const side = /side=(\w+)/.exec(match[0])?.[1];
    add('result', match, [{mode: match[1], side}]);
  }
  if (rows.filter(row => row.kind === 'result').length !== 5) throw Error('unrecognized result exits');
  return rows;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) console.log(JSON.stringify(exportBranches(fs.readFileSync(process.argv[2], 'utf8')), null, 2));
