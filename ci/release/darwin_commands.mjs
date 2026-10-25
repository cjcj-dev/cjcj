// Preserve each native subprocess's own output, status and signal, including failure.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
export function darwinCommand(work, label, command, args, options = {}) {
  fs.mkdirSync(work, {recursive:true});
  const stdout = path.join(work, `${label}.stdout`), stderr = path.join(work, `${label}.stderr`);
  const out = fs.openSync(stdout, 'w'), err = fs.openSync(stderr, 'w');
  let result;
  const start = new Date().toISOString();
  try { result = spawnSync(command, args, {...options, stdio:['ignore', out, err]}); }
  finally { fs.closeSync(out); fs.closeSync(err); }
  const record = {command, args, start, end:new Date().toISOString(), rc:result.status,
    signal:result.signal, error:result.error?.message || null, stdout, stderr};
  fs.writeFileSync(path.join(work, `${label}.json`), JSON.stringify(record, null, 2)+'\n');
  const output = fs.readFileSync(stdout, 'utf8'), errors = fs.readFileSync(stderr, 'utf8');
  process.stdout.write(output); process.stderr.write(errors);
  if (result.error || result.status !== 0) throw Object.assign(new Error(`DARWIN_COMMAND_FAILED ${label} rc=${result.status} signal=${result.signal}`),
    {exitCode:result.status || 1, cause:result.error});
  return {stdout:output, stderr:errors};
}
