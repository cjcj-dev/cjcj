// Source-derived inventory for G1's retired Bash entry contracts. Each row
// retains its original source anchor; unhandled guards remain explicit gaps.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
export function exportBranches(source) {
  const rows = [];
  const lines = source.split('\n');
  const bindings = new Map();
  for (const [index, sourceLine] of lines.entries()) {
    const declaration = /^(\w+)=\$\{(\d+):([?-])([^}]*)\}/.exec(sourceLine);
    if (declaration) {
      const [, variable, position, operator, value] = declaration;
      bindings.set(variable, Number(position));
      const args = Array.from({length: Number(position)-1}, (_, i) => `$ARG${i+1}`);
      const inputs = operator === '?' ? [{args}, {args: [...args, '']}] :
        [{args}, {args: [...args, '']}, {args: [...args, '$VALUE']}];
      rows.push({kind: operator === '?' ? 'required' : 'default', line: index+1,
        source: sourceLine, variable, position: Number(position), guard: operator === '?', value, inputs});
    }
    // Nested environment fallbacks are distinct decisions from the positional
    // fallback enclosing them. The names and default values come from source.
    for (const m of sourceLine.matchAll(/\$\{([A-Z_][A-Z_0-9]*):-([^}]*)\}/g)) {
      rows.push({kind:'environment-default', line:index+1, source:sourceLine,
        variable:m[1], value:m[2], inputs:[{env:{[m[1]]:null}}, {env:{[m[1]]:''}}, {env:{[m[1]]:'$VALUE'}}]});
    }
    if (/^\s*(?:if |test |\[\[ )/.test(sourceLine) || /\|\| (?:exit|return)\b/.test(sourceLine)) {
      const positional = /\$\{(\d+):-\}/.exec(sourceLine);
      const named = /\[\[ -n \$(\w+) \]\]/.exec(sourceLine);
      const position = positional ? Number(positional[1]) : named ? bindings.get(named[1]) : undefined;
      const inputs = position ? ['', '$VALUE'].map(value => ({args:Array.from({length:position},(_,i)=>i+1===position?value:`$ARG${i+1}`)})) : null;
      rows.push({kind:'guard',line:index+1,source:sourceLine,position,inputs,
        unresolved:!inputs});
    }
  }
  return rows;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2);
  console.log(JSON.stringify(files.flatMap(file => exportBranches(fs.readFileSync(file,'utf8')).map(row=>({file,...row}))),null,2));
}
