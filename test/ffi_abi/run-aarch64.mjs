#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { $ } from 'zx';
const [compiler, sdk, fixtures, checker, output] = process.argv.slice(2);
if (!output) throw Error('usage: run-aarch64.mjs <public-cjc> <sdk> <generated-fixtures> <bounds-checker> <new-output>');
fs.mkdirSync(output);
const env = {...process.env, CANGJIE_HOME: sdk, PATH: `${sdk}/bin:/usr/local/bin:/usr/bin:/bin`,
    LD_LIBRARY_PATH: `${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/third_party/llvm/lib`};
const records = [];
const run = $({cwd: output, env, quiet: true, nothrow: true, timeout: 300000});
async function step(name, argv) {
    const start = new Date().toISOString();
    const result = await run`${argv}`;
    fs.writeFileSync(path.join(output, name + '.stdout'), result.stdout);
    fs.writeFileSync(path.join(output, name + '.stderr'), result.stderr);
    records.push({name, argv, start, end: new Date().toISOString(), rc: result.exitCode, signal: result.signal});
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(records, null, 2));
    console.log(`${name}: rc=${result.exitCode} signal=${result.signal}`);
    return result.exitCode;
}
fs.writeFileSync(path.join(output, 'inputs.json'), JSON.stringify({compiler, sdk, fixtures, checker,
    compilerSha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(sdk, 'libexec/compiler/cjcj-stage1'))).digest('hex'),
    checkerSha256: crypto.createHash('sha256').update(fs.readFileSync(checker)).digest('hex'),
    semanticImports: path.join(sdk, 'modules/linux_x86_64_cjnative'),
    targetLibraries: 'NOT_USED (object output only)',
    target: 'aarch64-unknown-linux-gnu', nativeExecution: 'NOT_RUN'}, null, 2));
const c = await step('c-cross', ['/usr/bin/clang', '--target=aarch64-unknown-linux-gnu', '-std=gnu11', '-O0', '-c', path.join(fixtures, 'aarch64.c'), '-o', path.join(output, 'c.o')]);
// CJO carries semantic declarations. Use the fixed SDK's declarations through
// the public import option; do not relabel its x86 bitcode/libraries as ARM.
const cj = await step('cj-cross', [compiler, path.join(fixtures, 'aarch64.cj'), '--experimental', '--target=aarch64-unknown-linux-gnu', '--import-path', path.join(sdk, 'modules/linux_x86_64_cjnative'), '--output-type=obj', '--compile-target', 'staticlib', '-O0', '--verbose', '--apc-split-num=1', '--save-temps=' + output, '-o', path.join(output, 'cj.o')]);
if (c !== 0 || cj !== 0) process.exit(1);
let failed = await step('object-targets', ['/usr/bin/readelf', '-h', path.join(output, 'c.o'), path.join(output, 'cj.o')]) !== 0;
for (const name of ['c.o', 'cj.o']) {
    const elf = fs.readFileSync(path.join(output, name));
    if (!elf.subarray(0, 4).equals(Buffer.from([127, 69, 76, 70])) || elf[5] !== 1 || elf.readUInt16LE(18) !== 183)
        throw Error(name + ' is not little-endian AArch64 ELF');
}
// The normal driver installs the requested triple during its opt stage.
// Check that real backend module, not the frontend's host-default marker.
const bc = path.join(output, 'aarch64.opt.bc');
for (const [name, prefix] of [['return', 'cj_ret_'], ['incoming', 'cj_echo_'], ['outgoing', 'cj_call_'], ['control', 'cj_scalar_control'], ['exact-control', 'cj_ret_B8'], ['hfa-control', 'cj_ret_H']]) {
    if (await step(name + '-bounds', [checker, bc, prefix]) !== 0) failed = true;
}
process.exitCode = failed ? 1 : 0;
