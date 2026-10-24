#!/usr/bin/env zx
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [input, output] = process.argv.slice(2);
const text = fs.readFileSync(input, 'utf8');
const packed = text.split('\n').filter(line => /= type <\{ i8, i32 \}>/.test(line)).map(line => line.split(' = ')[0]);
assert(packed.length, 'packed source storage type must be present');
const checked = [], violations = [];
let addresses = new Set(), functionName = '';
for (const [index, line] of text.split('\n').entries()) {
    if (line.startsWith('define ')) { addresses = new Set(); functionName = line; }
    const definition = line.match(/^\s*(%[\w.$-]+) = (.*)$/);
    if (definition) {
        const [, value, expression] = definition;
        if (packed.some(type => expression.startsWith('getelementptr inbounds ' + type + ',') || expression.startsWith('getelementptr ' + type + ',')) && /, i(?:32|64) 0, i32 1(?:, !|\s*$)/.test(expression)) addresses.add(value);
        if (/^bitcast /.test(expression) && [...addresses].some(address => expression.includes(' ' + address + ' to '))) addresses.add(value);
    }
    const memory = line.match(/(?:load i32, i32(?: addrspace\(\d+\))?\*|store i32 [^,]+, i32(?: addrspace\(\d+\))?\*) (%[\w.$-]+), align (\d+)/);
    if (memory && addresses.has(memory[1])) {
        const result = {line: index + 1, function: functionName, instruction: line.trim(), alignment: Number(memory[2])};
        checked.push(result);
        if (result.alignment > 1) violations.push(result);
    }
}
fs.writeFileSync(output, JSON.stringify({input, packed, checked, violations}, null, 2));
assert(checked.some(row => row.instruction.includes('load i32')), 'must reach packed i32 load invariant');
assert(checked.some(row => row.instruction.includes('store i32')), 'must reach packed i32 store invariant');
assert(checked.some(row => row.instruction.includes('load i32') && !row.instruction.includes('typed.copy')), 'must reach ordinary packed field read');
assert(checked.some(row => row.instruction.includes('store i32 1000,')), 'must reach packed initialization');
assert(checked.some(row => row.function.includes('cj_packed_return')), 'must reach packed return consumer');
assert(checked.some(row => row.instruction.includes('typed.copy')), 'must reach packed typed-copy consumer');
assert.equal(violations.length, 0, 'packed offset-one i32 access overstates alignment');
console.log(`PASS packed LLVM alignment: ${checked.length} real accesses`);
