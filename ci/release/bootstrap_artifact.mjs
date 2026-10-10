import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {downloadPinned} from './download_pinned.mjs';

export function bootstrapArtifact(selected, repository, artifactId, work, label) {
  if (selected) return selected;
  if (!/^[1-9][0-9]*$/.test(String(artifactId || ''))) {
    throw new Error(`${label}_ARTIFACT_PIN_MISSING`);
  }
  fs.mkdirSync(work, {recursive: true});
  const scratch = fs.mkdtempSync(path.join(work, `${label.toLowerCase()}-`));
  const archive = path.join(scratch, 'artifact.zip');
  downloadPinned(repository, artifactId, archive);
  const artifact = path.join(scratch, 'artifact');
  const extracted = spawnSync('unzip', ['-q', archive, '-d', artifact], {stdio: 'inherit'});
  if (extracted.error) throw extracted.error;
  if (extracted.status !== 0) throw new Error(`${label}_ARTIFACT_EXTRACT_FAILED`);
  fs.unlinkSync(archive);
  return artifact;
}
