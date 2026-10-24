import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {capturedTraceCommand,requireTraceCommand,windowsTraceCommands} from './native-windows-llvm-trace.mjs';
const execute=promisify(execFile);
const root=await fs.mkdtemp(path.join(process.env.TRACE_TEST_EVIDENCE||os.tmpdir(),'trace-command-'));
test.after(async()=>{if(!process.env.TRACE_TEST_EVIDENCE)await fs.rm(root,{recursive:true});});

test('real command records actual PID, own rc and unmodified output',async()=>{
  const row=await capturedTraceCommand([process.execPath,'-e','console.log(process.pid); console.error("stderr-original");'],{work:root,label:'positive'});
  requireTraceCommand(row);
  assert.equal(Number((await fs.readFile(path.join(root,row.stdout),'utf8')).trim()),row.pid);
  assert.equal(await fs.readFile(path.join(root,row.stderr),'utf8'),'stderr-original\n');
  assert.equal(row.rc,0);assert.ok(row.pid>0);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(root,'positive.json'),'utf8')),row);
});
test('real nonzero target rc cannot become successful capture',async()=>{
  const row=await capturedTraceCommand([process.execPath,'-e','process.exit(17)'],{work:root,label:'target-red'});
  assert.equal(row.rc,17);console.log('TRACE_NONZERO_TARGET_ASSERTION_REACHED');
  assert.throws(()=>requireTraceCommand(row),error=>error.rc===17&&error.command===row);
});
test('spawn failure stays distinct from a child exit code',async()=>{
  const row=await capturedTraceCommand([path.join(root,'no-such-tool')],{work:root,label:'spawn-failure'});
  assert.equal(row.pid,null);assert.equal(row.rc,null);assert.equal(row.error.code,'ENOENT');
  assert.throws(()=>requireTraceCommand(row),/WINDOWS_TRACE_COMMAND_FAILED/);
});
test('trace argv preserve provider flags, native originals and session scope',()=>{
  const commands=windowsTraceCommands(root,{logman:'logman.exe',tracerpt:'tracerpt.exe'});
  assert.ok(commands.start.includes('(process,img)'));
  assert.deepEqual(commands.stop,['logman.exe','stop','NT Kernel Logger','-ets']);
  assert.ok(commands.decode.includes(path.join(root,'host-llvm.etl')));
  assert.ok(commands.decode.includes('-summary'));assert.ok(!commands.decode.includes('-lr'));
});
test('public entry rejects Linux without creating trace work or claiming loads',async()=>{
  assert.notEqual(process.platform,'win32');
  const work=path.join(root,'not-created'),config=path.join(root,'foreign.json');
  await fs.writeFile(config,JSON.stringify({host:root,work,tools:{logman:'logman.exe',tracerpt:'tracerpt.exe'}}));
  await assert.rejects(execute(process.execPath,['ci/bootstrap/native-windows-llvm-trace.mjs',config]),error=>
    error.code===1&&error.stderr.includes('WINDOWS_TRACE_NATIVE_HOST_REQUIRED'));
  assert.equal(await fs.stat(work).catch(()=>null),null);
});
