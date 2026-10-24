#!/usr/bin/env zx
import path from 'node:path';
import fs from 'node:fs/promises';
import {copyOutputs} from '../../bootstrap/sdk-flow.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';

const workspace=process.env.CANGJIE_WORKSPACE;
if(!workspace||process.env.CJCJ_SRCBUILD_TARGET!=='linux-x64')throw new Error('WINDOWS_FFI_INSTALL_INPUT_REQUIRED');
const std=path.join(workspace,'software/final-std-windows-stage2');
await assertFinalStd(std,getTarget('windows-x64'));
const copies=['lib/libstdFFI.dll','lib/libstdFFI.dll.a'].map(rel=>({from:path.join(std,rel),to:rel,owner:'source-built Windows std'}));
for(const spec of copies)if(!(await fs.stat(spec.from)).isFile())throw new Error('WINDOWS_FFI_OUTPUT '+spec.from);
await copyOutputs(path.join(workspace,'software/cangjie'),copies);
