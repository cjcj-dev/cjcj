#!/usr/bin/env zx
import fs from 'node:fs';

for (const file of ['ci/runtime_pin.env', 'ci/colour-runtime/darwin_aarch64.env']) {
  fs.appendFileSync(process.env.GITHUB_ENV, fs.readFileSync(file));
}
