#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const [source, output] = process.argv.slice(2);
const code = fs.readFileSync(path.join(source, 'packages/codegen/src/CGCFFI.cj'), 'utf8');
const arm = code.slice(code.indexOf('public open class LinuxAarch64CJNativeCGCFFI'), code.indexOf('@When[os == "macOS"]'));
const word = Number(code.match(/BYTES_PER_WORD: UInt64 = (\d+)u64/)[1]);
const limit = Number(arm.match(/limitSizeOfSmallStruct = (\d+)u64/)[1]);
const hfa = Number(arm.match(/membersBox.value <= (\d+)u64/)[1]);
assert.equal(word, 8); assert.equal(limit, 16); assert.equal(hfa, 4);
fs.mkdirSync(output, {recursive: true});
const cases = [];
const field = (name, cj, c, value, literal) => ({name, cj, c, value, literal});
// Cover every allocation size in the ordinary direct-composite range,
// including exact containers, plus the first indirect size.
for (let n = 1; n <= limit + 1; ++n) cases.push({name: `B${n}`, size: n,
    fields: Array.from({length: n}, (_, i) => field(`f${i}`, 'UInt8', 'unsigned char', i + 1, `${i + 1}u8`))});
for (const [cj, c, bytes, suffix] of [['Float32', 'float', 4, 'f32'], ['Float64', 'double', 8, 'f64']]) {
    for (let n = 1; n <= hfa; ++n) cases.push({name: `H${bytes}_${n}`, size: bytes * n,
        fields: Array.from({length: n}, (_, i) => field(`f${i}`, cj, c, `${i + 1}.0`, `${i + 1}.0${suffix}`))});
}
for (const [cj, c, size, literal] of [['UInt32', 'unsigned int', 5, '1000u32'], ['UInt64', 'unsigned long long', 9, '1000u64']]) {
    cases.push({name: `P${size}`, size, attr: 'packed', cattr: '__attribute__((packed))',
        fields: [field('tag', 'UInt8', 'unsigned char', 3, '3u8'), field('value', cj, c, 1000, literal)]});
}
for (const size of [word, limit]) cases.push({name: `A${size}`, size, attr: `align: ${size}`,
    cattr: `__attribute__((aligned(${size})))`, fields: [field('x', 'UInt8', 'unsigned char', 7, '7u8')]});
cases.push({name: 'Nested3', size: 3, fields: [field('inner', 'B3', 'B3', '{1,2,3}', 'B3()')], checks: ['inner.f0==1', 'inner.f1==2', 'inner.f2==3']});
cases.push({name: 'Empty', size: 0, fields: []});
let cj = '', c = '';
for (const t of cases) {
    cj += `@C${t.attr ? `[${t.attr}]` : ''}\nstruct ${t.name} { ${t.fields.map(f => `var ${f.name}: ${f.cj} = ${f.literal}`).join('; ')} }\n`;
    c += `typedef struct ${t.cattr || ''} { ${t.fields.map(f => `${f.c} ${f.name};`).join(' ')} } ${t.name};\n_Static_assert(sizeof(${t.name})==${t.size}, "${t.name} source size");\n`;
}
cj += 'foreign {\n' + cases.map(t => `func c_echo_${t.name}(p: ${t.name}): ${t.name}`).join('\n') + '\n}\n';
for (const t of cases) {
    cj += `@C\nfunc cj_ret_${t.name}(): ${t.name} { return ${t.name}() }\n@C\nfunc cj_echo_${t.name}(p: ${t.name}): ${t.name} { return p }\n@C\nfunc cj_call_${t.name}(p: ${t.name}): ${t.name} { unsafe { return c_echo_${t.name}(p) } }\n`;
    const checks = t.checks || t.fields.map(f => `${f.name}==${f.value}`);
    const check = v => checks.map(x => `${v}.${x}`).join(' && ') || '1';
    c += `extern ${t.name} cj_ret_${t.name}(void);\nextern ${t.name} cj_echo_${t.name}(${t.name});\nextern ${t.name} cj_call_${t.name}(${t.name});\n${t.name} c_echo_${t.name}(${t.name} p) { return p; }\nint c_test_${t.name}(void) { ${t.name} a=cj_ret_${t.name}(); if(!(${check('a')})) return 1; ${t.name} b=cj_echo_${t.name}(a); if(!(${check('b')})) return 2; ${t.name} d=cj_call_${t.name}(b); return !(${check('d')}); }\n`;
}
cj += '@C\nfunc cj_scalar_control(x: UInt64): UInt64 { return x }\n';
c += 'extern unsigned long long cj_scalar_control(unsigned long long);\nint main(void) { if(cj_scalar_control(41)!=41) return 99;\n' + cases.map(t => `if(c_test_${t.name}()) return 1;`).join('\n') + '\nreturn 0; }\n';
fs.writeFileSync(path.join(output, 'aarch64.cj'), cj);
fs.writeFileSync(path.join(output, 'aarch64.c'), c);
fs.writeFileSync(path.join(output, 'cases.json'), JSON.stringify({basis: 'LinuxAarch64CJNativeCGCFFI.GetMappingArgInfo / IsHomogeneousAggregate / ProcessRetValue / ProcessAarch64DirectArg', word, limit, hfa, cases}, null, 2));
console.log(`generated ${cases.length} source-layout cases from AArch64 classification branches`);
