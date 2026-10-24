#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
export function hlePayloadFixture(root,suffix='') {
 const write=(relative,contents)=>{const file=path.join(root,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,contents);};
 write('tools/bin/node'+suffix,'controlled node payload\n');
 write('tools/dtsparser/node_modules/.bin/cjbind'+suffix,'controlled cjbind boundary\n');
 for(const [name,version]of [['typescript','4.9.5'],['https-proxy-agent','7.0.6']]) {
  write('tools/dtsparser/node_modules/'+name+'/package.json',JSON.stringify({name,version,main:'index.js'}));
  write('tools/dtsparser/node_modules/'+name+'/index.js','controlled dependency module\n');
 }
}
