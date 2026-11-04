#!/usr/bin/env zx
// C12 real common/specific CJO round-trip, old-layout and malformed-slot controls.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [compiler, legacyCompiler, output] = process.argv.slice(2);
for (const p of [compiler, legacyCompiler, output]) assert(path.isAbsolute(p));
fs.mkdirSync(output, {recursive: true});
function dir(name) { const p = path.join(output, name); fs.mkdirSync(p, {recursive: true}); return p; }
function src(name, content) { const p = path.join(output, name); fs.mkdirSync(path.dirname(p), {recursive: true}); fs.writeFileSync(p, content); return p; }
function run(name, executable, args, expected = 0) {
  const argv = [executable, ...args, '--jobs', '8'];
  const start = new Date().toISOString();
  const r = spawnSync(argv[0], argv.slice(1), {cwd: output, encoding: 'utf8'});
  fs.writeFileSync(path.join(output, name + '.log'), (r.stdout ?? '') + (r.stderr ?? ''));
  fs.writeFileSync(path.join(output, name + '.json'), JSON.stringify({argv, rc:r.status, signal:r.signal, error:r.error?.message, start, end:new Date().toISOString()}, null, 2));
  assert.equal(r.status, expected, name + ': ' + r.stderr); return (r.stdout ?? '') + (r.stderr ?? '');
}
function imports(cjo) {
  const b = fs.readFileSync(cjo); assert.equal(b.toString('ascii', 4, 8), 'CJOF');
  const root = b.readUInt32LE(0);
  function field(t, n) { const vt = t - b.readInt32LE(t); const o = 4 + 2*n; return o < b.readUInt16LE(vt) ? b.readUInt16LE(vt+o) : 0; }
  function ptr(t, n) { const f = field(t,n); return f ? t+f+b.readUInt32LE(t+f) : 0; }
  function vector(v) { return v ? Array.from({length:b.readUInt32LE(v)}, (_,i) => {const p=v+4+i*4; return p+b.readUInt32LE(p);}) : []; }
  function str(t,n) { const p=ptr(t,n); return p ? b.toString('utf8',p+4,p+4+b.readUInt32LE(p)) : ''; }
  const versionOffset = root + field(root,1);
  const rows = vector(ptr(root,6)).flatMap(file => vector(ptr(file,0)).map(t => {
    const slot = field(t,9);
    return {table:t, vtable:t-b.readInt32LE(t), slotPosition:t-b.readInt32LE(t)+22, fieldPosition:slot?t+slot:null, identifier:str(t,3), prefixes:vector(ptr(t,2)).map(p=>b.toString('utf8',p+4,p+4+b.readUInt32LE(p))), slotPresent:slot!==0, implicit:slot!==0 && b.readUInt8(t+slot)!==0};
  }));
  return {version:Array.from(b.subarray(versionOffset,versionOffset+3)), rows};
}
const targets=[];
function check(name, body) { try {body(); targets.push({name,passed:true});console.log('PASS '+name);} catch(e){targets.push({name,passed:false,error:e.message});console.log('FAIL '+name+': '+e.message);} }
for (const [origin, producer] of [['current', compiler], ['legacy-f3', legacyCompiler]]) {
  for (const explicit of [false,true]) {
    const tag=origin+(explicit?'-explicit':'-implicit');
    const common=src(tag+'/common.cj','package implicitfixture\n'+(explicit?'import std.core.*\n':'')+'public common func answer(): Int64\n');
    const commonout=dir(tag+'/commonout');
    run(tag+'-common',producer,[common,'--experimental','--output-type=chir','-o',commonout+'/']);
    const wire=imports(commonout+'/implicitfixture.cjo');
    if (origin === 'current' && !explicit) {
      const cjo = commonout+'/implicitfixture.cjo';
      const marked = wire.rows.find(r=>r.implicit);
      assert(marked, 'real producer must serialize an implicit import');
      for (const kind of ['outside-buffer','outside-object','invalid-bool']) {
        const bytes = fs.readFileSync(cjo);
        if (kind === 'invalid-bool') bytes[marked.fieldPosition] = 2;
        else bytes.writeUInt16LE(kind === 'outside-buffer' ? 65535 : bytes.readUInt16LE(marked.vtable+2), marked.slotPosition);
        const bad = path.join(output, tag+'-'+kind+'.cjo'); fs.writeFileSync(bad,bytes);
        // Existing native schema can still read the unchanged metadata. This
        // control proves the new-slot rejection comes from the added consumer.
        run(tag+'-'+kind+'-old-native',legacyCompiler,[bad,'--scan-dependency']);
        check(kind+'-public-rejection',()=>{ const rejection = run(tag+'-'+kind+'-reject',compiler,[bad,'--scan-dependency'],1); assert.match(rejection,/failed|incompatible|validation/); assert.doesNotMatch(rejection,/Exception/); });
      }
    }
    fs.writeFileSync(path.join(output,tag+'-wire.json'),JSON.stringify(wire,null,2));
    check(tag+'-wire-field',()=>{
      if(origin==='legacy-f3') { assert(wire.rows.every(r=>!r.slotPresent)); assert.deepEqual(wire.version,[1,1,0]); }
      else { assert(wire.rows.some(r=>r.implicit)); assert.deepEqual(wire.version,[1,1,1]); }
      if(explicit)assert(wire.rows.some(r=>r.prefixes.join('.')==='std.core'&&!r.implicit));
    });
    const specific=src(tag+'/specific.cj','package implicitfixture\npublic specific func answer(): Int64 { 42 }\n');
    const specificout=dir(tag+'/specificout');
    run(tag+'-specific',compiler,[specific,'--experimental','--output-type=chir','--common-part-cjo',commonout+'/implicitfixture.cjo','--common-part-chir',commonout+'/implicitfixture.chir','-o',specificout+'/']);
    const scan=JSON.parse(run(tag+'-scan',compiler,[specificout+'/implicitfixture.cjo','--scan-dependency']).trim());
    check(tag+'-real-metadata',()=>{
      const core=scan.dependencies.find(d=>d.package==='std.core');
      // An old producer cannot encode IMPLICIT_ADD: absent field intentionally
      // decodes false, so its historical implicit import is retained.
      assert.equal(Boolean(core),explicit||origin==='legacy-f3');
    });
  }
}
const ordinary=src('ordinary/lib.cj','package ordinaryc12\npublic func answer(): Int64 { 42 }\n');
const ordinaryout=dir('ordinary/out');
run('ordinary-producer',compiler,[ordinary,'--output-type=staticlib','-o',ordinaryout+'/']);
const use=src('ordinary/use.cj','package ordinaryuse\nimport ordinaryc12.answer\npublic func use(): Int64 { answer() }\n');
for(const [tag,consumer]of [['current',compiler],['legacy-f3',legacyCompiler]]){
  run('ordinary-'+tag,consumer,[use,'--experimental','--output-type=chir','--import-path',ordinaryout,'-o',dir('ordinary/'+tag)+'/']);
  check('ordinary-'+tag+'-consume',()=>{});
}
fs.writeFileSync(path.join(output,'targets.json'),JSON.stringify(targets,null,2));
process.exit(targets.every(t=>t.passed)?0:1);
