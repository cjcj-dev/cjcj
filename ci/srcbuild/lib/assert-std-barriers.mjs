import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileDigest} from '../../bootstrap/sdk-io.mjs';
import {nativeSymbols} from '../../bootstrap/std-runtime-colour.mjs';
const STRING_METHODS=['_CNat6String7indexOfHRNatY0_E','_CNat6String7toArrayHv'];
const STRING_CALLERS=['_CNak12ParserHelper12doLongParserHRNat5ArrayIRNat6StringEEY3_l','_CNacXCNac7HashMapIG_G0_E8toStringHv'];

// The existing bounded streaming/cancellation facility is shared by the
// disassembler and installed consumer. It does not interpret instructions.
export function streamStdProcess(argv, {signal,cwd,env,onLine,limit=8*1024*1024,
  capture=true,tailStderr=false,label='STD_PROCESS',timeout=180000}={}) {
 return new Promise((resolve,reject)=>{
  if(signal?.aborted)return reject(new Error(label+'_CANCELLED'));
  // C2's posix_spawn tools inherit this session/group and these pipes.
  // Own exactly this invocation, never the caller's or a name-matched process.
  const grouped=process.platform==='linux';
  const child=spawn(argv[0],argv.slice(1),{cwd,env,detached:grouped,stdio:['ignore','pipe','pipe']});
  const processGroup=grouped?child.pid:undefined;
  let stdout='',stderr='',pending='',bytes=0,failure,killTimer,timeoutTimer,cleanupTimer,pollTimer;
  let closed=false,exited=false,settled=false,code=null,childSignal=null;
  const alive=()=>{
   if(!child.pid)return false;
   if(!grouped)return !exited;
   try{process.kill(-processGroup,0);return true;}catch(error){if(error.code==='ESRCH')return false;throw error;}
  };
  const send=kind=>{
   try{if(grouped&&processGroup)process.kill(-processGroup,kind);else if(!exited)child.kill(kind);}
   catch(error){if(error.code!=='ESRCH')failure ||= error;}
  };
  const finish=cleanupComplete=>{
   if(settled)return;settled=true;
   for(const timer of [killTimer,timeoutTimer,cleanupTimer])clearTimeout(timer);
   clearInterval(pollTimer);signal?.removeEventListener('abort',cancel);
   if(!cleanupComplete){failure ||= new Error(label+'_CLEANUP_INCOMPLETE');child.stdout.destroy();child.stderr.destroy();child.unref();}
   const result={code,signal:childSignal,stdout,stderr,processGroup,cleanupComplete};
   if(failure){reject(Object.assign(failure,{...result,rc:code||1,childRc:code}));return;}
   resolve(result);
  };
  const check=()=>{
   if(settled)return;
   try{if(closed&&!alive())finish(true);}catch(error){stop(error);}
  };
  const stop=error=>{
   if(settled)return;failure ||= error;send('SIGTERM');
   if(!killTimer)killTimer=setTimeout(()=>{send('SIGKILL');check();},500);
   if(!pollTimer)pollTimer=setInterval(check,25);
   // A bounded return is not a claim of cleanup: never PASS on this branch.
   if(!cleanupTimer)cleanupTimer=setTimeout(()=>finish(false),2000);
   check();
  };
  const cancel=()=>stop(new Error(label+'_CANCELLED'));
  const emit=line=>{try{onLine?.(line);}catch(error){stop(error);}};
  child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
  child.stdout.on('data',chunk=>{
   if(failure)return;
   bytes+=Buffer.byteLength(chunk);
   if(bytes>limit){stop(new Error(label+'_OUTPUT_LIMIT'));return;}
   if(capture)stdout+=chunk;
   for(const part of chunk.split(/(?<=\n)/)){
    if(pending.length+part.length>65536){pending='';stop(new Error(label+'_LINE_LIMIT'));return;}
    pending+=part;
    if(pending.endsWith('\n')){emit(pending.slice(0,-1).replace(/\r$/,''));pending='';if(failure)return;}
   }
  });
  child.stderr.on('data',chunk=>{
   if(failure)return;
   if(tailStderr)stderr=(stderr+chunk).slice(-65536);
   else{bytes+=Buffer.byteLength(chunk);if(bytes>limit){stop(new Error(label+'_OUTPUT_LIMIT'));return;}stderr+=chunk;}
  });
  child.stdout.on('error',stop);child.stderr.on('error',stop);child.once('error',stop);
  child.once('exit',(rc,sig)=>{
   exited=true;code=rc;childSignal=sig;
   if(settled)return;
   try{if(alive())stop(new Error(label+'_DESCENDANTS_AFTER_EXIT'));}catch(error){stop(error);}
  });
  child.once('close',(rc,sig)=>{
   exited=true;closed=true;code=rc;childSignal=sig;
   if(settled)return;
   if(!failure&&pending)emit(pending);
   try{if(alive())stop(new Error(label+'_DESCENDANTS_AFTER_CLOSE'));else check();}catch(error){stop(error);}
  });
  signal?.addEventListener('abort',cancel,{once:true});
  timeoutTimer=setTimeout(()=>stop(new Error(label+'_TIMEOUT')),timeout);
  if(signal?.aborted)cancel();
 });
}
export async function streamBarrierObjdump(args,{signal}={}) {
 const states=[...STRING_METHODS,...STRING_CALLERS].map(symbol=>({symbol,found:false}));
 const result=await streamStdProcess(['objdump',...args],{signal,capture:false,
  limit:Infinity,tailStderr:true,label:'STD_BARRIER',onLine:line=>{
   const header=line.match(/^\s*[0-9a-f]+ <([^>]+)>:$/);
   if(!header)return;
   const state=states.find(s=>s.symbol===header[1]);
   if(state){if(state.found)throw new Error('STD_BARRIER_DUPLICATE '+state.symbol);state.found=true;}
  }});
 return {...result,states};
}
export async function assertStdBarriers({coreLib, runtime, hostRuntime, target, signal,
  argoptLib=path.join(path.dirname(coreLib),'libcangjie-std-argopt.a'),
  collectionLib=path.join(path.dirname(coreLib),'libcangjie-std-collection.a')}) {
  signal?.throwIfAborted();
  const platform=target.spec.key;
  const [colourSymbols,hostSymbols,stdSymbols]=await Promise.all([
    nativeSymbols(runtime,{platform,runtime:true}),nativeSymbols(hostRuntime,{platform,runtime:true}),
    nativeSymbols(coreLib,{platform})]);
  signal?.throwIfAborted();
  const exports=new Set([...colourSymbols].filter(name=>!hostSymbols.has(name)));
  console.error(`STD-COLOUR-EXPORTS colour_runtime=${runtime} colour_runtime_sha256=${await fileDigest(runtime)} host_runtime=${hostRuntime} host_runtime_sha256=${await fileDigest(hostRuntime)} colour_only=${[...exports].sort().join(',')||'none'}`);
  if(!exports.size)throw new Error('empty colour-only runtime export set');
  const hasColour=[...stdSymbols].some(name=>exports.has(name));
  const hasReadBarrier=[...stdSymbols].some(name=>/^CJ_MCC_Read(?:StaticRef|RefField)$/.test(name));
  console.log(`STAGE3_BARRIER_SYMBOL_ASSERTION_REACHED colour=${hasColour} read_barrier=${hasReadBarrier}`);
  if (!hasColour || !hasReadBarrier) {
    throw new Error(`final std barrier symbol assertion failed: colour=${hasColour} read_barrier=${hasReadBarrier}`);
  }
  if (target.spec.os !== 'linux' || target.spec.arch !== 'x86_64') {
    // The existing instruction-shape probe is x86-specific. On native AArch64
    // and Mach-O, require both exact runtime references instead of pretending
    // the x86 shr/relocation syntax applies.
    console.log(`STAGE3_BARRIER_SYMBOL_ASSERT_PASS target=${target.spec.key} colour=1 read_barrier=1`);
    return {rc: 0, signal: null};
  }
  const inspect=async archive=>{
  const output = await streamBarrierObjdump(['-drw', archive], {signal});
  if (output.signal || output.code !== 0) {
    const error = new Error(`objdump failed rc=${output.code} signal=${output.signal}`);
    error.rc = output.code;
    error.signal = output.signal;
    throw error;
  }
  signal?.throwIfAborted();
  return output.states;
  };
  // These are definition/linkage checks, not a machine-code safety proof.
  for(const [archive,symbols] of [[coreLib,STRING_METHODS],
      [argoptLib,[STRING_CALLERS[0]]],[collectionLib,[STRING_CALLERS[1]]]]) {
    const states=await inspect(archive);
    for(const symbol of symbols)if(!states.find(s=>s.symbol===symbol)?.found)
      throw new Error('STD_BARRIER_DEFINITION_MISSING '+symbol);
    console.log(`STD-STRING-INPUT archive=${archive} sha256=${await fileDigest(archive)}`);
  }
  signal?.throwIfAborted();
  console.log('STAGE3_BARRIER_LINKAGE_PASS scope=runtime-references-and-definitions semantic-consumer=separate');
  return {rc:0,signal:null};
}
