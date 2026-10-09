import test from 'node:test';
import assert from 'node:assert/strict';
import {readRuntimeCommit} from './runtime-provenance.mjs';

test('retained runtime commit uses the producer newline format', () => {
  // runtime/build/cmake/GenerateRuntimeProvenance.cmake:123 emits this field
  // followed by a newline and further fields, not a terminating NUL.
  const commit = 'f2283db793be1fcbe986f9a4ed5c217609dcf3ca';
  const produced = Buffer.from(`CJRT-COMMIT:${commit}\nCJRT-DECLARED:${commit}\0`);
  assert.equal(readRuntimeCommit(produced), commit);
});
