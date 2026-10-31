import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {read, hash, requireValue} from './identity.mjs';

const pins = read(new URL('./legacy-pins.json', import.meta.url));
export function legacy(directory, operation, args, transportArchive = null) {
  for (const [name, sha] of Object.entries(pins.files)) {
    requireValue(hash(path.join(directory, name)) === sha, 'legacy-pin:' + name);
  }
  // Run the immutable original validators and prepare entry, never a compiler.
  // A labelled offline archive parameter changes only the SDK transport pin.
  const code = `import sys,json\nfrom pathlib import Path\nsys.path.insert(0,sys.argv[1])\nimport identity,prepare_build\nif sys.argv[3] != 'null': identity.FROZEN['sdk_archive_sha256']=json.loads(sys.argv[3])\na=json.loads(sys.argv[4])\nif sys.argv[2]=='prepare': prepare_build.prepare(Path(a[0]),Path(a[1]),a[2])\nelse:\n r=json.loads(Path(a[0]).read_text())\n identity.require(r['steps']==prepare_build.fixed_steps(Path(a[0]).parent,r['inputs']),'fixed-build-steps')\n identity.require(prepare_build.capture_inputs(Path(a[0]).parent,r['inputs'])==r['input_manifest'],'build-input-drift')\n`;
  const result = spawnSync('python3', ['-c', code, directory, operation, JSON.stringify(transportArchive), JSON.stringify(args)], {encoding: 'utf8'});
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  requireValue(result.status === 0, 'legacy-' + operation);
}
