#!/usr/bin/env zx
// Node cannot spawn a Windows .cmd shim without a shell.
import fs from 'node:fs/promises';
import path from 'node:path';
export async function npxZx(script,env=process.env) {
  const args=['--yes','zx@8',script];
  if(process.platform!=='win32')return ['npx',...args];
  for(const cli of [
    ...(env.npm_execpath?[path.join(path.dirname(env.npm_execpath),'npx-cli.js')]:[]),
    path.join(path.dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),
    path.resolve(path.dirname(process.execPath),'../lib/node_modules/npm/bin/npx-cli.js'),
  ])if((await fs.stat(cli).catch(error=>{if(error.code!=='ENOENT')throw error;}))?.isFile())
    return [process.execPath,cli,...args];
  throw Error('SHIM_BUILD_NPX_CLI_REQUIRED');
}
