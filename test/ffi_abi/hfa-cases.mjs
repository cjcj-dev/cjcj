#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const [source, output] = process.argv.slice(2);
const code = fs.readFileSync(path.join(source, 'packages/codegen/src/CGCFFI.cj'), 'utf8');
const arm = code.slice(code.indexOf('public open class LinuxAarch64CJNativeCGCFFI'), code.indexOf('@When[os == "macOS"]'));
const limit = Number(arm.match(/membersBox.value <= (\d+)u64/)[1]);
assert.equal(limit, 4);
const f = {name:'Float32', c:'float', size:4, init:'1.0f32', value:'1.0f'},
    d = {name:'Float64', c:'double', size:8, init:'2.0f64', value:'2.0'},
    u = {name:'UInt32', c:'unsigned int', size:4, init:'3u32', value:'3'};
const array = (element, count) => ({element, count, name:`VArray<${element.name}, $${count}>`,
    size:element.size*count, align:element.align||element.size,
    init:'['+Array(count).fill(element.init).join(', ')+']'});
const types=[];
function record(name, elements, {packed=false, align=0, group='target'}={}) {
    const fields=elements.map((type,i)=>({name:'f'+i,type}));
    let size=0, natural=1;
    for(const {type} of fields){const a=packed?1:(type.align||type.size||1);natural=Math.max(natural,a);size=Math.ceil(size/a)*a+type.size;}
    const alignment=Math.max(natural,align);size=Math.ceil(size/alignment)*alignment;
    const type={name,c:name,fields,packed,align:alignment,requestedAlign:align,size,init:name+'()',group};
    types.push(type);return type;
}
// Every permutation of the legal floating fundamental types through the HFA
// member limit, including homogeneous controls and the first excess count.
for(let n=1;n<=limit;++n)for(let mask=0;mask<(1<<n);++mask)
    record('Seq'+n+'_'+mask,Array.from({length:n},(_,i)=>mask&(1<<i)?d:f),{group:mask===0||mask===(1<<n)-1?'control':'target'});
for(const t of [f,d]){
    const tag=t===f?'F':'D';
    record('Excess'+tag,Array(limit+1).fill(t),{group:'control'});
    for(let n=1;n<=limit+1;++n)record('Array'+tag+n,[array(t,n)]);
    const pair=record('Pair'+tag,[t,t],{group:'control'});
    record('Nested'+tag,[pair,pair]);
    record('ArrayStruct'+tag,[array(pair,2)]);
    record('ArrayArray'+tag,[array(array(t,2),2)]);
    record('ArrayPlus'+tag,[array(t,3),t]);
    record('NestedExcess'+tag,[array(pair,2),t],{group:'control'});
    record('Packed'+tag,[array(t,2)],{packed:true});
    record('AlignedExact'+tag,[array(t,2)],{align:2*t.size});
    record('AlignedTail'+tag,[t],{align:4*t.size,group:'control'});
    const aligned=record('AlignedElement'+tag,[t,t],{align:2*t.size});
    record('AlignedArray'+tag,[array(aligned,2)]);
    record('Integer'+tag,[t,u],{group:'control'});
    const mixed=record('MixedInner'+tag,[t,t===f?d:f]);
    record('MixedArray'+tag,[array(mixed,2)]);
    record('MixedNested'+tag,[pair,mixed]);
}
const empty=record('Empty',[],{group:'control'});
record('EmptyFloat',[empty,f,empty]);
record('EmptyArray',[array(empty,2),d]);
function declaration(t,name){return t.element?declaration(t.element,name+'['+t.count+']'):t.c+' '+name;}
function leaves(t,prefix){return t.element?Array.from({length:t.count},(_,i)=>leaves(t.element,prefix+'['+i+']')).flat():
    t.fields?t.fields.flatMap(x=>leaves(x.type,prefix+'.'+x.name)):[{path:prefix,type:t}];}
let cj='',c='';
for(const t of types){
    cj+=`@C${t.packed?'[packed]':t.requestedAlign?'[align: '+t.requestedAlign+']':''}\nstruct ${t.name} { ${t.fields.map(x=>'var '+x.name+': '+x.type.name+' = '+x.type.init).join('; ')} }\n`;
    c+=`typedef struct ${t.packed?'__attribute__((packed))':t.requestedAlign?'__attribute__((aligned('+t.requestedAlign+')))':''} { ${t.fields.map(x=>declaration(x.type,x.name)+';').join(' ')} } ${t.name};\n_Static_assert(sizeof(${t.name})==${t.size}, "${t.name} layout");\n`;
}
cj+='foreign {\n'+types.map(t=>`func c_echo_${t.name}(p: ${t.name}): ${t.name}`).join('\n')+'\n}\n';
for(const t of types){
    cj+=`@C\nfunc cj_ret_${t.name}(): ${t.name} { return ${t.name}() }\n@C\nfunc cj_echo_${t.name}(p: ${t.name}): ${t.name} { return p }\n@C\nfunc cj_call_${t.name}(p: ${t.name}): ${t.name} { unsafe { return c_echo_${t.name}(p) } }\n`;
    const checks=leaves(t,'p').map(x=>x.path+' == '+x.type.init).join(' && ')||'true';
    cj+=`@C\nfunc cj_values_${t.name}(p: ${t.name}): Bool { return ${checks} }\n`;
    const check=v=>leaves(t,v).map(x=>x.path+' == '+x.type.value).join(' && ')||'1';
    c+=`${t.name} c_echo_${t.name}(${t.name} p) { return p; }\nextern ${t.name} cj_ret_${t.name}(void);\nextern ${t.name} cj_echo_${t.name}(${t.name});\nextern ${t.name} cj_call_${t.name}(${t.name});\nextern _Bool cj_values_${t.name}(${t.name});\nint test_${t.name}(void) { ${t.name} a=cj_ret_${t.name}(); if(!(${check('a')})) return 1; ${t.name} b=cj_echo_${t.name}(a); if(!(${check('b')})) return 2; ${t.name} d=cj_call_${t.name}(b); return !(${check('d')}) || !cj_values_${t.name}(d); }\n`;
}
c+='int main(void) {\n'+types.map(t=>`if(test_${t.name}()) return 1;`).join('\n')+'\nreturn 0; }\n';
fs.mkdirSync(output);
fs.writeFileSync(path.join(output,'hfa.cj'),cj);fs.writeFileSync(path.join(output,'hfa.c'),c);
fs.writeFileSync(path.join(output,'cases.json'),JSON.stringify({limit,types},null,2));
for(const group of ['target','control'])fs.writeFileSync(path.join(output,group+'.txt'),types.filter(t=>t.group===group).map(t=>t.name).join('\n')+'\n');
console.log(`generated ${types.length} layouts; target=${types.filter(t=>t.group==='target').length}, control=${types.filter(t=>t.group==='control').length}`);
