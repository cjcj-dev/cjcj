#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [compiler, output] = process.argv.slice(2);
const root = path.resolve(output);
fs.mkdirSync(root); // Require fresh outputs: a stale CJO must never pass.
const enabled = ['--experimental', '--enable-local-mode', '--disable-codegen'];
const signatures = fileURLToPath(new URL('./signatures.cj', import.meta.url));
function compile(name, source, args, diag) {
  const cwd = path.join(root, name);
  fs.mkdirSync(cwd);
  const archive = path.join(cwd, name + '.a');
  const argv = [...args, '--output-type=staticlib', '--diagnostic-format=json', source, '-o', archive];
  const r = spawnSync(compiler, argv, {cwd, encoding:'utf8'});
  fs.writeFileSync(path.join(cwd, 'result.json'), JSON.stringify({compiler, argv, rc:r.status,
    signal:r.signal, stdout:r.stdout, stderr:r.stderr}, null, 2));
  if (r.error) throw r.error;
  assert.equal(r.status, diag ? 1 : 0, name + ': ' + r.stderr);
  if (diag) assert.match(r.stderr + r.stdout, diag, name);
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
consumer('ordinary', 'let f = plain\nplainNested(f)', []);
consumer('bareFull', 'let f = full\nf(20, 22)', [], disabled);
consumer('bareHalf', 'let f = half\nf(20, 22)', [], disabled);
consumer('nestedDisabled', 'let f = nested\n0', [], disabled);
consumer('enabledNested', 'let f = full\nnested(f)', enabled);
consumer('enabledHalf', 'let f = half\nnested(f)', enabled);
consumer('wrongMode', 'nested(plain)', enabled, /mismatched|incompatible|no.match|cannot.match/i);
console.log('CJO cross-package signature controls passed');
