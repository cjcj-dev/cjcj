#!/usr/bin/env -S npx --yes zx@8

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_SAMPLES = [
  '01_return',
  '42_arraylist',
  '43_hashmap',
  '50_generic_fn',
  '87_lambda_interface_dispatch',
  '113_virtual_dispatch',
];

const SDK_VERSION_RE = /1\.2\.0-alpha\.\d{14}/g;
const SDK_VERSION_CANONICAL = '1.2.0-alpha.00000000000000';
const LAYERS = ['pre-opt-globals', 'post-opt', 'object', 'linked-elf'];

const NORMALIZATION_RULES = [
  {
    id: 'A_SDK_PRODUCER_IDENTITY',
    class: 'A',
    scope: [
      'pre-opt/post-opt: exact LLVM global @cj.sdk.version',
      'object/linked-ELF: same-offset NUL-terminated Cangjie version record in .data',
    ],
    action: `replace only the ${SDK_VERSION_CANONICAL.length}-byte producer-version payload with ${SDK_VERSION_CANONICAL}`,
    basis: 'REPORT-elfdiff.md: all six samples differ in the producer SDK identity emitted by @cj.sdk.version; the value is provenance, not program state',
  },
];

function usage(exitCode = 0) {
  const output = `usage: npx --yes zx@8 scripts/raw_elf_gate.mjs [options]

Required:
  --candidate PATH       freshly built selfhost cjc
  --official PATH        official reference cjc
  --corpus DIR           directory containing the six .cj samples
  --evidence-dir DIR     durable result/artifact directory
  --scratch DIR          disposable same-path compilation directory
  --cpus LIST            required inherited CPU affinity (for example 96-119)

Optional:
  --rounds N             same-window repetitions (default: 2)
  --samples CSV          sample stems (default: the elfdiff six)
  --llvm-dis PATH        llvm-dis path (default: $CANGJIE_HOME/third_party/llvm/bin/llvm-dis)
  --positive-control     run the global-order B-class injection arm (default)
  --no-positive-control  omit the injection arm
  --describe-normalization  print the exact Class-A allowlist and exit
  --help                  show this help

The normal gate exits 0 only when all four layers pass for every sample, all
rounds agree byte-for-byte at the normalized layer level, and the optional
positive-control arm is detected. Unknown differences fail closed.`;
  (exitCode === 0 ? console.log : console.error)(output);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const opts = {
    rounds: 2,
    samples: [...DEFAULT_SAMPLES],
    positiveControl: true,
    describeNormalization: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help') usage(0);
    if (arg === '--positive-control') {
      opts.positiveControl = true;
      continue;
    }
    if (arg === '--no-positive-control') {
      opts.positiveControl = false;
      continue;
    }
    if (arg === '--describe-normalization') {
      opts.describeNormalization = true;
      continue;
    }
    const keyMap = new Map([
      ['--candidate', 'candidate'],
      ['--official', 'official'],
      ['--corpus', 'corpus'],
      ['--evidence-dir', 'evidenceDir'],
      ['--scratch', 'scratch'],
      ['--cpus', 'cpus'],
      ['--rounds', 'rounds'],
      ['--samples', 'samples'],
      ['--llvm-dis', 'llvmDis'],
    ]);
    const key = keyMap.get(arg);
    if (!key || i + 1 >= argv.length) usage(2);
    const value = argv[i + 1];
    i += 1;
    if (key === 'rounds') opts.rounds = Number.parseInt(value, 10);
    else if (key === 'samples') opts.samples = value.split(',').filter(Boolean);
    else opts[key] = value;
  }
  return opts;
}

function runtimeArgs() {
  const zxArgv = globalThis.argv;
  if (!zxArgv || !Array.isArray(zxArgv._)) return process.argv.slice(2);
  const tokens = [...zxArgv._.map(String)];
  for (const [key, rawValue] of Object.entries(zxArgv)) {
    if (key === '_') continue;
    const values = Array.isArray(rawValue) ? rawValue : [rawValue];
    for (const value of values) {
      if (value === false) tokens.push(`--no-${key}`);
      else if (value === true) tokens.push(`--${key}`);
      else tokens.push(`--${key}`, String(value));
    }
  }
  return tokens;
}

function sha256Buffer(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function sha256File(file) {
  return sha256Buffer(readFileSync(file));
}

function ensureFile(file, description) {
  if (!existsSync(file) || !statSync(file).isFile()) {
    throw new Error(`${description} is not a file: ${file}`);
  }
}

function ensureDir(dir, description) {
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    throw new Error(`${description} is not a directory: ${dir}`);
  }
}

function parseCpuList(spec) {
  const cpus = new Set();
  for (const part of spec.split(',')) {
    const match = part.match(/^(\d+)(?:-(\d+))?$/);
    if (!match) throw new Error(`invalid CPU list component: ${part}`);
    const first = Number.parseInt(match[1], 10);
    const last = Number.parseInt(match[2] ?? match[1], 10);
    if (last < first) throw new Error(`invalid descending CPU range: ${part}`);
    for (let cpu = first; cpu <= last; cpu += 1) cpus.add(cpu);
  }
  return [...cpus].sort((a, b) => a - b);
}

function sameNumbers(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function verifyAffinity(requested) {
  const status = readFileSync('/proc/self/status', 'utf8');
  const match = status.match(/^Cpus_allowed_list:\s*(.+)$/m);
  if (!match) throw new Error('cannot read Cpus_allowed_list from /proc/self/status');
  const actual = match[1].trim();
  if (!sameNumbers(parseCpuList(requested), parseCpuList(actual))) {
    throw new Error(`CPU affinity mismatch: requested=${requested} actual=${actual}; run the entire gate under taskset`);
  }
  return actual;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    timeout: options.timeout ?? 10 * 60 * 1000,
  });
  if (options.stdoutFile) writeFileSync(options.stdoutFile, result.stdout ?? '');
  if (options.stderrFile) writeFileSync(options.stderrFile, result.stderr ?? '');
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const tail = `${result.stderr ?? ''}\n${result.stdout ?? ''}`.trim().split('\n').slice(-12).join('\n');
    throw new Error(`${command} exited ${result.status}${tail ? `:\n${tail}` : ''}`);
  }
  return result.stdout ?? '';
}

function commandIdentity(command) {
  const file = realpathSync(command);
  return { path: file, size: statSync(file).size, sha256: sha256File(file) };
}

function outsideQuotedTransform(input, transform) {
  let output = '';
  let plain = '';
  let quoted = false;
  let escaped = false;
  const flush = () => {
    output += transform(plain);
    plain = '';
  };
  for (const char of input) {
    if (quoted) {
      output += char;
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') quoted = false;
    } else if (char === '"') {
      flush();
      output += char;
      quoted = true;
    } else {
      plain += char;
    }
  }
  flush();
  return output;
}

function normalizeSdkIr(text, label) {
  const observations = [];
  const lines = text.split('\n').map((line) => {
    if (!line.startsWith('@cj.sdk.version =')) return line;
    let matches = 0;
    const normalized = line.replace(SDK_VERSION_RE, (value) => {
      matches += 1;
      observations.push({ label, schema: '@cj.sdk.version', value });
      return SDK_VERSION_CANONICAL;
    });
    if (matches !== 1) {
      throw new Error(`${label}: @cj.sdk.version must contain exactly one schema-valid version, found ${matches}`);
    }
    return normalized;
  });
  if (observations.length !== 1) {
    throw new Error(`${label}: expected exactly one @cj.sdk.version global, found ${observations.length}`);
  }
  return { text: lines.join('\n'), observations };
}

function parseLlSupport(text) {
  const attributes = new Map();
  const metadata = new Map();
  for (const line of text.split('\n')) {
    let match = line.match(/^attributes #(\d+) = (.*)$/);
    if (match) {
      attributes.set(match[1], match[2]);
      continue;
    }
    match = line.match(/^!(\d+) = (.*)$/);
    if (match) metadata.set(match[1], match[2]);
  }
  return { attributes, metadata };
}

function referencedMetadata(text) {
  const refs = [];
  outsideQuotedTransform(text, (plain) => plain.replace(/!(\d+)/g, (_whole, id) => {
    refs.push(id);
    return _whole;
  }));
  return refs;
}

function canonicalizeMetadata(statement, metadata, label) {
  const localIds = new Map();
  const order = [];
  const visit = (id) => {
    if (localIds.has(id)) return;
    if (!metadata.has(id)) throw new Error(`${label}: missing metadata definition !${id}`);
    localIds.set(id, localIds.size);
    order.push(id);
    for (const child of referencedMetadata(metadata.get(id))) visit(child);
  };
  for (const id of referencedMetadata(statement)) visit(id);
  const replace = (text) => outsideQuotedTransform(text, (plain) => plain.replace(/!(\d+)/g, (_whole, id) => `!m${localIds.get(id)}`));
  const root = replace(statement);
  if (order.length === 0) return root;
  const definitions = order.map((id) => `!m${localIds.get(id)}=${replace(metadata.get(id))}`);
  return `${root}\n; metadata-closure ${definitions.join(' ; ')}`;
}

function expandAttributes(statement, attributes, label) {
  return outsideQuotedTransform(statement, (plain) => plain.replace(/#(\d+)/g, (_whole, id) => {
    if (!attributes.has(id)) throw new Error(`${label}: missing attribute group #${id}`);
    return `#attrs${attributes.get(id)}`;
  }));
}

function entityName(line) {
  const match = line.match(/^(?:define|declare)\s+.*?@("[^"]+"|[^ (]+)|^([@%$!][^ =]+)/);
  return match?.[1] ?? match?.[2] ?? line.slice(0, 80);
}

function isExternalGlobal(line) {
  return /^@[^=]+ =\s+(?:external|extern_weak)\b/.test(line);
}

function entity(kind, line, text, orderSensitive) {
  return {
    kind,
    name: entityName(line),
    orderSensitive,
    text: `${kind}|${text}`,
  };
}

function semanticStatement(statement, support, label) {
  return canonicalizeMetadata(expandAttributes(statement, support.attributes, label), support.metadata, label);
}

function extractPreOptGlobals(rawText, label) {
  const normalized = normalizeSdkIr(rawText, label);
  const support = parseLlSupport(normalized.text);
  const entities = [];
  for (const line of normalized.text.split('\n')) {
    let kind;
    if (/^@[^=]+ = /.test(line)) kind = /\b(alias|ifunc)\b/.test(line) ? 'alias' : 'global';
    else if (/^%[^=]+ = type\b/.test(line)) kind = 'type';
    else if (/^\$[^=]+ = comdat\b/.test(line)) kind = 'comdat';
    else if (/^![A-Za-z_][A-Za-z0-9_.]* = /.test(line)) kind = 'named-metadata';
    else if (/^(target datalayout|target triple|module asm) = /.test(line)) kind = 'module-property';
    else continue;
    if (kind === 'global' && isExternalGlobal(line)) kind = 'global-declaration';
    const orderSensitive = ['global', 'alias', 'comdat'].includes(kind);
    entities.push(entity(
      kind,
      line,
      semanticStatement(line, support, `${label}:${entityName(line)}`),
      orderSensitive,
    ));
  }
  if (!entities.some((entity) => entity.kind === 'global')) {
    throw new Error(`${label}: no pre-opt globals captured`);
  }
  return { entities, observations: normalized.observations };
}

function localTokenTransform(functionText, typeNames) {
  const localIds = new Map();
  const getLocal = (token) => {
    if (!localIds.has(token)) localIds.set(token, `v${localIds.size}`);
    return localIds.get(token);
  };
  const lines = [];
  for (const originalLine of functionText.split('\n')) {
    let line = originalLine;
    const label = line.match(/^([A-Za-z0-9_.$-]+):/);
    if (label) line = `${getLocal(`%${label[1]}`)}:${line.slice(label[0].length)}`;
    line = outsideQuotedTransform(line, (plain) => plain.replace(/%(?:[A-Za-z0-9_.$-]+|"[^"]+")/g, (token) => {
      if (typeNames.has(token)) return token;
      return `%${getLocal(token)}`;
    }));
    lines.push(line);
  }
  return lines.join('\n');
}

function extractPostOpt(rawText, label) {
  const normalized = normalizeSdkIr(rawText, label);
  const support = parseLlSupport(normalized.text);
  const lines = normalized.text.split('\n');
  const typeNames = new Set(lines.flatMap((line) => {
    const match = line.match(/^(%(?:[^ =]+|"[^"]+")) = type\b/);
    return match ? [match[1]] : [];
  }));
  const entities = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line.startsWith('define ')) {
      const body = [line];
      while (index + 1 < lines.length) {
        index += 1;
        body.push(lines[index]);
        if (lines[index] === '}') break;
      }
      if (body.at(-1) !== '}') throw new Error(`${label}: unterminated function ${entityName(line)}`);
      const localCanonical = localTokenTransform(body.join('\n'), typeNames);
      entities.push(entity(
        'function-definition',
        line,
        semanticStatement(localCanonical, support, `${label}:${entityName(line)}`),
        true,
      ));
      continue;
    }
    let kind;
    if (line.startsWith('declare ')) kind = 'function-declaration';
    else if (/^@[^=]+ = /.test(line)) kind = /\b(alias|ifunc)\b/.test(line) ? 'alias' : 'global';
    else if (/^%[^=]+ = type\b/.test(line)) kind = 'type';
    else if (/^\$[^=]+ = comdat\b/.test(line)) kind = 'comdat';
    else if (/^![A-Za-z_][A-Za-z0-9_.]* = /.test(line)) kind = 'named-metadata';
    else if (/^(source_filename|target datalayout|target triple|module asm) = /.test(line)) kind = 'module-property';
    else continue;
    if (kind === 'global' && isExternalGlobal(line)) kind = 'global-declaration';
    const orderSensitive = ['global', 'alias', 'comdat'].includes(kind);
    entities.push(entity(
      kind,
      line,
      semanticStatement(line, support, `${label}:${entityName(line)}`),
      orderSensitive,
    ));
  }
  if (!entities.some((entity) => entity.kind === 'function-definition')) {
    throw new Error(`${label}: no post-opt function definitions captured`);
  }
  return { entities, observations: normalized.observations };
}

function comparisonEntities(entities) {
  const emitted = entities.filter((item) => item.orderSensitive);
  const structural = entities.filter((item) => !item.orderSensitive).sort((left, right) => (
    left.kind.localeCompare(right.kind)
      || left.name.localeCompare(right.name)
      || left.text.localeCompare(right.text)
  ));
  return [
    entity('comparison-boundary', 'order-sensitive', 'emitted-definition-order', true),
    ...emitted,
    entity('comparison-boundary', 'name-structured', 'non-emitted-entities-by-name', false),
    ...structural,
  ];
}

function serializeEntities(entities) {
  return Buffer.from(comparisonEntities(entities).map((item) => item.text).join('\n\n'), 'utf8');
}

function firstEntityDifference(left, right) {
  const count = Math.max(left.length, right.length);
  for (let index = 0; index < count; index += 1) {
    if (left[index]?.text === right[index]?.text) continue;
    const compact = (entity) => entity ? {
      kind: entity.kind,
      name: entity.name,
      sha256: sha256Buffer(Buffer.from(entity.text)),
      preview: entity.text.slice(0, 1000),
    } : null;
    return { index, official: compact(left[index]), candidate: compact(right[index]) };
  }
  return null;
}

function readElfSections(buffer, label) {
  if (buffer.length < 64 || buffer.subarray(0, 4).toString('hex') !== '7f454c46') {
    throw new Error(`${label}: not an ELF file`);
  }
  if (buffer[4] !== 2 || buffer[5] !== 1) {
    throw new Error(`${label}: only ELF64 little-endian artifacts are supported`);
  }
  const sectionOffset = Number(buffer.readBigUInt64LE(0x28));
  const sectionEntrySize = buffer.readUInt16LE(0x3a);
  const sectionCount = buffer.readUInt16LE(0x3c);
  const nameTableIndex = buffer.readUInt16LE(0x3e);
  if (sectionEntrySize < 64 || nameTableIndex >= sectionCount) {
    throw new Error(`${label}: invalid ELF section table`);
  }
  const headerAt = (index) => sectionOffset + index * sectionEntrySize;
  const nameHeader = headerAt(nameTableIndex);
  const namesOffset = Number(buffer.readBigUInt64LE(nameHeader + 0x18));
  const namesSize = Number(buffer.readBigUInt64LE(nameHeader + 0x20));
  const names = buffer.subarray(namesOffset, namesOffset + namesSize);
  const readName = (offset) => {
    let end = offset;
    while (end < names.length && names[end] !== 0) end += 1;
    return names.subarray(offset, end).toString('utf8');
  };
  const sections = [];
  for (let index = 0; index < sectionCount; index += 1) {
    const header = headerAt(index);
    if (header + 64 > buffer.length) throw new Error(`${label}: truncated ELF section header ${index}`);
    sections.push({
      index,
      name: readName(buffer.readUInt32LE(header)),
      type: buffer.readUInt32LE(header + 4),
      flags: buffer.readBigUInt64LE(header + 8).toString(),
      offset: Number(buffer.readBigUInt64LE(header + 0x18)),
      size: Number(buffer.readBigUInt64LE(header + 0x20)),
      align: buffer.readBigUInt64LE(header + 0x30).toString(),
    });
  }
  return sections;
}

function sdkRecordsInData(buffer, label) {
  const records = [];
  const dataSections = readElfSections(buffer, label).filter((section) => section.name === '.data');
  if (dataSections.length !== 1) throw new Error(`${label}: expected exactly one .data section, found ${dataSections.length}`);
  for (const section of dataSections) {
    const content = buffer.subarray(section.offset, section.offset + section.size).toString('latin1');
    const pattern = /1\.2\.0-alpha\.\d{14}\x00/g;
    for (const match of content.matchAll(pattern)) {
      records.push({
        section: section.name,
        sectionOffset: match.index,
        fileOffset: section.offset + match.index,
        value: match[0].slice(0, -1),
        length: match[0].length - 1,
      });
    }
  }
  return records;
}

function normalizeElfPair(officialBuffer, candidateBuffer, label) {
  const official = Buffer.from(officialBuffer);
  const candidate = Buffer.from(candidateBuffer);
  const officialRecords = sdkRecordsInData(official, `${label}:official`);
  const candidateRecords = sdkRecordsInData(candidate, `${label}:candidate`);
  const key = (record) => `${record.section}:${record.sectionOffset}:${record.length}`;
  const officialMap = new Map(officialRecords.map((record) => [key(record), record]));
  const candidateMap = new Map(candidateRecords.map((record) => [key(record), record]));
  const officialKeys = [...officialMap.keys()].sort();
  const candidateKeys = [...candidateMap.keys()].sort();
  const positionsMatch = JSON.stringify(officialKeys) === JSON.stringify(candidateKeys);
  const observations = [];
  if (positionsMatch) {
    const replacement = Buffer.from(SDK_VERSION_CANONICAL, 'ascii');
    for (const recordKey of officialKeys) {
      const left = officialMap.get(recordKey);
      const right = candidateMap.get(recordKey);
      if (left.length !== replacement.length || right.length !== replacement.length) {
        throw new Error(`${label}: SDK schema length changed at ${recordKey}`);
      }
      replacement.copy(official, left.fileOffset);
      replacement.copy(candidate, right.fileOffset);
      observations.push({
        label,
        schema: `${left.section}+${left.sectionOffset}`,
        official: left.value,
        candidate: right.value,
      });
    }
  }
  return {
    official,
    candidate,
    positionsMatch,
    observations,
    unmatchedSchema: positionsMatch ? null : { official: officialKeys, candidate: candidateKeys },
  };
}

function binaryDifference(left, right) {
  const overlap = Math.min(left.length, right.length);
  let first = -1;
  let count = Math.abs(left.length - right.length);
  for (let index = 0; index < overlap; index += 1) {
    if (left[index] !== right[index]) {
      if (first === -1) first = index;
      count += 1;
    }
  }
  if (first === -1 && left.length !== right.length) first = overlap;
  return { firstOffset: first, differingBytes: count, officialSize: left.length, candidateSize: right.length };
}

function compareEntityLayer(official, candidate) {
  const officialBytes = serializeEntities(official.entities);
  const candidateBytes = serializeEntities(candidate.entities);
  const pass = officialBytes.equals(candidateBytes);
  return {
    pass,
    officialSha256: sha256Buffer(officialBytes),
    candidateSha256: sha256Buffer(candidateBytes),
    officialEntityCount: official.entities.length,
    candidateEntityCount: candidate.entities.length,
    firstDifference: pass ? null : firstEntityDifference(
      comparisonEntities(official.entities),
      comparisonEntities(candidate.entities),
    ),
    normalization: [...official.observations, ...candidate.observations],
  };
}

function compareBinaryLayer(officialFile, candidateFile, label) {
  const pair = normalizeElfPair(readFileSync(officialFile), readFileSync(candidateFile), label);
  const pass = pair.positionsMatch && pair.official.equals(pair.candidate);
  return {
    pass,
    officialSha256: sha256Buffer(pair.official),
    candidateSha256: sha256Buffer(pair.candidate),
    rawOfficialSha256: sha256File(officialFile),
    rawCandidateSha256: sha256File(candidateFile),
    difference: pass ? null : binaryDifference(pair.official, pair.candidate),
    normalization: pair.observations,
    unmatchedSchema: pair.unmatchedSchema,
  };
}

function findArtifacts(slot, sample, output) {
  const expected = {
    preOpt: path.join(slot, `${sample}.bc`),
    postOpt: path.join(slot, `${sample}.opt.bc`),
    object: path.join(slot, `${sample}.o`),
    elf: output,
  };
  for (const [kind, file] of Object.entries(expected)) ensureFile(file, `${sample} ${kind} artifact`);
  const preOptBitcodes = readdirSync(slot).filter((name) => name.endsWith('.bc') && !name.endsWith('.opt.bc'));
  const postOptBitcodes = readdirSync(slot).filter((name) => name.endsWith('.opt.bc'));
  const objects = readdirSync(slot).filter((name) => name.endsWith('.o'));
  if (preOptBitcodes.length !== 1 || postOptBitcodes.length !== 1 || objects.length !== 1) {
    throw new Error(`${sample}: expected one pre-opt BC, post-opt BC, and object; found ${preOptBitcodes.length}/${postOptBitcodes.length}/${objects.length}`);
  }
  return expected;
}

function compileArm({ compiler, arm, sample, source, scratch, evidence, llvmDis, env }) {
  const slot = path.join(scratch, 'same-path');
  rmSync(slot, { recursive: true, force: true });
  mkdirSync(slot, { recursive: true });
  const output = path.join(slot, 'a.out');
  const armDir = path.join(evidence, arm);
  mkdirSync(armDir, { recursive: true });
  const stdoutFile = path.join(armDir, 'compile.stdout');
  const stderrFile = path.join(armDir, 'compile.stderr');
  const argv = [
    source,
    '-O2',
    '--jobs', '1',
    '--apc=1',
    '-V',
    '--save-temps', slot,
    '-o', output,
  ];
  run(compiler, argv, { cwd: scratch, env, stdoutFile, stderrFile });
  const artifacts = findArtifacts(slot, sample, output);
  const retained = {};
  for (const [kind, file] of Object.entries(artifacts)) {
    const suffix = kind === 'elf' ? '.elf' : path.extname(file);
    const destination = path.join(armDir, `${sample}${kind === 'postOpt' ? '.opt.bc' : suffix}`);
    copyFileSync(file, destination);
    retained[kind] = destination;
  }
  retained.preLl = path.join(armDir, `${sample}.bc.ll`);
  retained.postLl = path.join(armDir, `${sample}.opt.bc.ll`);
  run(llvmDis, [retained.preOpt, '-o', retained.preLl], { cwd: scratch, env });
  run(llvmDis, [retained.postOpt, '-o', retained.postLl], { cwd: scratch, env });
  writeFileSync(path.join(armDir, 'argv.json'), `${JSON.stringify(argv, null, 2)}\n`);
  return {
    ...retained,
    identities: Object.fromEntries(Object.entries(retained)
      .filter(([, file]) => existsSync(file))
      .map(([kind, file]) => [kind, { size: statSync(file).size, sha256: sha256File(file) }])),
  };
}

function compareSample(sample, official, candidate) {
  const preOfficial = extractPreOptGlobals(readFileSync(official.preLl, 'utf8'), `${sample}:pre-opt:official`);
  const preCandidate = extractPreOptGlobals(readFileSync(candidate.preLl, 'utf8'), `${sample}:pre-opt:candidate`);
  const postOfficial = extractPostOpt(readFileSync(official.postLl, 'utf8'), `${sample}:post-opt:official`);
  const postCandidate = extractPostOpt(readFileSync(candidate.postLl, 'utf8'), `${sample}:post-opt:candidate`);
  return {
    sample,
    layers: {
      'pre-opt-globals': compareEntityLayer(preOfficial, preCandidate),
      'post-opt': compareEntityLayer(postOfficial, postCandidate),
      object: compareBinaryLayer(official.object, candidate.object, `${sample}:object`),
      'linked-elf': compareBinaryLayer(official.elf, candidate.elf, `${sample}:linked-elf`),
    },
    artifacts: { official: official.identities, candidate: candidate.identities },
  };
}

function resultSignature(result) {
  return Object.fromEntries(result.samples.map((sample) => [sample.sample, Object.fromEntries(
    LAYERS.map((layer) => [layer, {
      pass: sample.layers[layer].pass,
      officialSha256: sample.layers[layer].officialSha256,
      candidateSha256: sample.layers[layer].candidateSha256,
    }]),
  )]));
}

function positiveControl(candidateArtifacts, sample) {
  const pre = extractPreOptGlobals(readFileSync(candidateArtifacts.preLl, 'utf8'), `${sample}:positive-control`);
  const selfBaseline = compareEntityLayer(pre, pre);
  const orderMutation = pre.entities.map((item) => ({ ...item }));
  const globalIndices = orderMutation.flatMap((item, index) => item.kind === 'global' ? [index] : []);
  if (globalIndices.length < 2) throw new Error(`${sample}: positive control needs at least two globals`);
  const first = globalIndices[0];
  const second = globalIndices[1];
  const orderNames = [orderMutation[first].name, orderMutation[second].name];
  [orderMutation[first], orderMutation[second]] = [orderMutation[second], orderMutation[first]];
  const orderInjected = compareEntityLayer(pre, { ...pre, entities: orderMutation });

  const typeMutation = pre.entities.map((item) => ({ ...item }));
  const typeIndex = typeMutation.findIndex((item) => item.kind === 'type' && item.text.includes(' = type {'));
  if (typeIndex < 0) throw new Error(`${sample}: positive control needs a structured named type`);
  const typeName = typeMutation[typeIndex].name;
  typeMutation[typeIndex].text = typeMutation[typeIndex].text.replace(' = type {', ' = type { i8,');
  const typeInjected = compareEntityLayer(pre, { ...pre, entities: typeMutation });

  const common = {
    sample,
    class: 'B',
    baselinePass: selfBaseline.pass,
    redLayer: 'pre-opt-globals',
    restored: true,
    sourceOrArtifactModified: false,
  };
  return [
    {
      ...common,
      name: 'global-order',
      injection: 'swap-pre-opt-global-definition-order',
      targets: orderNames,
      detected: !orderInjected.pass,
      firstDifference: orderInjected.firstDifference,
    },
    {
      ...common,
      name: 'type-structure',
      injection: 'prepend-i8-field-to-named-type',
      targets: [typeName],
      detected: !typeInjected.pass,
      firstDifference: typeInjected.firstDifference,
    },
  ];
}

function printRound(round) {
  for (const sample of round.samples) {
    const details = LAYERS.map((layer) => `${layer}=${sample.layers[layer].pass ? 'PASS' : 'FAIL'}`).join(' ');
    console.log(`RAWGATE_RESULT round=${round.round} sample=${sample.sample} ${details}`);
    for (const layer of LAYERS) {
      const result = sample.layers[layer];
      if (!result.pass) {
        const first = result.firstDifference
          ? `${result.firstDifference.official?.kind ?? 'none'}:${result.firstDifference.official?.name ?? 'none'}->${result.firstDifference.candidate?.kind ?? 'none'}:${result.firstDifference.candidate?.name ?? 'none'}`
          : `offset=${result.difference?.firstOffset ?? 'schema'}`;
        console.log(`RAWGATE_DIFF round=${round.round} sample=${sample.sample} layer=${layer} first=${first}`);
      }
    }
  }
}

function main() {
  const opts = parseArgs(runtimeArgs());
  if (opts.describeNormalization) {
    console.log(JSON.stringify(NORMALIZATION_RULES, null, 2));
    return 0;
  }
  const required = ['candidate', 'official', 'corpus', 'evidenceDir', 'scratch', 'cpus'];
  for (const key of required) if (!opts[key]) usage(2);
  if (!Number.isInteger(opts.rounds) || opts.rounds < 1) throw new Error(`invalid --rounds: ${opts.rounds}`);
  if (opts.samples.length === 0) throw new Error('--samples resolved to an empty set');

  const candidate = realpathSync(opts.candidate);
  const official = realpathSync(opts.official);
  const corpus = realpathSync(opts.corpus);
  const evidenceDir = path.resolve(opts.evidenceDir);
  const scratch = path.resolve(opts.scratch);
  const cangjieHome = process.env.CANGJIE_HOME;
  if (!cangjieHome && !opts.llvmDis) throw new Error('CANGJIE_HOME or --llvm-dis is required');
  const llvmDis = realpathSync(opts.llvmDis ?? path.join(cangjieHome, 'third_party/llvm/bin/llvm-dis'));
  ensureFile(candidate, 'candidate compiler');
  ensureFile(official, 'official compiler');
  ensureFile(llvmDis, 'llvm-dis');
  ensureDir(corpus, 'corpus');
  const affinity = verifyAffinity(opts.cpus);
  if (evidenceDir === scratch || evidenceDir.startsWith(`${scratch}${path.sep}`)) {
    throw new Error('--evidence-dir must not be inside the disposable --scratch directory');
  }
  rmSync(evidenceDir, { recursive: true, force: true });
  rmSync(scratch, { recursive: true, force: true });
  mkdirSync(evidenceDir, { recursive: true });
  mkdirSync(scratch, { recursive: true });

  const env = { ...process.env };
  env.cjHeapSize = '24GB';
  if (cangjieHome) {
    const libs = [
      path.join(cangjieHome, 'third_party/llvm/lib'),
      path.join(cangjieHome, 'runtime/lib/linux_x86_64_cjnative'),
      path.join(cangjieHome, 'tools/lib'),
      env.LD_LIBRARY_PATH ?? '',
    ].filter(Boolean);
    env.LD_LIBRARY_PATH = libs.join(':');
  }
  const sources = new Map(opts.samples.map((sample) => {
    const source = path.join(corpus, `${sample}.cj`);
    ensureFile(source, `${sample} source`);
    return [sample, source];
  }));
  const manifest = {
    schema: 1,
    startedAt: new Date().toISOString(),
    flagMode: 'off (--cjcj-optimization absent)',
    affinity,
    rounds: opts.rounds,
    samples: opts.samples,
    samePath: path.join(scratch, 'same-path'),
    compileArgs: ['-O2', '--jobs', '1', '--apc=1', '-V', '--save-temps', '<same-path>', '-o', '<same-path>/a.out'],
    tools: {
      candidate: commandIdentity(candidate),
      official: commandIdentity(official),
      llvmDis: commandIdentity(llvmDis),
    },
    sources: Object.fromEntries([...sources].map(([sample, source]) => [sample, {
      path: source,
      size: statSync(source).size,
      sha256: sha256File(source),
    }])),
    normalizationRules: NORMALIZATION_RULES,
  };
  writeFileSync(path.join(evidenceDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);

  const rounds = [];
  let controlArtifacts = null;
  for (let roundNumber = 1; roundNumber <= opts.rounds; roundNumber += 1) {
    const roundDir = path.join(evidenceDir, `round-${roundNumber}`);
    mkdirSync(roundDir, { recursive: true });
    const samples = [];
    for (const [sample, source] of sources) {
      const sampleDir = path.join(roundDir, sample);
      const officialArtifacts = compileArm({
        compiler: official,
        arm: 'official',
        sample,
        source,
        scratch,
        evidence: sampleDir,
        llvmDis,
        env,
      });
      const candidateArtifacts = compileArm({
        compiler: candidate,
        arm: 'candidate',
        sample,
        source,
        scratch,
        evidence: sampleDir,
        llvmDis,
        env,
      });
      if (!controlArtifacts) controlArtifacts = candidateArtifacts;
      samples.push(compareSample(sample, officialArtifacts, candidateArtifacts));
      rmSync(path.join(scratch, 'same-path'), { recursive: true, force: true });
    }
    const round = { round: roundNumber, samples };
    rounds.push(round);
    writeFileSync(path.join(roundDir, 'results.json'), `${JSON.stringify(round, null, 2)}\n`);
    printRound(round);
  }

  const signatures = rounds.map(resultSignature);
  const reproducible = signatures.slice(1).every((signature) => JSON.stringify(signature) === JSON.stringify(signatures[0]));
  const positive = opts.positiveControl ? positiveControl(controlArtifacts, opts.samples[0]) : [];
  for (const control of positive) {
    console.log(`RAWGATE_POSITIVE_CONTROL name=${control.name} baseline=${control.baselinePass ? 'PASS' : 'FAIL'} injection=${control.injection} class=${control.class} detected=${control.detected ? 'YES' : 'NO'} red_layer=${control.detected ? control.redLayer : 'none'} restored=${control.restored ? 'YES' : 'NO'}`);
  }
  console.log(`RAWGATE_REPRODUCIBLE rounds=${opts.rounds} result=${reproducible ? 'PASS' : 'FAIL'}`);
  const allParity = rounds.every((round) => round.samples.every((sample) => LAYERS.every((layer) => sample.layers[layer].pass)));
  const controlPass = positive.every((control) => control.baselinePass && control.detected && control.restored);
  const summary = {
    schema: 1,
    completedAt: new Date().toISOString(),
    allParity,
    reproducible,
    positiveControl: positive,
    rounds: rounds.map((round) => ({ round: round.round, signature: resultSignature(round) })),
    exitPass: allParity && reproducible && controlPass,
  };
  writeFileSync(path.join(evidenceDir, 'summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
  rmSync(scratch, { recursive: true, force: true });
  console.log(`RAW_ELF_GATE=${summary.exitPass ? 'PASS' : 'FAIL'} parity=${allParity ? 'PASS' : 'FAIL'} reproducible=${reproducible ? 'PASS' : 'FAIL'} positive_control=${controlPass ? 'PASS' : 'FAIL'}`);
  return summary.exitPass ? 0 : 1;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(`RAW_ELF_GATE=ERROR ${error?.stack ?? error}`);
  process.exitCode = 2;
}
