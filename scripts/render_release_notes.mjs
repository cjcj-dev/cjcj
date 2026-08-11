#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import {
  RELEASE_SIGNATURE_POLICY,
  validateReleaseManifestArtifact,
  validateReleaseManifestSource,
} from '../build/lib/release-manifest.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  validateGateApparatusManifestSection,
} from '../build/lib/release-gate-apparatus.mjs';

const REQUIRED_COMPONENTS = [
  'base-sdk', GATE_APPARATUS_COMPONENT, 'cjcj', 'runtime', 'llvm-llc', 'llvm-opt', 'std', 'cjpm', 'python',
];

function option(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`--${name} is required`);
  return process.argv[index + 1];
}

function cell(value) {
  return String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
}

const version = option('version');
const dist = path.resolve(option('dist'));
const output = path.resolve(option('output'));
const escapedVersion = version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const pattern = new RegExp(`^cjcj-${escapedVersion}-(.+)\\.RELEASE-MANIFEST\\.jsonl$`);
const manifests = (await fs.readdir(dist)).map(name => ({name, match: name.match(pattern)}))
  .filter(entry => entry.match).sort((left, right) => left.name.localeCompare(right.name));
if (manifests.length === 0) throw new Error(`no release manifests under ${dist}`);

const loadedManifests = await Promise.all(manifests.map(async ({name, match}) => {
  const text = await fs.readFile(path.join(dist, name), 'utf8');
  const rows = text.split(/\r?\n/).filter(Boolean).map((line, index) => {
    try { return JSON.parse(line); } catch (error) {
      throw new Error(`${name}:${index + 1}: invalid JSON: ${error.message}`);
    }
  });
  if (rows.length === 0) throw new Error(`${name}: empty manifest`);
  // The core components are required exactly; the Cangjie-written tools are
  // discovered from the package, so their number grows as hle, cjcov and
  // cjtrace-recover get wired. An exact equality over the whole set would have
  // to be edited every time one lands — and an assertion that must be edited to
  // stay true is the same shape as the hard-coded artifact name and the
  // hard-coded counts this repository has already been bitten by. Missing a core
  // component and inventing an unknown one both still fail.
  const components = rows.map(row => row.component).sort();
  const requiredComponents = [...REQUIRED_COMPONENTS].sort();
  const missing = requiredComponents.filter(component => !components.includes(component));
  const unexpected = components.filter(component =>
    !requiredComponents.includes(component) && !/^tool-[A-Za-z0-9._-]+$/.test(component));
  if (missing.length || unexpected.length) {
    throw new Error(`${name}: manifest components mismatch: expected=${requiredComponents.join(',')} ` +
      `actual=${components.join(',')}` +
      `${missing.length ? ` missing=${missing.join(',')}` : ''}` +
      `${unexpected.length ? ` unexpected=${unexpected.join(',')}` : ''}`);
  }
  const apparatus = rows.find(row => row.component === GATE_APPARATUS_COMPONENT);
  validateGateApparatusManifestSection(apparatus?.acceptance_apparatus, match[1]);
  return {name, match, rows};
}));
const signaturePolicies = new Set(loadedManifests.flatMap(({rows}) =>
  rows.map(row => row.signature_policy)));
if (signaturePolicies.size !== 1 || !signaturePolicies.has(RELEASE_SIGNATURE_POLICY)) {
  throw new Error(`release manifests must have one ${RELEASE_SIGNATURE_POLICY} signature_policy; got ${
    [...signaturePolicies].map(value => JSON.stringify(value)).sort().join(', ') || '<empty>'}`);
}

const lines = [
  `# cjcj v${version}`,
  '',
  'Every SDK archive embeds `RELEASE-MANIFEST.jsonl`; the same manifest is attached beside the archive.',
  'The tables below are rendered from those manifests. `not-applicable` is allowed only with an explicit reason; unresolved provenance is rejected. `no-stamp` records an absent embedded stamp.',
  `Signature policy: \`${RELEASE_SIGNATURE_POLICY}\`.`,
  'SHA_ONLY provides checksums only; this release has no detached signature, GitHub attestation, CycloneDX SBOM, or SPDX SBOM.',
  '',
  '## Component provenance',
];

for (const {name, match, rows} of loadedManifests) {
  lines.push('', `### ${match[1]}`, '',
    '| component | source commit/version | artifact SHA-256 | embedded stamp |',
    '|---|---|---|---|');
  for (const row of rows) {
    validateReleaseManifestSource(row.source, row.component || '<missing-component>');
    validateReleaseManifestArtifact(row.artifact, row.component || '<missing-component>');
    const values = [row.component, row.source?.commit, row.artifact?.sha256, row.embedded_stamp];
    if (row.schema !== 1 || row.signature_policy !== RELEASE_SIGNATURE_POLICY ||
        values.some(value => typeof value !== 'string' || value.length === 0)) {
      throw new Error(`${name}: malformed component row ${JSON.stringify(row)}`);
    }
    lines.push(`| ${values.map(cell).join(' | ')} |`);
  }
}

await fs.writeFile(output, `${lines.join('\n')}\n`);
console.log(`release notes: ${output} (${manifests.length} manifest(s))`);
