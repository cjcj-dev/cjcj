#!/usr/bin/env zx
// Generic-call resolution compile/run golden gate for the self-host compiler.

import path from 'node:path';
import {runSingleFileGoldenGate} from './zx_gate_lib.mjs';

const fixtureDir = path.join(import.meta.dirname, 'generic_fixtures');
const home = process.env.CANGJIE_HOME || '/root/cj_build/cangjie_compiler/output';
await runSingleFileGoldenGate({name: 'generic_gate', fixtureDir, goldenDir: path.join(fixtureDir, 'golden'), home, reference: process.env.REF_CJC || `${home}/bin/cjc`});
