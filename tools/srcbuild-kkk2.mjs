#!/usr/bin/env zx
// The source is deployed separately; this launcher executes its native target
// configuration using the existing controlled box, with no Git/tool mutation.
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
export function remoteCommand({source,config,from,through}){
 for(const value of [source,config,from,through].filter(Boolean))if(/[\n\r\0]/.test(value))throw new Error('REMOTE_ARGUMENT');
 if(![source,config].every(value=>typeof value==='string'&&path.isAbsolute(value)
   &&['/root/','/mnt/cjcj-data/'].some(root=>path.resolve(value).startsWith(root))))throw new Error('REMOTE_PRIVATE_PATH');
 const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
 const argv=['node',path.join(source,'ci/bootstrap/sdk-flow.mjs'),'--config',config,
  ...(from?['--from',from]:[]),...(through?['--through',through]:[])];
 return 'ulimit -c 0; ulimit -Hc 0; '+argv.map(quote).join(' ');
}
export function main(args=process.argv.slice(2)){
 const {values}=parseArgs({args,options:{lane:{type:'string'},source:{type:'string'},config:{type:'string'},from:{type:'string'},through:{type:'string'},'memory-gb':{type:'string'}}});
 if(!/^[a-zA-Z0-9_-]+$/.test(values.lane||''))throw new Error('LANE_REQUIRED');
 if(values['memory-gb']!==undefined&&(!/^[1-9][0-9]*$/.test(values['memory-gb'])||!Number.isSafeInteger(Number(values['memory-gb']))))throw new Error('MEMORY_GB');
 const roots=['/root/','/mnt/cjcj-data/'].map(root=>root+values.lane+'/');
 if(![values.source,values.config].every(value=>typeof value==='string'&&path.isAbsolute(value)
   &&roots.some(root=>path.resolve(value).startsWith(root))))throw new Error('LANE_PATH');
 const command=remoteCommand(values);
 // The existing workflow controller owns defaults and actual capacity checks.
 // Preserve the caller's admitted jobs/memory; only an explicit option overrides memory.
 const r=spawnSync('/root/cj_build/tools/cjops',['control','wf-kkk2','bsh',values.lane,command],
  {stdio:'inherit',env:{...process.env,...(values['memory-gb']===undefined?{}:{KKK2_MEM_GB:values['memory-gb']})}});
 if(r.error)throw r.error;if(r.signal)throw new Error('REMOTE_SIGNAL '+r.signal);return r.status;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{process.exitCode=main();}catch(e){console.error(e.stack);process.exitCode=1;}
}
