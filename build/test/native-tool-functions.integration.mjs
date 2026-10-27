// Real independent tools, using a read-only, explicitly selected SDK for AST/CJO
// dependencies. This is not a complete SDK or a new compiler/std qualification.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {cleanSdkEnvironment} from '../../ci/bootstrap/sdk-platform.mjs';
const [prefix,sdk,source,work,names='cjfmt,lsp,cjlint,cjprof,cjcompat']=process.argv.slice(2);
const selected=new Set(names.split(','));
assert(selected.size && [...selected].every(name=>['cjfmt','lsp','cjlint','cjprof','cjcompat','cjtrace-recover'].includes(name)),'known tool selection required');
for(const value of [prefix,sdk,source,work])assert(value&&path.isAbsolute(value),'absolute prefix/sdk/source/work required');
assert.equal(process.platform,'linux');
fs.mkdirSync(work);
const env=cleanSdkEnvironment(sdk,'linux_x86_64');
// An independently installed frontend component belongs to this tool prefix,
// not to the read-only compiler SDK. The loader evidence below records which
// library each executable actually selects, installed and unpacked alike.
env.LD_LIBRARY_PATH=prefix+'/tools/lib:'+env.LD_LIBRARY_PATH;
const commands=[],groups=[],checks=[];
function run(name,argv,{cwd=work,library,expected=0,environment={}}={}) {
 const started=new Date().toISOString(),selected={...env,...(library?{LD_LIBRARY_PATH:library+':'+env.LD_LIBRARY_PATH}:{}),...environment};
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env:selected,encoding:'utf8',maxBuffer:16*1024*1024,timeout:120000});
 fs.writeFileSync(work+'/'+name+'.stdout',r.stdout??'');fs.writeFileSync(work+'/'+name+'.stderr',r.stderr??'');
 commands.push({name,argv,cwd,env:selected,started,ended:new Date().toISOString(),rc:r.status,signal:r.signal,error:r.error?.message??null});
 fs.writeFileSync(work+'/commands.json',JSON.stringify(commands,null,2));
 if(expected!==null)assert.equal(r.status,expected,name);return r;
}
function check(name,fn){try{fn();checks.push({name,pass:true});}catch(e){checks.push({name,pass:false,error:String(e)});throw e;}finally{fs.writeFileSync(work+'/checks.json',JSON.stringify(checks,null,2));}}
async function group(name,fn){if(!selected.has(name)){groups.push({name,status:'NOT_RUN',reason:'not selected'});return;}try{await fn();groups.push({name,rc:0});}catch(e){groups.push({name,rc:1,error:e.stack});}fs.writeFileSync(work+'/groups.json',JSON.stringify(groups,null,2));}
const binary=name=>prefix+'/'+name+'/bin/'+(name==='lsp'?'LSPServer':name);
// Exercise source-language receiver results, inheritance and generic results.
// These declarations also enter actual major-1 CJO files in cjcompat below.
const receiverDeclarations=`
public open class ReceiverBase {
 public let value: Int64
 public init(value: Int64) { this.value = value }
 public func read(): Int64 { value }
}
public class ReceiverDerived <: ReceiverBase {
 public init(value: Int64) { super(value + 2) }
}
public class ReceiverBox<T> {
 public let payload: T
 public init(payload: T) { this.payload = payload }
 public func read(): T { payload }
}
public func receiverResult(): Int64 {
 let receiver = ReceiverDerived(40)
 let box = ReceiverBox<Int64>(receiver.read())
 return box.read()
}
`;
for(const name of selected)run(name+'-loader',['ldd',binary(name)],{library:prefix+'/'+name+'/lib'});
await group('cjfmt',()=>{
 const input=work+'/format.cj',output=work+'/formatted.cj',again=work+'/again.cj';
 fs.writeFileSync(input,'// header\nmain(){\nlet value=7 // inline\nprintln(value)\n}\n');
 run('fmt',[binary('cjfmt'),'-f',input,'-o',output,'-c',prefix+'/cjfmt/config/cangjie-format.toml']);
 check('format changes whitespace and preserves comments',()=>{const text=fs.readFileSync(output,'utf8');assert.notEqual(text,fs.readFileSync(input,'utf8'));assert.match(text,/\/\/ header/);assert.match(text,/\/\/ inline/);});
 run('fmt-compile',[sdk+'/bin/cjc',output,'-o',work+'/formatted-program']);
 check('formatted program semantics',()=>assert.equal(run('fmt-run',[work+'/formatted-program']).stdout.trim(),'7'));
 run('fmt-again',[binary('cjfmt'),'-f',output,'-o',again,'-c',prefix+'/cjfmt/config/cangjie-format.toml']);
 check('format idempotence',()=>assert.equal(fs.readFileSync(again,'utf8'),fs.readFileSync(output,'utf8')));
});
await group('lsp',()=>{
 const project=work+'/lsp-project';fs.cpSync(source+'/cangjie-language-server/test/public/fixtures/ordinary',project,{recursive:true});
 const receiverFile=project+'/src/receiver.cj';
 fs.writeFileSync(receiverFile,'package probe\n'+receiverDeclarations);
 fs.writeFileSync(work+'/receiver-reference.cj',receiverDeclarations+'\nmain() { println(receiverResult()) }\n');
 run('receiver-reference-compile',[sdk+'/bin/cjc',work+'/receiver-reference.cj','-o',work+'/receiver-reference']);
 check('actual producer constructor result',()=>assert.equal(run('receiver-reference-run',[work+'/receiver-reference']).stdout.trim(),'42'));
 // Preserve the ordinary source control, then exercise imported declarations
 // through the existing public CJO protocol consumer. A source symbol alone
 // does not establish that the selected SDK's CJO files were accepted.
 const selections=[];
 for(const [consumer,mode]of [['source-control','explicit'],['cjo-searchpath','default'],['cjo-searchpath','explicit']]) {
  const file=source+'/cangjie-language-server/test/public/'+consumer+'.mjs';
  const original=fs.readFileSync(file,'utf8'),expression="join(sdk, 'tools/bin/LSPServer')";
  assert.equal(original.split(expression).length-1,2);
  const tag='lsp-'+consumer+'-'+mode,script=work+'/'+tag+'.mjs',evidence=work+'/'+tag;
  const libraryExpression="join(sdk, 'tools/lib')";
  assert.equal(original.split(libraryExpression).length-1,1);
  const semanticAnchor='  result.assertionExecuted = true;';
  assert.equal(original.split(semanticAnchor).length-1,1);
  const semanticRequests=`  result.receiverClass = await request('workspace/symbol', { query: 'ReceiverDerived' });
  result.genericClass = await request('workspace/symbol', { query: 'ReceiverBox' });
  result.receiverFunction = await request('workspace/symbol', { query: 'receiverResult' });
`;
  fs.writeFileSync(script,original.replaceAll(expression,JSON.stringify(binary('lsp')))
   .replace(libraryExpression,JSON.stringify(prefix+'/tools/lib'))
   .replace(semanticAnchor,semanticRequests+semanticAnchor));
  selections.push({source:file,mode,replacement:{from:expression,to:binary('lsp')},
   frontendLibrary:prefix+'/tools/lib',assertions:'unchanged'});
  fs.writeFileSync(work+'/lsp-consumer-selection.json',JSON.stringify(selections,null,2));
  const result=run(tag,[process.execPath,script,sdk,project,evidence,mode,'memory'],{expected:null});
  check('LSP '+consumer+' '+mode,()=>{
   const r=JSON.parse(fs.readFileSync(evidence+'/result.json'));
   assert.equal(r.assertionExecuted,true);assert.equal(r.controlPass,true);
   if(consumer==='cjo-searchpath')assert.equal(r.targetPass,true,'imported std.ast.FuncDecl required');
   for(const [field,name,kind]of [['receiverClass','ReceiverDerived',5],['genericClass','ReceiverBox',5],['receiverFunction','receiverResult',12]])
    assert(r[field]?.some(item=>item.name.startsWith(name)&&item.kind===kind),'semantic receiver/generic symbol '+name);
   const protocol=JSON.parse(fs.readFileSync(evidence+'/protocol.json'));
   const incompatible=protocol.filter(x=>x.method==='textDocument/checkHealthy'&&/\bis incompatible\b/.test(x.params?.message??''));
   assert.equal(incompatible.length,0,'selected SDK CJO incompatibility diagnostics');
   assert.equal(r.process.code,0);assert.equal(result.status,0);
  });
 }
});
await group('cjlint',()=>{
 for(const [arm,decl]of [['mutable','var'],['immutable','let']]) {
  const dir=work+'/lint-'+arm;fs.mkdirSync(dir);fs.writeFileSync(dir+'/main.cj','main(): Int64 {\n    '+decl+' value: Int64 = 42\n    return value\n}\n');
  run('lint-'+arm+'-compile',[sdk+'/bin/cjc',dir+'/main.cj','-o',dir+'/program']);
  const output=work+'/lint-'+arm+'-report';run('lint-'+arm,[binary('cjlint'),'-f',dir,'-c',prefix+'/cjlint','-m',sdk,'-o',output,'-r','json'],{library:prefix+'/cjlint/lib'});
  check('lint G.VAR.01 '+arm,()=>{const report=JSON.parse(fs.readFileSync(output+'.json'));assert(Array.isArray(report));assert.equal(report.some(x=>x.description?.includes('G.VAR.01')&&x.description.includes("'value'")),arm==='mutable');});
 }
 for(const [arm,decl]of [['mutable','var'],['immutable','let']]) {
  const dir=work+'/lint-receiver-'+arm;fs.mkdirSync(dir);
  fs.writeFileSync(dir+'/main.cj',receiverDeclarations+'\nmain(): Int64 {\n '+decl+' value = receiverResult()\n println(value)\n return 0\n}\n');
  run('lint-receiver-'+arm+'-compile',[sdk+'/bin/cjc',dir+'/main.cj','-o',dir+'/program']);
  check('receiver program '+arm,()=>assert.equal(run('lint-receiver-'+arm+'-run',[dir+'/program']).stdout.trim(),'42'));
  const output=work+'/lint-receiver-'+arm+'-report';
  run('lint-receiver-'+arm,[binary('cjlint'),'-f',dir,'-c',prefix+'/cjlint','-m',sdk,'-o',output,'-r','json'],{library:prefix+'/cjlint/lib'});
  check('lint receiver result G.VAR.01 '+arm,()=>{
   const report=JSON.parse(fs.readFileSync(output+'.json'));assert(Array.isArray(report));
   assert.equal(report.some(x=>x.description?.includes('G.VAR.01')&&x.description.includes("'value'")),arm==='mutable');
  });
 }
});
await group('cjprof',()=>{
 for(const [name,expected]of [['heap',/default::Dirived\s+1\s+72\s+168/],['heap_multi_ref',/std.core::Future<Unit>\s+1\s+168\s+728/]]) {
  const input=work+'/'+name+'.data';fs.copyFileSync(source+'/cjprof/tests/'+name+'.data',input);
  const result=run('prof-'+name,[binary('cjprof'),'heap','-i',input],{library:prefix+'/cjprof/lib'});
  check('prof actual retained heap '+name,()=>assert.match(result.stdout,expected));
 }
 const facts=JSON.parse(fs.readFileSync(prefix+'/cjprof/build-facts.json'));
 assert.equal(facts.language,'Cangjie');assert.equal(facts.sdk,sdk,'selected compiler/runtime host');
 const jdk=facts.jdk,jar=prefix+'/cjprof/share/java/cjprof.jar';assert(path.isAbsolute(jdk));
 fs.writeFileSync(work+'/PublicProf.java',`import com.cjprof.jni.Cjprof;
public class PublicProf {
 public static void main(String[] a) throws Exception {
  Cjprof.initialize();
  if (!Cjprof.parseHeapSnapshotFiles(java.util.Arrays.asList(a[0]))) throw new AssertionError("parse");
  if (Cjprof.queryAllHeapSnapshot().size()!=1) throw new AssertionError("snapshot count");
  long id=Cjprof.getSnapshotIDByFilePath(a[0]);
  if (Cjprof.getConstructorNodesBySnapshotID(id).isEmpty()) throw new AssertionError("constructors");
  System.out.println("CJPROF_PUBLIC_JAVA_HEAP_PASS");
  System.out.print(java.nio.file.Files.readString(java.nio.file.Path.of("/proc/self/maps")));
 }
}\n`);
 run('prof-java-compile',[jdk+'/bin/javac','-cp',jar,work+'/PublicProf.java']);
 const result=run('prof-java-run',[jdk+'/bin/java','-Xcheck:jni','-Djava.library.path='+prefix+'/cjprof/lib','-cp',work+':'+jar,'PublicProf',work+'/heap.data'],
  {library:prefix+'/cjprof/lib',environment:{LD_PRELOAD:jdk+'/lib/libjsig.so'}});
 check('prof Java parsed installed CJ implementation',()=>{
  assert.match(result.stdout,/CJPROF_PUBLIC_JAVA_HEAP_PASS/);
  for(const lib of ['libcjprof-cangjie.so','libcjprof-jni.so'])assert(result.stdout.includes(prefix+'/cjprof/lib/'+lib));
  assert(result.stdout.includes(sdk+'/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'));
  assert(result.stdout.includes(jdk+'/lib/libjsig.so'));
 });
});
await group('cjcompat',()=>{
 for(const [name,body]of Object.entries({old:'public func retained(): Int64 { 1 }\npublic func removed(): Int64 { 2 }\n',same:'public func retained(): Int64 { 1 }\npublic func removed(): Int64 { 2 }\n',deleted:'public func retained(): Int64 { 1 }\n'})) {
  const dir=work+'/compat-'+name;fs.mkdirSync(dir);fs.writeFileSync(dir+'/lib.cj','package compat_fixture\n'+receiverDeclarations+body);
  run('compat-cjo-'+name,[sdk+'/bin/cjc','lib.cj','--output-type=staticlib','-o','libcompat_fixture.a'],{cwd:dir});
 }
 for(const mode of [[],['--api'],['--abi']])for(const name of ['same','deleted']) {
  const tag=mode[0]?.slice(2)||'default';const r=run('compat-'+name+'-'+tag,[binary('cjcompat'),'--old',work+'/compat-old/compat_fixture.cjo','--new',work+'/compat-'+name+'/compat_fixture.cjo',...mode]);
  check('compat '+name+' '+tag,()=>{assert.match(r.stdout,name==='same'?/^Compatible!\s*$/m:/^Incompatible!$/m);if(name==='deleted')assert(r.stdout.includes('Function declaration visible outside the module deleted or made private.'));});
 }
});
await group('cjtrace-recover',()=>{
 const file=work+'/trace-source.cj';fs.writeFileSync(file,'func ordinaryControl(): Int64 { 7 }\nmain() { println(ordinaryControl()) }\n');
 run('trace-source-compile',[sdk+'/bin/cjc',file,'-o',work+'/trace-program']);
 check('trace source program',()=>assert.equal(run('trace-source-run',[work+'/trace-program']).stdout.trim(),'7'));
 const symbols=run('trace-symbols',['nm','--defined-only',work+'/trace-program']).stdout;
 const symbol=symbols.split('\n').map(s=>s.trim().split(/\s+/).at(-1)).find(s=>s?.startsWith('_CN')&&s.includes('ordinaryControl')&&!s.includes('$'));
 assert(symbol,'actual compiler symbol required');
 fs.writeFileSync(work+'/trace.map',symbol+' target original.cj\n');fs.writeFileSync(work+'/trace.txt','Exception: probe\n    at target(SOURCE:17)\n');
 const output=run('trace-recovery',[binary('cjtrace-recover'),'-m',work+'/trace.map','-f',work+'/trace.txt']).stdout;
 check('trace actual recovered symbol and source',()=>assert(output.split('\n').includes('    at default.ordinaryControl()(original.cj:17)')));
});
fs.writeFileSync(work+'/result.json' ,JSON.stringify({prefix,sdk,source,selected:[...selected],groups,scope:'selected independent tools; external selected SDK AST/CJO dependencies; no full SDK/Stage2'},null,2));
process.exitCode=groups.some(g=>g.rc!==undefined&&g.rc!==0)?1:0;
