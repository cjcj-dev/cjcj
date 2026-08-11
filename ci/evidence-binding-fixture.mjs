import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const PRODUCER_HEAD = '1111111111111111111111111111111111111111';

function sha256(contents) {
  return crypto.createHash('sha256').update(contents).digest('hex');
}

async function payloadFiles(root, directory = root) {
  const files = [];
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await payloadFiles(root, file));
    else if (entry.isFile() && entry.name !== 'EVIDENCE_BINDING.json') {
      files.push(path.relative(root, file).split(path.sep).join('/'));
    }
  }
  return files;
}

function checkoutHead(checkout) {
  const result = spawnSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
}

export async function bindEvidence(root, gate, checkout, producerHead = PRODUCER_HEAD) {
  const meta = path.join(root, 'meta.txt');
  let metaText = '';
  try {
    metaText = await fs.readFile(meta, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (!metaText.split(/\r?\n/).includes(`HEAD=${producerHead}`)) {
    await fs.writeFile(meta, `${metaText}${metaText && !metaText.endsWith('\n') ? '\n' : ''}HEAD=${producerHead}\n`);
  }
  const recipe = `fixture recipe for ${gate}\n`;
  await fs.writeFile(path.join(root, 'RECIPE.txt'), recipe);
  const payload = {};
  for (const relative of (await payloadFiles(root)).sort()) {
    payload[relative] = sha256(await fs.readFile(path.join(root, ...relative.split('/'))));
  }
  const binding = {
    schema: 1,
    gate,
    cjcj_head_sha: checkoutHead(checkout),
    producer: {
      repository: 'fixture/cangjie-runtime',
      head_sha: producerHead,
      head_file: 'meta.txt',
    },
    recipe: {
      id: `${gate.toLowerCase()}-fixture`,
      file: 'RECIPE.txt',
      sha256: sha256(recipe),
    },
    measurement: {
      started_utc: '2026-08-11T00:00:00+08:00',
      finished_utc: '2026-08-11T00:01:00+08:00',
    },
    payload_sha256: payload,
  };
  await fs.writeFile(path.join(root, 'EVIDENCE_BINDING.json'), `${JSON.stringify(binding, null, 2)}\n`);
  return binding;
}
