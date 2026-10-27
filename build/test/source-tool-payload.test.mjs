import {hlePayloadFixture} from './hle-payload-fixture.mjs';
// The release tool path is only wired if the three programs that make it up
// agree on the same payload. This drives them for real -- prepare, install, then
// the manifest the package is described by -- because a test that reads their
// source text cannot see a tool whose binary arrives without the configuration
// or shared library it needs, which is what the release package would ship.
//
// cjfmt is the case that matters: it reads a default formatting configuration
// and links a shared library whose implementation lives in tools/lib. The
// official SDK has both, so replacing only the binary keeps a foreign
// configuration next to our front end.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {getTarget} from '../lib/targets.mjs';
import {sourceToolPayloads} from '../../ci/release/source-tool-payloads.mjs';

const root = path.resolve(import.meta.dirname, '..', '..');
const prepare = path.join(root, 'ci', 'release', 'prepare_tools_artifact.mjs');
const install = path.join(root, 'ci', 'release', 'install_tools_artifact.mjs');
const digest = contents => createHash('sha256').update(contents).digest('hex');

function writeExecutable(file, contents) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents, {mode: 0o755});
}

function writeFile(file, contents) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, contents);
}

// Transport fixture source facts are explicit. A separate arm uses an older source.
// These records do not claim a native tool build or semantic qualification.
function producerFacts(sdk,tool,binary,platform='linux-x64',source=null) {
  const pins=Object.fromEntries(fs.readFileSync(path.join(root,'ci/source_pin.env'),'utf8').split('\n').filter(line=>line.includes('=')).map(line=>[line.slice(0,line.indexOf('=')),line.slice(line.indexOf('=')+1)]));
  source??={status:'resolved',repository:pins.TOOLS_SRC_URL,commit:pins.TOOLS_REF};
  const file=path.join(sdk,'TOOLS-INPUTS.json'),suffix=platform==='windows-x64'?'.exe':'';
  const inputs=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):{files:{}};
  const sha256=digest(fs.readFileSync(binary)),payloads={};
  if(tool==='cjlint')for(const name of fs.readdirSync(path.join(sdk,'tools/config')).filter(name=>name.endsWith('.json'))) {
    const rel='tools/config/'+name;payloads[rel]={sha256:digest(fs.readFileSync(path.join(sdk,rel)))};
  }
  if(tool==='cjprof')for(const prefix of ['tools/config/static','.target-tools/tools/config/static']) {
    for(const tail of fs.readdirSync(path.join(sdk,prefix),{recursive:true})) {
      const rel=prefix+'/'+tail;if(fs.statSync(path.join(sdk,rel)).isFile())payloads[rel]={sha256:digest(fs.readFileSync(path.join(sdk,rel)))};
    }
  }
  inputs.files['tools/bin/'+tool+suffix]={sha256,producer:{source,
    artifact:{sha256},build:{rc:0,platform:getTarget(platform).spec.llvmPlatform},install:{rc:0,artifact:{path:binary,sha256},payloads}}};
  writeFile(file,JSON.stringify(inputs));
}
// A source-built SDK as the srcbuild stage leaves it: the tool binary, its
// configuration, and the shared library its front end links against.
function sourceSdk(rootDirectory) {
  const sdk = path.join(rootDirectory, 'source-sdk');
  writeExecutable(path.join(sdk, 'tools', 'bin', 'cjfmt'), 'source-built cjfmt bytes\n');
  writeFile(path.join(sdk, 'tools', 'config', 'cangjie-format.toml'), 'indentWidth = 4\n');
  writeFile(path.join(sdk, 'tools', 'lib', 'libcangjie-lsp.so'), 'source-built lsp library\n');
  producerFacts(sdk,'cjfmt',path.join(sdk,'tools/bin/cjfmt'));
  return sdk;
}

// An installed release SDK as the official base leaves it: the same names, but
// the official bytes. Installing over it is what the release job does.
function installedSdk(rootDirectory) {
  const sdk = path.join(rootDirectory, 'release-sdk');
  writeExecutable(path.join(sdk, 'tools', 'bin', 'cjfmt'), 'official cjfmt bytes\n');
  writeFile(path.join(sdk, 'tools', 'config', 'cangjie-format.toml'), 'indentWidth = 2\n');
  writeFile(path.join(sdk, 'tools', 'lib', 'libcangjie-lsp.so'), 'official lsp library\n');
  return sdk;
}

function run(script, args, options = {}) {
  return execFileSync(process.execPath, [script, ...args], {
    cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options,
  });
}

test('Cangjie cjfmt reaches the package with its configuration and leaves unrelated AST alone', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'source-tool-payload-'));
  const sdk = sourceSdk(fixture);
  const artifact = path.join(fixture, 'artifact');
  const release = installedSdk(fixture);
  try {
    run(prepare, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--binary', path.join(sdk, 'tools', 'bin', 'cjfmt'),
      '--sdk', sdk, '--outdir', artifact]);
    // The producer records the payload it actually staged, not just the binary.
    const sidecar = JSON.parse(fs.readFileSync(path.join(artifact, 'SOURCE-PROVENANCE.json'), 'utf8'));
    assert.deepEqual(sidecar.payloads.map(entry => entry.path).sort(),
      ['tools/config/cangjie-format.toml'], 'the sidecar records the Cangjie formatter payload');
    assert.equal(fs.readFileSync(path.join(artifact, 'tools', 'config', 'cangjie-format.toml'), 'utf8'),
      'indentWidth = 4\n', 'the producer must carry the source configuration');

    run(install, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--artifact', artifact, '--sdk', release]);
    // The point of the whole path: the package ends up with our tool *and* our
    // configuration. The unrelated C++ AST library is not its payload. The
    // producer stamps the binary with the source lineage, so the installed bytes
    // are the staged ones plus that record rather than the raw source bytes.
    const installedBinary = fs.readFileSync(path.join(release, 'tools', 'bin', 'cjfmt'), 'utf8');
    assert.match(installedBinary, /^source-built cjfmt bytes\n/);
    assert.match(installedBinary, /CJTOOL-COMMIT:[0-9a-f]{40}/);
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'config', 'cangjie-format.toml'), 'utf8'),
      'indentWidth = 4\n', 'the source configuration must replace the official one');
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'lib', 'libcangjie-lsp.so'), 'utf8'),
      'official lsp library\n', 'cjfmt does not own the unrelated AST library');
    // The stock bytes are preserved rather than destroyed.
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'stock', 'cjfmt'), 'utf8'),
      'official cjfmt bytes\n');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('a binary swapped underneath its sidecar is refused, not installed', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'source-tool-swap-'));
  const sdk = sourceSdk(fixture);
  const artifact = path.join(fixture, 'artifact');
  const release = installedSdk(fixture);
  try {
    run(prepare, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--binary', path.join(sdk, 'tools', 'bin', 'cjfmt'),
      '--sdk', sdk, '--outdir', artifact]);
    fs.writeFileSync(path.join(artifact, 'cjfmt'), 'a different binary\n');
    assert.throws(() => run(install, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--artifact', artifact, '--sdk', release]), /binary SHA-256 mismatch/);
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'bin', 'cjfmt'), 'utf8'),
      'official cjfmt bytes\n', 'a refused install must leave the package untouched');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('a payload that differs from the recorded one is refused', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'source-tool-payload-swap-'));
  const sdk = sourceSdk(fixture);
  const artifact = path.join(fixture, 'artifact');
  const release = installedSdk(fixture);
  try {
    run(prepare, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--binary', path.join(sdk, 'tools', 'bin', 'cjfmt'),
      '--sdk', sdk, '--outdir', artifact]);
    // The configuration is replaced after the sidecar was written. Installing it
    // would give the package a configuration the record does not describe.
    fs.writeFileSync(path.join(artifact, 'tools', 'config', 'cangjie-format.toml'),
      'indentWidth = 8\n');
    assert.throws(() => run(install, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--artifact', artifact, '--sdk', release]), /payload tools\/config\/cangjie-format.toml differs/);
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'config', 'cangjie-format.toml'), 'utf8'),
      'indentWidth = 2\n', 'a refused payload must leave the official configuration in place');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('a tool the source build cannot produce for the platform fails instead of staging nothing', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'source-tool-missing-'));
  // A source SDK with the binary but without the payload the tool reads: the
  // producer must refuse rather than stage a binary that will run against
  // whatever the release tree happens to have.
  const sdk = path.join(fixture, 'source-sdk');
  writeExecutable(path.join(sdk, 'tools', 'bin', 'cjfmt'), 'source-built cjfmt bytes\n');
  producerFacts(sdk,'cjfmt',path.join(sdk,'tools/bin/cjfmt'));
  try {
    assert.throws(() => run(prepare, ['--tool', 'cjfmt', '--platform', 'linux-x64',
      '--binary', path.join(sdk, 'tools', 'bin', 'cjfmt'),
      '--sdk', sdk, '--outdir', path.join(fixture, 'artifact')]),
      /source SDK has no tools\/config/);
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

// hle keeps its own producer and installer because srcbuild renames its
// product. It has the same obligation as the shared path: the parser payload its
// entry point loads has to travel with the binary, and the installer has to put
// it back rather than leaving the official one in place.
test('hle carries its parser payload through its own producer and installer', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'hle-payload-'));
  const source = path.join(fixture, 'source-sdk');
  writeExecutable(path.join(source, 'tools', 'bin', 'hle'), 'source-built hle bytes\n');
  writeFile(path.join(source, 'tools', 'dtsparser', 'analysis.js'), 'source parser\n');
  hlePayloadFixture(source);
  const artifact = path.join(fixture, 'artifact');
  const release = path.join(fixture, 'release-sdk');
  writeExecutable(path.join(release, 'tools', 'bin', 'hle'), 'official hle bytes\n');
  writeFile(path.join(release, 'tools', 'dtsparser', 'analysis.js'), 'official parser\n');
  const hlePrepare = path.join(root, 'ci', 'release', 'prepare_hle_artifact.mjs');
  const hleInstall = path.join(root, 'ci', 'release', 'install_hle_artifact.mjs');
  try {
    run(hlePrepare, ['--platform', 'linux-x64',
      '--binary', path.join(source, 'tools', 'bin', 'hle'),
      '--sdk', source, '--outdir', artifact]);
    const sidecar = JSON.parse(fs.readFileSync(path.join(artifact, 'HLE-PROVENANCE.json'), 'utf8'));
    assert.deepEqual(sidecar.payloads.map(entry => entry.path), ['tools/dtsparser', 'tools/bin/node']);
    assert.equal(fs.readFileSync(path.join(artifact, 'tools', 'dtsparser', 'analysis.js'), 'utf8'),
      'source parser\n', 'the producer must carry the source parser payload');

    run(hleInstall, ['--platform', 'linux-x64', '--artifact', artifact, '--sdk', release]);
    assert.match(fs.readFileSync(path.join(release, 'tools', 'bin', 'hle'), 'utf8'),
      /^source-built hle bytes\n/, 'the source binary must be installed');
    assert.equal(fs.readFileSync(path.join(release, 'tools', 'dtsparser', 'analysis.js'), 'utf8'),
      'source parser\n', 'the source parser must replace the official one');

    // A payload changed after the sidecar was written is refused.
    fs.writeFileSync(path.join(artifact, 'tools', 'dtsparser', 'analysis.js'), 'tampered parser\n');
    assert.throws(() => run(hleInstall, ['--platform', 'linux-x64', '--artifact', artifact, '--sdk', release]),
      /payload tools\/dtsparser differs/);
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

test('the payload table covers every tool the release installs', async () => {
  const {SOURCE_TOOLS_NATIVE, SOURCE_TOOLS_WINDOWS} = await import('../lib/release-component-provenance.mjs');
  const {sourceToolPayloads} = await import('../../ci/release/source-tool-payloads.mjs');
  // A tool the release installs without a payload declaration would silently
  // keep the official files beside a source-built binary.
  for (const tool of new Set([...SOURCE_TOOLS_NATIVE, ...SOURCE_TOOLS_WINDOWS, 'hle'])) {
    assert.doesNotThrow(() => sourceToolPayloads(tool), `${tool} has no payload declaration`);
  }
  // The tools whose behaviour actually depends on files beside the binary.
  assert.deepEqual([...sourceToolPayloads('cjfmt')].sort(),
    ['tools/config/cangjie-format.toml']);
  assert.deepEqual([...sourceToolPayloads('LSPServer')], ['tools/lib/libcangjie-lsp.so']);
  assert.deepEqual([...sourceToolPayloads('hle')], ['tools/dtsparser', 'tools/bin/node']);
  assert.deepEqual([...sourceToolPayloads('cjcov')], []);
  assert.deepEqual([...sourceToolPayloads('cjtrace-recover')], []);
});

// Transport interfaces only: these bytes do not claim native tool builds.
for(const [platform,suffix,libraries]of [
 ['linux-x64','',['tools/lib/libcangjie-lsp.so']],
 ['linux-aarch64','',['tools/lib/libcangjie-lsp.so']],
 ['darwin-x64','',['tools/lib/libcangjie-lsp.dylib']],
 ['darwin-arm64','',['tools/lib/libcangjie-lsp.dylib']],
 ['windows-x64','.exe',['tools/bin/libcangjie-lsp.dll','tools/lib/libcangjie-lsp.dll.a']],
])for(const tool of ['cjfmt','LSPServer','cjcov','cjtrace-recover','hle','cjlint','cjprof','cjcompat'])test('A8 platform '+platform+' '+tool+' transports target payload and preserves shared config',()=>{
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'a8-platform-')),sdk=path.join(work,'source'),release=path.join(work,'release'),artifact=path.join(work,'artifact');
 const binary=path.join(sdk,'tools/bin/'+tool+suffix);
 writeExecutable(binary,'controlled '+platform+' '+tool+' bytes\n');
 writeExecutable(path.join(release,'tools/bin/'+tool+suffix),'base tool bytes\n');
 writeFile(path.join(sdk,'tools/config/cangjie-format.toml'),'target format\n');
 for(const lib of libraries)writeFile(path.join(sdk,lib),'target '+platform+' library\n');
 writeFile(path.join(sdk,'tools/dtsparser/analysis.js'),'target parser\n');hlePayloadFixture(sdk,suffix);
 writeFile(path.join(release,'tools/config/cangjie-repo.toml'),'keep cjpm repository\n');
 writeFile(path.join(release,'tools/config/other.toml'),'keep other configuration\n');
 writeFile(path.join(release,'tools/config/cangjie-format.toml'),'base format\n');
 for(const rel of sourceToolPayloads(tool,platform)) {
  if(rel==='tools/config')writeFile(path.join(sdk,rel,'cjlint_rule_list.json'),'target lint config');
  else if(rel.endsWith('/config/static'))writeFile(path.join(sdk,rel,'index.html'),'target prof config');
  else if(!fs.existsSync(path.join(sdk,rel)))writeFile(path.join(sdk,rel),'target native payload');
 }
 if(tool==='cjprof')for(const prefix of ['tools/config/static','.target-tools/tools/config/static'])writeFile(path.join(release,prefix,'legacy.html'),'previous installed page');
 if(tool!=='hle')producerFacts(sdk,tool,binary,platform);
 const dedicated=tool==='hle';
 const producer=dedicated?path.join(root,'ci/release/prepare_hle_artifact.mjs'):prepare;
 const consumer=dedicated?path.join(root,'ci/release/install_hle_artifact.mjs'):install;
 const toolArgs=dedicated?[]:['--tool',tool];
 try {
  run(producer,[...toolArgs,'--platform',platform,'--binary',binary,'--sdk',sdk,'--outdir',artifact]);
  // Move the actual artifact root before consumption.
  const moved=artifact+'-moved';fs.renameSync(artifact,moved);
  run(consumer,[...toolArgs,'--platform',platform,'--artifact',moved,'--sdk',release]);
  const results={binary:fs.readFileSync(path.join(release,'tools/bin/'+tool+suffix),'utf8'),
   format:tool==='cjfmt'?fs.readFileSync(path.join(release,'tools/config/cangjie-format.toml'),'utf8'):null,
   repo:fs.readFileSync(path.join(release,'tools/config/cangjie-repo.toml'),'utf8'),other:fs.readFileSync(path.join(release,'tools/config/other.toml'),'utf8')};
  console.log('A8_PLATFORM_TARGET_ASSERTION_REACHED',platform,tool,JSON.stringify(results));
  assert.ok(results.binary.startsWith('controlled '+platform+' '+tool+' bytes\n'));
  assert.deepEqual({repo:results.repo,other:results.other},{repo:'keep cjpm repository\n',other:'keep other configuration\n'});
  if(tool==='cjfmt')assert.equal(results.format,'target format\n');
  if(tool==='LSPServer')for(const lib of libraries)assert.equal(fs.readFileSync(path.join(release,lib),'utf8'),'target '+platform+' library\n');
  if(tool==='hle')assert.equal(fs.readFileSync(path.join(release,'tools/dtsparser/analysis.js'),'utf8'),'target parser\n');
  if(tool==='cjprof')for(const prefix of ['tools/config/static','.target-tools/tools/config/static']) {
   assert.equal(fs.existsSync(path.join(release,prefix,'legacy.html')),false,'artifact reinstall removes previous static member');
   assert.equal(fs.readFileSync(path.join(release,prefix,'index.html'),'utf8'),'target prof config');
  }
 } finally {fs.rmSync(work,{recursive:true,force:true});}
});

test('A8 workflow native callers provide their actual SDK input',()=>{
 const source=fs.readFileSync(path.join(root,'.github/workflows/srcbuild-target.yml'),'utf8');
 const calls=[...source.matchAll(/node ci\/release\/prepare_tools_artifact\.mjs \\\n((?:[^\n]*\\\n)*[^\n]*--outdir[^\n]*)/g)]
  .map(match=>match[1]).filter(text=>text.includes('${{ matrix.target }}'));
 assert.equal(calls.length,7);
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'a8-caller-')),sdk=sourceSdk(work);
 try {
  for(const call of calls){
   const expanded=call.replace(/\\\n/g,' ').replaceAll('${{ matrix.target }}','linux-x64').replaceAll('$CANGJIE_WORKSPACE',work).replaceAll('$GITHUB_WORKSPACE',work);
   const argv=[...expanded.matchAll(/"([^\"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
   const binary=argv[argv.indexOf('--binary')+1],artifact=argv[argv.indexOf('--outdir')+1];
   const targetSdk=argv.includes('--sdk')?argv[argv.indexOf('--sdk')+1]:null;
   // This is the workflow's own argument list; materialize its named inputs.
   if(targetSdk){fs.mkdirSync(path.dirname(targetSdk),{recursive:true});
   if(!fs.existsSync(targetSdk))fs.cpSync(sdk,targetSdk,{recursive:true});}
   writeExecutable(binary,'controlled caller binary\n');
   const tool=argv[argv.indexOf('--tool')+1];
   for(const rel of sourceToolPayloads(tool,'linux-x64')) {
    if(rel==='tools/config')writeFile(path.join(targetSdk,rel,'cjlint_rule_list.json'),'lint config');
    else if(rel.endsWith('/config/static'))writeFile(path.join(targetSdk,rel,'index.html'),'prof config');
    else if(!fs.existsSync(path.join(targetSdk,rel)))writeFile(path.join(targetSdk,rel),'native payload');
   }
   producerFacts(targetSdk,tool,binary);
   const rc=(()=>{try{run(prepare,argv);return 0;}catch(error){return error.status;}})();
   console.log('A8_CALLER_TARGET_ASSERTION_REACHED',JSON.stringify({argv,rc}));
   assert.equal(rc,0);
   assert.ok(fs.existsSync(path.join(artifact,'SOURCE-PROVENANCE.json')));
  }
 }finally{fs.rmSync(work,{recursive:true,force:true});}
});

test('A8 unsafe payload cannot write outside either transport root',()=>{
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'a8-root-')),sdk=sourceSdk(work),artifact=path.join(work,'artifacts/tool'),release=installedSdk(path.join(work,'installed'));
 fs.mkdirSync(path.dirname(artifact),{recursive:true});
 try{
  run(prepare,['--tool','cjfmt','--platform','linux-x64','--binary',path.join(sdk,'tools/bin/cjfmt'),'--sdk',sdk,'--outdir',artifact]);
  const sidecar=path.join(artifact,'SOURCE-PROVENANCE.json'),record=JSON.parse(fs.readFileSync(sidecar,'utf8'));
  writeFile(path.join(work,'artifacts/escape'),'outside source content');
  record.payloads.push({path:'../escape',type:'file',sha256:digest('outside source content')});fs.writeFileSync(sidecar,JSON.stringify(record));
  let rejected=false;try{run(install,['--tool','cjfmt','--platform','linux-x64','--artifact',artifact,'--sdk',release]);}catch{rejected=true;}
  const facts={rejected,unchanged:fs.readFileSync(path.join(release,'tools/bin/cjfmt'),'utf8')==='official cjfmt bytes\n',escapeAbsent:!fs.existsSync(path.join(work,'installed/escape'))};
  console.log('A8_ROOT_TARGET_ASSERTION_REACHED',JSON.stringify(facts));assert.deepEqual(facts,{rejected:true,unchanged:true,escapeAbsent:true});
 }finally{fs.rmSync(work,{recursive:true,force:true});}
});
test('A8 hle producer refuses a parser directory without runtime dependencies',()=>{
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'a8-hle-missing-')),sdk=path.join(work,'sdk');
 writeExecutable(path.join(sdk,'tools/bin/hle'),'controlled hle');writeExecutable(path.join(sdk,'tools/bin/node'),'controlled node');writeFile(path.join(sdk,'tools/dtsparser/analysis.js'),'parser alone');
 let rejected=false;try{run(path.join(root,'ci/release/prepare_hle_artifact.mjs'),['--platform','linux-x64','--binary',path.join(sdk,'tools/bin/hle'),'--sdk',sdk,'--outdir',path.join(work,'artifact')]);}catch{rejected=true;}
 console.log('A8_HLE_CLOSURE_TARGET_ASSERTION_REACHED',rejected);assert.equal(rejected,true);
 fs.rmSync(work,{recursive:true,force:true});
});
test('A8 independent dependency producer returns installed parser and target dependency facts',async()=>{
 const {installHleDependencies}=await import('../srcbuild/hle-dependencies.mjs');
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'a8-dependency-producer-')),sdk=path.join(work,'sdk'),tools=path.join(work,'tools'),dependencies=path.join(work,'deps');
 hlePayloadFixture(dependencies);
 writeFile(path.join(tools,'hyperlangExtension/src/dtsparser/analysis.js'),'fixed parser boundary');
 writeFile(path.join(tools,'hyperlangExtension/src/dtsparser/package.json'),JSON.stringify({dependencies:{typescript:'npm:typescript@4.9.5','https-proxy-agent':'7.0.6'}}));
 const input={platform:'linux_x86_64',node:{path:'/bin/true',source:'controlled ELF boundary',version:'fixture'},modules:{path:path.join(dependencies,'tools/dtsparser/node_modules'),source:'controlled module tree',version:'fixture'},cjbind:{path:'/bin/true',source:'controlled ELF boundary, not actual cjbind',version:'v1.1.0-alpha.53.1'}};
 try{
  const facts=await installHleDependencies({toolsRoot:tools,sdk,platform:'linux_x86_64',input});
  const actual={parser:fs.existsSync(path.join(sdk,'tools/dtsparser/analysis.js'))?fs.readFileSync(path.join(sdk,'tools/dtsparser/analysis.js'),'utf8'):null,platform:facts.platform,node:fs.existsSync(path.join(sdk,'tools/bin/node'))?digest(fs.readFileSync(path.join(sdk,'tools/bin/node'))):null,cjbind:fs.existsSync(path.join(sdk,'tools/dtsparser/node_modules/.bin/cjbind'))?digest(fs.readFileSync(path.join(sdk,'tools/dtsparser/node_modules/.bin/cjbind'))):null};
  console.log('A8_DEPENDENCY_PRODUCER_TARGET_ASSERTION_REACHED',JSON.stringify(actual));assert.deepEqual(actual,{parser:'fixed parser boundary',platform:'linux_x86_64',node:digest(fs.readFileSync('/bin/true')),cjbind:digest(fs.readFileSync('/bin/true'))});
 }finally{fs.rmSync(work,{recursive:true,force:true});}
});


test('component producer preserves older recorded source and rejects an unrecorded body',()=>{
 const work=fs.mkdtempSync(path.join(os.tmpdir(),'tool-original-source-')),sdk=sourceSdk(work),artifact=path.join(work,'artifact');
 const binary=path.join(sdk,'tools/bin/cjfmt'),original={status:'resolved',repository:'fixture://original-tools',commit:'e'.repeat(40)};
 try {
  producerFacts(sdk,'cjfmt',binary,'linux-x64',original);
  run(prepare,['--tool','cjfmt','--platform','linux-x64','--binary',binary,'--sdk',sdk,'--outdir',artifact]);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(artifact,'SOURCE-PROVENANCE.json'),'utf8')).source,original);
  const before=fs.readFileSync(binary);fs.appendFileSync(binary,'changed');
  assert.throws(()=>run(prepare,['--tool','cjfmt','--platform','linux-x64','--binary',binary,'--sdk',sdk,'--outdir',artifact]),/SOURCE_TOOL_ARTIFACT_BYTES/);
  fs.writeFileSync(binary,before);run(prepare,['--tool','cjfmt','--platform','linux-x64','--binary',binary,'--sdk',sdk,'--outdir',artifact]);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(artifact,'SOURCE-PROVENANCE.json'),'utf8')).source,original);
 }finally{fs.rmSync(work,{recursive:true,force:true});}
});
