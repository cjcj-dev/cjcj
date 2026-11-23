#!/usr/bin/env node
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [compiler, root] = process.argv.slice(2);
assert([compiler, root].every(p => p && path.isAbsolute(p)),
  'usage: node run-aggregate-receivers.mjs /absolute/bin/cjc /new/output');
fs.mkdirSync(root);
const modal = ['--experimental', '--enable-local-mode', '--output-type=cjo'];
const producerSource = fileURLToPath(new URL('./aggregate_receivers.cj', import.meta.url));
const failures = [];

function compile(name, source, flags, productName, rejectedMemberLine) {
  const cwd = path.join(root, name);
  fs.mkdirSync(cwd);
  const isCjo = flags.includes('--output-type=cjo');
  const product = path.join(cwd, productName + (isCjo ? '.cjo' : '.a'));
  const argv = [...flags, ...(isCjo ? [] : ['--output-type=staticlib']), '--diagnostic-format=json',
    source, '-o', isCjo ? cwd : product];
  const r = spawnSync(compiler, argv, {cwd, encoding: 'utf8'});
  const bytes = fs.statSync(product, {throwIfNoEntry: false})?.size ?? null;
  fs.writeFileSync(path.join(cwd, 'result.json'), JSON.stringify({
    compiler, argv, rc: r.status, signal: r.signal, bytes, stdout: r.stdout, stderr: r.stderr
  }, null, 2));
  if (r.error) throw r.error;
  let errors = [];
  try { errors = JSON.parse(r.stderr).Diags.filter(d => d.Severity === 'error'); }
  catch { /* A missing diagnostic cannot pass the rejection control. */ }
  const rejection = errors.length === 1 && errors[0].Message.includes("'size' is not a member") &&
    errors[0].Location.File === source && errors[0].Location.Line === rejectedMemberLine;
  const ok = rejectedMemberLine === undefined ? r.status === 0 && bytes > 0
    : r.status === 1 && bytes === null && rejection;
  console.log(name, 'compiler rc', r.status, ok ? 'PASS' : 'FAIL');
  if (!ok) failures.push(name);
  return cwd;
}

function consumer(name, decl, producer, options, rejectedMemberLine) {
  const file = path.join(root, name + '.cj');
  fs.writeFileSync(file, 'package client\nimport modalaggregatereceivers.CjoAggregateBag\n' + decl + '\n');
  compile(name, file, [...options, '--import-path', producer], 'client', rejectedMemberLine);
}

for (const api of ['off', 'on']) {
  const producerName = 'aggregateProducer-' + api;
  const producer = compile(producerName, producerSource, [...modal, '--cfg', 'local_mode_api=' + api],
    'modalaggregatereceivers');
  assert(!failures.includes(producerName), 'interface production failed: ' + producer);
  for (const [mode, options] of [['default', []], ['local', modal]]) {
    const label = api + '-' + mode;
    // Each projection uses the tuple's mode. Referencing bag twice must not look like a cycle.
    const projected = 'let bag = CjoAggregateBag()\nlet pair = (bag, bag)\n';
    consumer('aggregateSize-' + label, 'public func check(): Int64 {\n' + projected + 'pair[0].size\n}',
      producer, options);
    consumer('aggregateMethod-' + label, 'public func check(): Bool {\n' + projected + 'pair[0].isEmpty()\n}',
      producer, options);
  }
  consumer('knownLocalSize-' + api, 'public func check(bag: CjoAggregateBag @local!): Int64 { bag.size }',
    producer, modal, api === 'off' ? 3 : undefined);
  if (api === 'on') {
    consumer('aggregateLocalCtor', 'public func check(): Int64 { let bag = CjoAggregateBag() @local!\nbag.size }',
      producer, modal);
  }
}
assert.deepEqual(failures, []);
