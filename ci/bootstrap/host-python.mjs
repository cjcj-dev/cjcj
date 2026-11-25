import fs from 'node:fs/promises';
import path from 'node:path';

// build.py needs the runner's interpreter even when the SDK supplies a Python
// for CJDB. Preserve a host venv's executable path when checking symlinks.
export async function resolveHostPython(sdk, env = process.env) {
  const roots = [];
  for (const root of new Set([sdk, env.CANGJIE_HOME].filter(Boolean))) {
    roots.push(path.resolve(root));
    try { roots.push(await fs.realpath(root)); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const inSdk = file => roots.some(root => {
    const rel = path.relative(root, file);
    return rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel);
  });
  const search = env.PATH ?? env.Path ?? '';
  const names = process.platform === 'win32' ? ['python3.exe', 'python.exe'] : ['python3'];
  for (const dir of search.split(path.delimiter)) {
    if (!path.isAbsolute(dir) || inSdk(dir)) continue;
    for (const name of names) {
      const file = path.join(dir, name);
      try {
        if (inSdk(await fs.realpath(dir)) || inSdk(await fs.realpath(file))) continue;
        if (!(await fs.stat(file)).isFile()) continue;
        await fs.access(file, fs.constants.X_OK);
        return file;
      } catch (error) {
        if (!['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) throw error;
      }
    }
  }
  throw new Error('Host Python 3 executable not found outside the SDK on PATH');
}
