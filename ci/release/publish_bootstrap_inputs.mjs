#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {api, asset, digest, verify, validatePin, acquire} from './bootstrap_store.mjs';

// Input is a reviewed/generated list {path, sha256, mode}; never infer payloads from a directory scan.
const [root, listPath, output] = process.argv.slice(2);
const files = JSON.parse(fs.readFileSync(listPath, 'utf8'));
const pin = {version: 1, repository: process.env.GITHUB_REPOSITORY,
  run: Number(process.env.GITHUB_RUN_ID), attempt: Number(process.env.GITHUB_RUN_ATTEMPT),
  commit: process.env.GITHUB_SHA, artifact: Number(process.env.BOOTSTRAP_ARTIFACT_ID),
  files: files.map(file => ({path: file.path, mode: file.mode, artifact_sha256: file.sha256, release_sha256: file.sha256, asset: 1}))};
validatePin(pin);
for (const file of files) {
  const source = path.join(root, file.path);
  if (!fs.lstatSync(source).isFile()) throw new Error(`bootstrap publish requires regular file: ${file.path}`);
  verify(fs.readFileSync(source), file.sha256, file.path);
}
const metadata = await (await api(`/repos/${pin.repository}/actions/artifacts/${pin.artifact}`)).json();
const run = await (await api(`/repos/${pin.repository}/actions/runs/${pin.run}`)).json();
if (metadata.workflow_run?.id !== pin.run || metadata.workflow_run?.head_sha !== pin.commit
    || run.run_attempt !== pin.attempt || run.head_sha !== pin.commit) throw new Error('bootstrap publish provenance mismatch');
// Read back the fixed artifact too: both locations must contain identical bytes.
const checked = await acquire(pin, path.dirname(output), {mode: 'artifact', reason: 'publisher fixed-artifact readback'});
fs.rmSync(path.dirname(checked), {recursive: true, force: true});
const tag = `bootstrap-${pin.run}-${pin.attempt}-${pin.artifact}-prerelease`;
const release = await (await api(`/repos/${pin.repository}/releases`, {method: 'POST',
  body: JSON.stringify({tag_name: tag, target_commitish: pin.commit, name: tag, draft: true, prerelease: true, make_latest: 'false'})})).json();
for (const [index, file] of pin.files.entries()) {
  const bytes = fs.readFileSync(path.join(root, file.path));
  const response = await fetch(`${release.upload_url.split('{')[0]}?name=${encodeURIComponent(`payload-${index}-${path.basename(file.path)}`)}`, {
    method: 'POST', headers: {Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, 'Content-Type': 'application/octet-stream'}, body: bytes});
  if (!response.ok) throw new Error(`bootstrap upload failed: ${response.status} ${file.path}`);
  const uploaded = await response.json();
  file.asset = uploaded.id;
  const downloaded = await asset(pin.repository, file.asset);
  verify(downloaded, file.artifact_sha256, file.path);
  file.release_sha256 = digest(downloaded);
}
validatePin(pin);
await api(`/repos/${pin.repository}/releases/${release.id}`, {method: 'PATCH', body: JSON.stringify({draft: false, prerelease: true, make_latest: 'false'})});
fs.writeFileSync(output, `${JSON.stringify(pin, null, 2)}\n`);
console.log(`BOOTSTRAP_PUBLISHED tag=${tag} files=${pin.files.length} pin=${output}`);
