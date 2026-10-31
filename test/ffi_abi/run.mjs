#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { $ } from 'zx';

const [compiler, sdk, fixtures, output] = process.argv.slice(2);
if (!compiler || !sdk || !fixtures || !output) throw Error('usage: run.mjs <installed-cjc> <sdk> <fixtures> <new-output>');
fs.mkdirSync(output);
const env = { ...process.env, CANGJIE_HOME: sdk, PATH: `${sdk}/bin:${sdk}/tools/bin:/usr/bin:/bin`,
    LD_LIBRARY_PATH: `${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/lib/linux_x86_64_cjnative:${sdk}/third_party/llvm/lib:${sdk}/tools/lib` };
const run = $({ cwd: output, env, quiet: true, nothrow: true, timeout: 300_000 });
const results = [];
async function step(name, argv) {
    const start = new Date().toISOString();
    const executableSha256 = name.endsWith('-run') ? crypto.createHash('sha256').update(fs.readFileSync(argv[0])).digest('hex') : undefined;
    const r = await run({env: {...env, LD_DEBUG: 'libs'}})`${argv}`;
    fs.writeFileSync(path.join(output, name + '.stdout'), r.stdout);
    fs.writeFileSync(path.join(output, name + '.stderr'), r.stderr);
    fs.writeFileSync(path.join(output, name + '.log'), r.stdout + r.stderr);
    results.push({ name, argv, executableSha256, start, end: new Date().toISOString(), rc: r.exitCode, signal: r.signal });
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    console.log(`${name}: rc=${r.exitCode} signal=${r.signal}`);
    return r.exitCode;
}
let failed = false;
for (const [name, c, cj] of [['control', 'control.c', 'control.cj'], ['abi', 'abi.c', 'main.cj'], ['layout', 'layout.c', 'layout.cj'], ['overalign', 'overalign.c', 'overalign.cj'], ['packed', 'packed.c', 'packed.cj'], ['array', 'array.c', 'array.cj']]) {
    const object = path.join(output, name + '-c.o'), exe = path.join(output, name);
    if (await step(name + '-c', ['/usr/bin/cc', '-std=gnu11', '-O0', '-fPIC', '-c', path.join(fixtures, c), '-o', object]) !== 0) {
        failed = true;
        continue;
    }
    const compile = await step(name + '-cj', [compiler, path.join(fixtures, cj), '-O0', '--verbose', '--apc-split-num=1', '--save-temps=' + output,
        '--link-options', object, '-o', exe]);
    if (compile !== 0) {
        failed = true;
        continue;
    }
    // Preserve the public driver's full result, then execute its recorded
    // linker argv separately so the linker and target have their own statuses.
    const stdout = fs.readFileSync(path.join(output, name + '-cj.stdout'), 'utf8');
    const linkLine = stdout.split('\n').find(line => /^'[^']*\/(?:ld|ld.lld)' /.test(line));
    if (!linkLine || linkLine.replace(/'[^']*'/g, '').trim()) throw Error('unsupported recorded linker argv');
    const linkArgs = [...linkLine.matchAll(/'([^']*)'/g)].map(match => match[1]);
    const outputIndex = linkArgs.indexOf('-o');
    if (outputIndex < 0 || linkArgs[outputIndex + 1] !== exe) throw Error('link output does not match this fixture');
    linkArgs[outputIndex + 1] = exe + '.linked';
    if (await step(name + '-link', linkArgs) !== 0) { failed = true; continue; }
    if (await step(name + '-run', [exe + '.linked']) !== 0) failed = true;
    if (name === 'packed') {
        const ir = path.join(output, 'packed.ll');
        if (await step('packed-dis', [path.join(sdk, 'third_party/llvm/bin/llvm-dis'), path.join(output, 'packed.bc'), '-o', ir]) !== 0 ||
            await step('packed-alignment', [process.execPath, path.join(fixtures, 'check-packed-ir.mjs'), ir, path.join(output, 'packed-alignment.json')]) !== 0) failed = true;
    }
}
process.exitCode = failed ? 1 : 0;
