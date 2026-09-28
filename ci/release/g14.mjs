#!/usr/bin/env node
import {main} from './gc-campaign.mjs';
try { await main('G14'); }
catch (error) { console.error(error.message); process.exitCode = 2; }
