import fs from 'node:fs';
import {spawnSync} from 'node:child_process';

export function downloadArtifact(repository, artifactId, archive) {
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
