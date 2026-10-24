#!/usr/bin/env zx
// Existing shell CLI forwards to the single native target entry.
import {main} from './sdk-flow.mjs';
try{await main();}catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
