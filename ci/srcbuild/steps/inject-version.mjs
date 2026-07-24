#!/usr/bin/env zx

import path from 'node:path';

import {injectCangjieVersion} from './inject-version-lib.mjs';

const repoRoot = process.env.GITHUB_WORKSPACE || path.resolve(import.meta.dirname, '../../..');
const version = process.env.SOURCE_SDK_VERSION;
if (!version) throw new Error('SOURCE_SDK_VERSION is required');
await injectCangjieVersion(repoRoot, version);
