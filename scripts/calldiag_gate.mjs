#!/usr/bin/env zx
// Call-diagnostic compile/run golden gate for generic-call compatibility behavior.

import path from 'node:path';
import {runSingleFileGoldenGate} from './zx_gate_lib.mjs';

const fixtureDir = path.join(import.meta.dirname, 'calldiag_fixtures');
const home = process.env.CANGJIE_HOME || '/root/cj_build/cangjie_compiler/output';
await runSingleFileGoldenGate({name: 'calldiag_gate', fixtureDir, goldenDir: path.join(fixtureDir, 'golden'), home, reference: process.env.REF_CJC || `${home}/bin/cjc`});
