#!/usr/bin/env zx
// Formal environment CLI with only the previously produced native interface
// fixture. No actual SDK or Node copy, no LSP semantic qualification.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT,source=process.env.TOOL_AVAILABILITY_FIXTURE;
if(!parent||!source)throw Error('RELEASE_EVIDENCE_TEST_ROOT and TOOL_AVAILABILITY_FIXTURE required');
const work=await fs.mkdtemp(path.join(parent,'environment-availability-'));
const partial=path.join(work,'partial'),sdk=path.join(work,'sdk'),output=path.join(work,'output');
const inputs=JSON.parse(await fs.readFile(path.join(source,'TOOLS-INPUTS.json'),'utf8'));
const row=inputs.files['tools/bin/LSPServer'];assert.equal(row.producer.source.status,'resolved');
const files=new Set(['TOOLS-INPUTS.json','STAGE-INPUTS.json',row.entry.path,row.entry.recipe.path,row.artifact.path]);
for(const r of Object.values(inputs.installationInputs.artifacts))files.add(r.sdkRelative);
for(const r of Object.values(row.producer.build.inputs.artifacts))files.add(r.sdkRelative);
for(const rel of files){await fs.mkdir(path.dirname(path.join(partial,rel)),{recursive:true});await fs.copyFile(path.join(source,rel),path.join(partial,rel));}
await fs.mkdir(path.join(partial,'modules'),{recursive:true});
await fs.writeFile(path.join(partial,'envsetup.sh'),'export CANGJIE_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\n');
const entry=fileURLToPath(new URL('../../ci/cangjie-test/environment.py',import.meta.url)),records=[];
async function run(label,argv){
 const p=spawnSync(argv[0],argv.slice(1),{env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'},encoding:'utf8',maxBuffer:1024*1024});
 records.push({label,argv,pid:p.pid,rc:p.status,signal:p.signal,error:p.error?.message});
 await fs.writeFile(work+'/'+label+'.stdout',p.stdout??'');await fs.writeFile(work+'/'+label+'.stderr',p.stderr??'');
 await fs.writeFile(work+'/commands.json',JSON.stringify(records,null,2));assert.equal(p.status,0,label+': '+p.stderr);return p.stdout;
}
await run('prepare',['python3',entry,partial,sdk,output,'--arm','bootstrap']);
const manifest=JSON.parse(await fs.readFile(output+'/environment.json','utf8'));
assert.equal(manifest.tools.cjpm.ready,false,'missing CJ independent control');
console.log('ENVIRONMENT_CONTROL_MISSING_CJ_PASS');
assert.equal(manifest.tools.LSPServer.qualification.ready,false,'business path remains NOT_CONSUMED');
assert.equal(manifest.tools.LSPServer.qualification.available,true);
console.log('ENVIRONMENT_CURRENT_CONSUMER_ASSERTION_REACHED');
assert.equal(manifest.tools.LSPServer.ready,true,'available install must enter actual upstream tests');
// run.py's actual pre-execution function rereads the adjacent public reader.
// Exercise that same boundary after the real CLI emitted the manifest; this
// is not an upstream test-suite invocation or a second SDK qualification.
const python=`import sys,json,os\nfrom pathlib import Path\nsys.path.insert(0,${JSON.stringify(path.dirname(entry))})\nfrom environment import apply_environment\nsdk=Path(sys.argv[1]); manifest=json.loads(Path(sys.argv[2]).read_text())\napply_environment(sdk,dict(os.environ),manifest)\nprint('ENVIRONMENT_REENTRY_PASS')\n`;
await run('reentry',['python3','-c',python,sdk,output+'/environment.json']);
await fs.writeFile(path.join(sdk,inputs.installationInputs.artifacts.runtime.sdkRelative),'wrong runtime bytes');
const p=spawnSync('python3',['-c',python,sdk,output+'/environment.json'],{env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'},encoding:'utf8'});
records.push({label:'wrong-dependency',rc:p.status,signal:p.signal,argv:['python3','-c',python,sdk,output+'/environment.json']});
await fs.writeFile(work+'/wrong-dependency.stderr',p.stderr);await fs.writeFile(work+'/commands.json',JSON.stringify(records,null,2));
assert.equal(p.status,1);assert.match(p.stderr,/tool input changed: LSPServer: installed bytes differ/);
console.log('ENVIRONMENT_AVAILABILITY_FINITE_PASS '+work);
