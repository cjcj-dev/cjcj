import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

// Upstream stdlib/cmake/modules/AddCangjieSource.cmake:125-136:
// Release trims the source root; debug builds retain source locations.
export async function prepareTrimpath(sourceRoot, {debug = false} = {}) {
  const root = path.resolve(sourceRoot);
  const file = path.join(root, 'cjpm.toml');
  const text = await fs.readFile(file, 'utf8');
  const result = text.replace(/^(\s*compile-option\s*=\s*)("(?:[^"\\]|\\.)*")(.*)$/m,
    (_, prefix, encoded, suffix) => {
      const options = JSON.parse(encoded);
      const tokens = options.match(/"(?:[^"\\]|\\.)*"|'[^']*'|[^\s]+/g) || [];
      const clean = [];
      for (let i = 0; i < tokens.length; ++i) {
        if (tokens[i] === '--trimpath') { ++i; continue; }
        if (tokens[i].startsWith('--trimpath=')) continue;
        clean.push(tokens[i]);
      }
      if (!debug && !clean.includes('-g') && !clean.includes('--coverage')) {
        clean.push('--trimpath', JSON.stringify(root.replaceAll('\\', '/')));
      }
      return prefix + JSON.stringify(clean.join(' ')) + suffix;
    });
  await fs.writeFile(file, result);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await prepareTrimpath(process.argv[2] || '.', {debug: process.argv.includes('--debug')});
}
