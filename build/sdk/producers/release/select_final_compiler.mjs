#!/usr/bin/env node
import fs from 'node:fs/promises';
import {consumeFinalCompiler} from '../srcbuild/lib/final-compiler.mjs';
const binary = await consumeFinalCompiler({
  directory: process.env.FINAL_COMPILER_DIR,
  platform: process.env.RELEASE_PLATFORM,
  repository: `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}.git`,
  commit: process.env.GITHUB_SHA,
  runId: process.env.GITHUB_RUN_ID,
  runAttempt: process.env.GITHUB_RUN_ATTEMPT,
  std: process.env.FINAL_STD_DIR,
});
await fs.appendFile(process.env.GITHUB_ENV, `FINAL_COMPILER_BINARY=${binary}\n`);
console.log(`FINAL_COMPILER_SELECTED ${binary}`);
