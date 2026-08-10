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
  'core-lineage': Object.freeze([
    'LLVM_SHA',
    'LLC_SOURCE',
    'LLC_VERSION',
    'LLC_SHA256',
    'OPT_SOURCE',
    'OPT_VERSION',
    'OPT_SHA256',
    'LLD_TOOL',
    'LLD_SOURCE',
    'LLD_VERSION',
    'LLD_SHA256',
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
  LLC_SOURCE: /^tuple:[0-9a-f]{40}$/,
  LLC_VERSION: /^[^\r\n\t]+$/,
  CANGJIE_COMPILER_SHA: /^[0-9a-f]{40}$/,
  FLATBUFFERS_SHA: /^[0-9a-f]{40}$/,
  LLC_SHA256: /^[0-9a-f]{64}$/,
  OPT_SOURCE: /^tuple:[0-9a-f]{40}$/,
  OPT_VERSION: /^[^\r\n\t]+$/,
  OPT_SHA256: /^[0-9a-f]{64}$/,
  LLD_TOOL: /^(?:ld\.lld|ld64\.lld)$/,
  LLD_SOURCE: /^tuple:[0-9a-f]{40}$/,
  LLD_VERSION: /^[^\r\n\t]+$/,
  LLD_SHA256: /^[0-9a-f]{64}$/,
  SHIM_SHA256: /^[0-9a-f]{64}$/,
});

export const PACKAGED_LLVM_TOOL_NAMES = Object.freeze([
  'ld.lld',
  'ld64.lld',
  'llc',
  'lld',
  'lld-link',
  'lldb',
  'lldb-argdumper',
  'lldb-instr',
  'lldb-server',
  'lldb-vscode',
  'lli',
  'llvm-addr2line',
  'llvm-ar',
  'llvm-as',
  'llvm-cov',
  'llvm-dis',
  'llvm-link',
  'llvm-lto',
  'llvm-lto2',
  'llvm-objcopy',
  'llvm-objdump',
  'llvm-otool',
  'llvm-profdata',
  'llvm-profgen',
  'llvm-symbolizer',
  'opt',
]);

const PACKAGED_SCHEMA = 'packaged-v1';
const PACKAGED_HEADER = 'tool\tpresent\tsource\tversion\tsha256';
const TOOL_PATTERN = /^[A-Za-z0-9][A-Za-z0-9.+_-]*$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;

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
  if (selectedSchema === 'core-lineage') {
    for (const tool of ['LLC', 'OPT', 'LLD']) {
      const expectedSource = `tuple:${values.get('LLVM_SHA')}`;
      if (values.get(`${tool}_SOURCE`) !== expectedSource) {
        throw new Error(`${label}: ${tool}_SOURCE does not match LLVM_SHA`);
      }
      if (values.get(`${tool}_VERSION`).length > 512) {
        throw new Error(`${label}: ${tool}_VERSION is longer than 512 characters`);
      }
    }
  }
  return {schema: selectedSchema, values};
}

function assertPackagedRow(row, {llvmSha, baseSdkSha256, label}) {
  if (!TOOL_PATTERN.test(row.tool)) throw new Error(`${label}: invalid tool name: ${row.tool}`);
  if (!['yes', 'no'].includes(row.present)) {
    throw new Error(`${label}: ${row.tool}: present must be yes or no`);
  }
  if (/[\r\n\t]/.test(row.source) || /[\r\n\t]/.test(row.version)) {
    throw new Error(`${label}: ${row.tool}: source/version must be single-line TSV values`);
  }
  if (row.present === 'no') {
    if (row.source !== 'none' || row.version !== '-' || row.sha256 !== '-') {
      throw new Error(`${label}: ${row.tool}: absent tools must use source=none version=- sha256=-`);
    }
    return;
  }
  const permittedSources = new Set([`tuple:${llvmSha}`, `base-sdk:${baseSdkSha256}`]);
  if (!permittedSources.has(row.source)) {
    throw new Error(`${label}: ${row.tool}: invalid source: ${row.source}`);
  }
  if (!row.version || row.version === '-') throw new Error(`${label}: ${row.tool}: missing version`);
  if (!SHA256_PATTERN.test(row.sha256)) throw new Error(`${label}: ${row.tool}: invalid sha256`);
}

function validatePackagedTools(tools, metadata, label) {
  const names = tools.map(({tool}) => tool);
  const sortedNames = [...names].sort((left, right) => left.localeCompare(right));
  if (new Set(names).size !== names.length) throw new Error(`${label}: duplicate tool row`);
  if (!names.every((name, index) => name === sortedNames[index])) {
    throw new Error(`${label}: tool rows must be sorted`);
  }
  const missing = PACKAGED_LLVM_TOOL_NAMES.filter((tool) => !names.includes(tool));
  if (missing.length) throw new Error(`${label}: missing canonical tool rows: ${missing.join(',')}`);
  for (const row of tools) assertPackagedRow(row, {...metadata, label});
}

export function formatPackagedLlvmToolsManifest({llvmSha, baseSdkSha256, tools}, {label = 'llvm-tools.manifest'} = {}) {
  if (!/^[0-9a-f]{40}$/.test(llvmSha)) throw new Error(`${label}: invalid LLVM_SHA: ${llvmSha}`);
  if (!SHA256_PATTERN.test(baseSdkSha256)) {
    throw new Error(`${label}: invalid BASE_SDK_SHA256: ${baseSdkSha256}`);
  }
  validatePackagedTools(tools, {llvmSha, baseSdkSha256}, label);
  const rows = tools.map(({tool, present, source, version, sha256}) =>
    [tool, present, source, version, sha256].join('\t'));
  return [
    `SCHEMA=${PACKAGED_SCHEMA}`,
    `LLVM_SHA=${llvmSha}`,
    `BASE_SDK_SHA256=${baseSdkSha256}`,
    PACKAGED_HEADER,
    ...rows,
    '',
  ].join('\n');
}

export function parsePackagedLlvmToolsManifest(text, {label = 'llvm-tools.manifest'} = {}) {
  const lines = text.split(/\r?\n/);
  if (lines.at(-1) === '') lines.pop();
  if (lines[0] !== `SCHEMA=${PACKAGED_SCHEMA}`) throw new Error(`${label}: unsupported packaged schema`);
  const llvmMatch = lines[1]?.match(/^LLVM_SHA=([0-9a-f]{40})$/);
  const baseMatch = lines[2]?.match(/^BASE_SDK_SHA256=([0-9a-f]{64})$/);
  if (!llvmMatch) throw new Error(`${label}: invalid LLVM_SHA header`);
  if (!baseMatch) throw new Error(`${label}: invalid BASE_SDK_SHA256 header`);
  if (lines[3] !== PACKAGED_HEADER) throw new Error(`${label}: invalid TSV header`);
  const tools = lines.slice(4).map((line) => {
    const fields = line.split('\t');
    if (fields.length !== 5) throw new Error(`${label}: malformed tool row: ${line}`);
    const [tool, present, source, version, sha256] = fields;
    return {tool, present, source, version, sha256};
  });
  const result = {llvmSha: llvmMatch[1], baseSdkSha256: baseMatch[1], tools};
  validatePackagedTools(tools, result, label);
  return result;
}

async function main() {
  const [command, schema, manifestFile] = process.argv.slice(2);
  if (command === 'validate-packaged' && schema && !manifestFile) {
    const result = parsePackagedLlvmToolsManifest(await fs.readFile(schema, 'utf8'), {label: schema});
    console.log(`LLVM_TOOLS_MANIFEST_OK schema=${PACKAGED_SCHEMA} tools=${result.tools.length} file=${schema}`);
    return;
  }
  if (command !== 'validate' || !schema || !manifestFile) {
    console.error(
      'usage: llvm-tools-manifest.mjs validate <core|core-lineage|native|core-or-native> <manifest>\n' +
      '       llvm-tools-manifest.mjs validate-packaged <manifest>',
    );
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
