#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Single source of truth for llvm-tools.manifest. Platform-tuple artifacts carry
// only the tool lineage; native source-build artifacts additionally bind the
// runner platform, shim inputs and shim payload.
export const LLVM_TOOLS_MANIFEST_SCHEMAS = Object.freeze({
  core: Object.freeze([
    'LLVM_SHA',
    'LLC_SHA256',
    'OPT_SHA256',
  ]),
  native: Object.freeze([
    'PLATFORM',
    'LLVM_SHA',
    'CANGJIE_COMPILER_SHA',
    'FLATBUFFERS_SHA',
    'LLC_SHA256',
    'OPT_SHA256',
    'SHIM_SHA256',
  ]),
});

const FIELD_PATTERNS = Object.freeze({
  PLATFORM: /^(?:linux_(?:x86_64|aarch64)|darwin_(?:x86_64|aarch64)|windows_x86_64)$/,
  LLVM_SHA: /^[0-9a-f]{40}$/,
  CANGJIE_COMPILER_SHA: /^[0-9a-f]{40}$/,
  FLATBUFFERS_SHA: /^[0-9a-f]{40}$/,
  LLC_SHA256: /^[0-9a-f]{64}$/,
  OPT_SHA256: /^[0-9a-f]{64}$/,
  SHIM_SHA256: /^[0-9a-f]{64}$/,
});

function assertSchema(values, schema, label) {
  const expected = LLVM_TOOLS_MANIFEST_SCHEMAS[schema];
  if (!expected) throw new Error(`${label}: unknown manifest schema: ${schema}`);
  const expectedSet = new Set(expected);
  const missing = expected.filter((field) => !values.has(field));
  const unexpected = [...values.keys()].filter((field) => !expectedSet.has(field));
  if (missing.length || unexpected.length) {
    throw new Error(
      `${label}: ${schema} field contract mismatch; missing=${missing.join(',') || 'none'} ` +
      `unexpected=${unexpected.join(',') || 'none'}`,
    );
  }
}

export function parseLlvmToolsManifest(text, {label = 'llvm-tools.manifest', schema = 'core-or-native'} = {}) {
  const values = new Map();
  for (const line of text.split(/\r?\n/).filter(Boolean)) {
    const match = line.match(/^([A-Z0-9_]+)=(.+)$/);
    if (!match) throw new Error(`${label}: malformed line: ${line}`);
    const [, field, value] = match;
    if (values.has(field)) throw new Error(`${label}: duplicate field: ${field}`);
    values.set(field, value);
  }

  let selectedSchema = schema;
  if (schema === 'core-or-native') {
    const matching = Object.keys(LLVM_TOOLS_MANIFEST_SCHEMAS)
      .filter((candidate) => {
        const fields = LLVM_TOOLS_MANIFEST_SCHEMAS[candidate];
        return fields.length === values.size && fields.every((field) => values.has(field));
      });
    if (matching.length !== 1) {
      const knownFields = [...new Set(Object.values(LLVM_TOOLS_MANIFEST_SCHEMAS).flat())];
      const unexpected = [...values.keys()].filter((field) => !knownFields.includes(field));
      throw new Error(
        `${label}: no manifest schema matches ${values.size} fields; ` +
        `unexpected=${unexpected.join(',') || 'none'}`,
      );
    }
    [selectedSchema] = matching;
  }
  assertSchema(values, selectedSchema, label);

  for (const [field, value] of values) {
    if (!FIELD_PATTERNS[field]?.test(value)) {
      throw new Error(`${label}: invalid ${field}: ${value}`);
    }
  }
  return {schema: selectedSchema, values};
}

async function main() {
  const [command, schema, manifestFile] = process.argv.slice(2);
  if (command !== 'validate' || !schema || !manifestFile) {
    console.error('usage: llvm-tools-manifest.mjs validate <core|native|core-or-native> <manifest>');
    process.exit(2);
  }
  const result = parseLlvmToolsManifest(await fs.readFile(manifestFile, 'utf8'), {
    label: manifestFile,
    schema,
  });
  console.log(`LLVM_TOOLS_MANIFEST_OK schema=${result.schema} fields=${result.values.size} file=${manifestFile}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  await main();
}
