
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const entry=path.resolve(import.meta.dirname,'../steps/build-shim.mjs');
async function run(t,body) {
 const base=process.env.CONSTRAINT_TEST_ROOT || os.tmpdir();
 await fs.mkdir(base,{recursive:true});
 const cwd=await fs.mkdtemp(path.join(base,'shim-output-'));
 if(!process.env.CONSTRAINT_TEST_ROOT)t.after(()=>fs.rm(cwd,{recursive:true,force:true}));
 await fs.mkdir(path.join(cwd,'runtime_shim'));
 await fs.writeFile(path.join(cwd,'runtime_shim/build_shim.mjs'),"import fs from 'node:fs';\n"+body);
 const env={...process.env,CANGJIE_CPP_SRC:cwd};
 for(const key of ['CJCJ_LLVM_SHIM_O','CJCJ_BOOTSTRAP_CPP_SRC'])delete env[key];
 const result=spawnSync(process.execPath,[entry],{cwd,env,encoding:'utf8',timeout:120000});
 assert.ifError(result.error);
 assert.equal(result.signal,null,result.stderr);
 const command=JSON.parse(await fs.readFile(path.join(cwd,'.srcbuild/shim-build-command.json')));
 console.log(JSON.stringify({cwd,outerRc:result.status,command}));
 return {...result,cwd,command};
}
// This child exercises public caller log/exit transport, not Cangjie compilation.
test('public build-shim accepts successful output beyond the old 16 MiB buffer',async t=>{
 const r=await run(t,"const chunk=Buffer.alloc(1024*1024,120); for(let i=0;i<17;i++)fs.writeSync(1,chunk); fs.writeSync(2,'\\nOUTPUT_COMPLETE\\n'); fs.writeFileSync('runtime_shim/cjselfhost_llvmshim.o','fixture-object');");
 assert.equal(r.status,0,r.stderr);
 assert.equal(r.command.rc,0);
 assert.ok((await fs.stat(path.join(r.cwd,'.srcbuild/shim-build.log'))).size>=17*1024*1024);
 const log=await fs.open(path.join(r.cwd,'.srcbuild/shim-build.log'));
 try {const size=(await log.stat()).size; const tail=Buffer.alloc(64);await log.read(tail,0,64,size-64);assert.match(tail.toString(),/OUTPUT_COMPLETE/);}
 finally {await log.close();}
});
test('public build-shim preserves a failing child rc',async t=>{
 const r=await run(t,"fs.writeSync(2,'CHILD_RC_23'); process.exit(23);");
 assert.equal(r.status,23,r.stderr);assert.equal(r.command.rc,23);
 assert.match(await fs.readFile(path.join(r.cwd,'.srcbuild/shim-build.log'),'utf8'),/CHILD_RC_23/);
});
test('public build-shim retains the vendored object rejection',async t=>{
 const r=await run(t,"fs.writeSync(1,'used vendored prebuilt shim'); fs.writeFileSync('runtime_shim/cjselfhost_llvmshim.o','fixture-object');");
 assert.equal(r.status,1);assert.equal(r.command.rc,0);assert.match(r.stderr,/SHIM_BUILD_VENDORED/);
});
