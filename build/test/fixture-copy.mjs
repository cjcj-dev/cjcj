import fs from 'node:fs';

// Request independent copy-on-write files where supported. Node falls back to
// ordinary copies on other filesystems; never share writable inodes or omit data.
export function copyFixtureTree(source, destination) {
  fs.cpSync(source, destination, {
    recursive: true,
    mode: fs.constants.COPYFILE_FICLONE,
    verbatimSymlinks: true,
  });
}
