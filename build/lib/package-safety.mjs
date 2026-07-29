import fs from 'node:fs/promises';
import path from 'node:path';

function isStrictDescendant(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative !== '' && relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

export async function requirePrivateStage(stage, outputRoot, sourceRoot) {
  const info = await fs.lstat(stage).catch(() => null);
  if (!info?.isDirectory() || info.isSymbolicLink()) {
    throw new Error(`package stage must be a real directory, not a symbolic link: ${stage}`);
  }

  const [stageReal, outputReal, sourceReal] = await Promise.all([
    fs.realpath(stage), fs.realpath(outputRoot), fs.realpath(sourceRoot),
  ]);
  if (!isStrictDescendant(outputReal, stageReal)) {
    throw new Error(`package stage escapes its private output root: stage=${stageReal} root=${outputReal}`);
  }
  if (stageReal === sourceReal || isStrictDescendant(sourceReal, stageReal) ||
      isStrictDescendant(stageReal, sourceReal)) {
    throw new Error(`package stage overlaps source SDK: stage=${stageReal} sdk=${sourceReal}`);
  }
  return stageReal;
}
