import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {hostIdentity, prepareHostLlvm} from './host_llvm.mjs';
import {downloadArtifact} from './download_artifact.mjs';

const output = process.argv[2];
if (!output) throw new Error('usage: prepare_kkk2_host_llvm.mjs OUTPUT_JSON');
if (!process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT) {
  const pin = hostIdentity();
  const work = process.env.CJCJ_BOOTSTRAP_HOST_LLVM_WORK || process.env.RUNNER_TEMP;
  if (!work) throw new Error('HOST_LLVM_WORK_MISSING');
  fs.mkdirSync(work, {recursive: true});
  const scratch = fs.mkdtempSync(path.join(work, 'host-llvm-artifact-'));
  const archive = path.join(scratch, 'artifact.zip');
  downloadArtifact(pin.repository, pin.artifact_id, archive);
  const artifact = path.join(scratch, 'artifact');
  const extracted = spawnSync('unzip', ['-q', archive, '-d', artifact], {stdio: 'inherit'});
  if (extracted.error) throw extracted.error;
  if (extracted.status !== 0) throw new Error('HOST_LLVM_ARTIFACT_EXTRACT_FAILED');
  fs.unlinkSync(archive);
  process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT = artifact;
}
const hostLlvm = prepareHostLlvm();
fs.writeFileSync(output, JSON.stringify(hostLlvm));
