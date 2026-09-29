import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';

const compilerIdentity = fileURLToPath(new URL('../../bootstrap/compiler_identity.py', import.meta.url));
const execute = promisify(execFile);
import {fileSha256} from './final-compiler.mjs';

export async function installStage3Compiler({sdk, product, lineage}) {
  if (!lineage?.compilerSha256) throw new Error('compose stage3 lineage missing compilerSha256');
  if (await fileSha256(product) !== lineage.compilerSha256) {
    throw new Error('compose stage3 producer mismatch');
  }
  await execute('python3', [compilerIdentity, sdk, '--install', product]);
  const installed = path.join(sdk, 'bin', 'cjc');
  if (await fileSha256(installed) !== lineage.compilerSha256) {
    throw new Error('compose stage3 installed compiler mismatch');
  }
  return installed;
}

export async function sealStage3Compiler(sdk, transformation) {
  const recordPath = path.join(sdk, 'compiler-lineage.json');
  const record = JSON.parse(await fs.readFile(recordPath, 'utf8'));
  if (transformation !== 'copy') {
    record.installed_sha256 = await fileSha256(path.join(sdk, 'bin', 'cjcj-stage1'));
    record.transformation = transformation;
    await fs.writeFile(recordPath, JSON.stringify(record, null, 2) + '\n');
  }
  await execute('python3', [compilerIdentity, sdk]);
}
