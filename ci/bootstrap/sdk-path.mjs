// Inputs are native paths, not inventory keys. Fold only ASCII on Windows.
import path from 'node:path';

export const foldAscii = value => value.replace(/[A-Z]/g, c => c.toLowerCase());

export function pathKey(file, platform) {
  if (platform !== 'win32') return path.posix.normalize(file);
  return foldAscii(path.win32.normalize(file));
}

export function belowRoot(file, root, platform) {
  const paths = platform === 'win32' ? path.win32 : path.posix;
  if (!paths.isAbsolute(file)) return false;
  const base = pathKey(root, platform);
  const candidate = pathKey(file, platform);
  const prefix = base.endsWith(paths.sep) ? base : base + paths.sep;
  return candidate.startsWith(prefix) && candidate.length > prefix.length;
}
