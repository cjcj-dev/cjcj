#!/usr/bin/env zx
// Controlled Linux transport test only. No Windows executable is run. The
// actual producer child still observes Linux and must reject Windows N.
const [mode,...args]=process.argv.slice(2);
Object.defineProperty(process,'platform',{value:'win32'});
const entry=new URL(mode==='installer'?'../bootstrap/install-windows-toolchain.mjs':'../bootstrap/native-cjdb-job.mjs',import.meta.url);
process.argv=[process.execPath,entry.pathname,...args];
await import(entry.href);
