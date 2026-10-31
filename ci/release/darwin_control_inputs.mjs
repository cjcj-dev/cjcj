import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
export const repository = fileURLToPath(new URL('../../', import.meta.url));
export function copyDarwinControlSource(root) {
  // sdk-platform -> sdk-io -> sdk-flow's normal imports are retained. Copy the
  // current candidate's two module directories; no historical source checkout.
  for (const relative of ['ci/release', 'ci/bootstrap', 'build/lib'])
    fs.cpSync(path.join(repository, relative), path.join(root, relative), {recursive:true});
  for (const relative of ['ci/build-resources.mjs', 'ci/host-toolchain-pin.mjs'])
    fs.copyFileSync(path.join(repository, relative), path.join(root, relative));
}
export function writeCut(out, original, changed, label) {
  // Retain the exact two files as well as the unified diff; caller checks diff rc.
  fs.writeFileSync(path.join(out, `${label}.original`), original);
  fs.writeFileSync(path.join(out, `${label}.changed`), changed);
}
