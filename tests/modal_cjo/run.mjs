#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [compiler, output] = argv._.map(String);
if (![compiler, output].every(p => p && path.isAbsolute(p))) throw Error('usage: zx run.mjs /absolute/bin/cjc /new/output');
const root = path.resolve(output);
fs.mkdirSync(root); // Require fresh outputs: a stale CJO must never pass.
const enabled = ['--experimental', '--enable-local-mode', '--output-type=cjo'];
const signatures = fileURLToPath(new URL('./signatures.cj', import.meta.url));
const failures = [];
function compile(name, source, args, diag) {
  const cwd = path.join(root, name);
  fs.mkdirSync(cwd);
  const archive = path.join(cwd, name + '.a');
  const cjo = args.includes('--output-type=cjo');
  const argv = [...args, ...(cjo ? [] : ['--output-type=staticlib']), '--diagnostic-format=json', source, '-o', cjo ? cwd : archive];
  const r = spawnSync(compiler, argv, {cwd, encoding:'utf8'});
  fs.writeFileSync(path.join(cwd, 'result.json'), JSON.stringify({compiler, argv, rc:r.status,
    signal:r.signal, stdout:r.stdout, stderr:r.stderr}, null, 2));
  if (r.error) throw r.error;
  const ok = r.status === (diag ? 1 : 0) && (!diag || diag.test(r.stderr + r.stdout));
  console.log(name, 'compiler rc', r.status, 'expected', diag?.source ?? 'success', ok ? 'PASS' : 'FAIL');
  if (ok && !diag) {
    const product = cjo ? path.join(cwd, name === 'producer' ? 'modalsigs.cjo' : 'client.cjo') : archive;
    assert(fs.statSync(product).size > 0, 'missing ' + product);
  }
  if (!ok) failures.push(name);
  if (name === 'producer') assert(ok, 'failed to produce interface: ' + r.stderr);
  return cwd;
}
compile('defaultSource', signatures, [], /"DiagKind":\s*"parse_local_mode_disabled"/);
compile('nativeHeld', signatures, enabled.slice(0, 2), /local mode is unavailable/);
const producer = compile('producer', signatures, enabled);
assert(fs.statSync(path.join(producer, 'modalsigs.cjo')).size > 0);
assert(!fs.existsSync(path.join(producer, 'producer.a')));
function consumer(name, body, options, diag) {
  const file = path.join(root, name + '.cj');
  fs.writeFileSync(file, 'package client\nimport modalsigs.*\npublic func check(): Int64 {\n' + body + '\n}\n');
  compile(name, file, [...options, '--import-path', producer], diag);
}
const disabled = /"DiagKind":\s*"sema_local_api_disabled"/;
consumer('unusedImport', '42', []);
consumer('ordinary', 'let f = plain\nplainNested(f)', []);
consumer('directDisabled', 'full(20, 22)', [], disabled);
consumer('directEnabled', 'full(20, 22)', enabled);
consumer('bareFull', 'let f = full\nf(20, 22)', [], disabled);
consumer('bareHalf', 'let f = half\nf(20, 22)', [], disabled);
consumer('nestedDisabled', 'let f = nested\n0', [], disabled);
consumer('enabledNested', 'let f = full\nnested(f)', enabled);
consumer('enabledHalf', 'let f = half\nnested(f)', enabled);
const noMatch = /"DiagKind":\s*"sema_no_match_function_declaration_for_ref"/;
consumer('wrongMode', 'nested(plain)', enabled, noMatch);
consumer('wrongSlot', 'let f: (Int64 @local!, Int64) -> Int64 = full\nf(20, 22)', enabled,
  noMatch);
consumer('nonCopyRejected', 'let x: String @local! = "s"\n0', enabled, /"DiagKind":\s*"parse_unexpected_modal_type"/);
const unsupported = path.join(root, 'nonCopyParam.cj');
fs.writeFileSync(unsupported, 'package client\npublic func nope(s: String @local!): Int64 { 0 }\n');
compile('nonCopyParam', unsupported, enabled, /"DiagKind":\s*"parse_unexpected_modal_type"/);
assert.deepEqual(failures, []);
console.log('CJO cross-package signature controls passed');
