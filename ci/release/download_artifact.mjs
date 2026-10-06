import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {downloadPinned} from './download_pinned.mjs';

export function downloadArtifact(repository, artifactId, archive) {
  // Static reviewed inputs use persistent assets; run-selected artifacts retain
  // their ephemeral download path. Missing/corrupt persistent assets never fall back.
  const file = process.env.BOOTSTRAP_ARCHIVES_PIN || new URL('../bootstrap_artifacts_pin.json', import.meta.url);
  const registry = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (repository === 'cjcj-dev/cjcj' && Object.hasOwn(registry.artifacts, artifactId)) {
    return downloadPinned(repository, artifactId, archive);
  }
  const archiveFd = fs.openSync(archive, 'w');
  try {
    const download = spawnSync('gh', ['api', `repos/${repository}/actions/artifacts/${artifactId}/zip`], {
      stdio: ['inherit', archiveFd, 'inherit'],
    });
    if (download.error) throw download.error;
    if (download.status !== 0) throw new Error(`ARTIFACT_DOWNLOAD_FAILED artifact=${artifactId} status=${download.status}`);
  } finally {
    fs.closeSync(archiveFd);
  }
}
