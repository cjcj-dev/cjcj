#!/usr/bin/env zx
// Annotation compile/run golden gate for self-host annotation-factory wiring.

import path from 'node:path';
import {runSingleFileGoldenGate} from './zx_gate_lib.mjs';

const fixtureDir = path.join(import.meta.dirname, 'anno_fixtures');
await runSingleFileGoldenGate({
  name: 'anno_gate', fixtureDir, goldenDir: path.join(fixtureDir, 'golden'),
  home: process.env.CANGJIE_HOME || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029',
  reference: process.env.REF_CJC || '/root/.cjv/bin/cjc', includeHome: true, copyAsProg: true, replaceCjcBuild: true,
  fixtures: ['w1_class_declonly', 'w2_struct_declonly', 'w3_globalvar_declonly', 'w4_enum_declonly', 'u1_class_used', 'u2_globalvar_used', 'b1_func_declonly', 'b2_enum_ctor'],
});
