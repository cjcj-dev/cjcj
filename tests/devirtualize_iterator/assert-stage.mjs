#!/usr/bin/env zx
import fs from 'node:fs';
const [dump,kind]=process.argv.slice(2);
const text=fs.readFileSync(dump,'utf8');
function body(name){
 const marker='srcCodeIdentifier: '+name+',';
 const start=text.indexOf(marker);if(start<0)throw Error('missing function '+name);
 const end=text.indexOf('\n}',start);if(end<0)throw Error('missing body '+name);
 return text.slice(start,end);
}
const rows=[];
function check(name,ok){rows.push({name,executed:true,ok});}
if(kind==='matrix'){
 const work=body('work');
 check('work_has_checksum_next',work.includes('4nextH')&&work.includes('"matrix_multiply.cj"-13-10'));
 check('checksum_next_devirtualized',!/\b(?:Try)?Invoke\([^\n]*4nextHv/.test(work));
 check('concrete_next_consumed',/\b(?:Try)?Apply\([^\n]*(?:4nextHv|4nextH)/.test(work));
}else if(kind==='declared'){
 for(const name of ['closedCall','throwingCall']){
  const f=body(name);check(name+'_direct_value',/\b(?:Try)?Apply\([^\n]*5valueHv/.test(f));
  check(name+'_no_virtual_value',!/\b(?:Try)?Invoke\([^\n]*5valueHv/.test(f));
 }
 check('open_receiver_stays_virtual',/\b(?:Try)?Invoke\([^\n]*5valueHv/.test(body('openCall')));
}else throw Error('unknown kind');
console.log(JSON.stringify({dump,kind,assertions:rows},null,2));
process.exit(rows.every(x=>x.ok)?0:1);
