#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';

// The target chooses the format; only the executing host chooses the utility.
export function zipCommand(operation,archive,directory,host=process.platform,env=process.env) {
  if(host==='win32') {
    const system=env.SystemRoot||env.SYSTEMROOT;
    if(!system||!path.win32.isAbsolute(system))throw Error('ZIP_SYSTEMROOT_REQUIRED');
    const exe=path.win32.join(system,'System32','tar.exe');
    return operation==='create'?[exe,'--format','zip','-cf',archive,'--',directory]:[exe,'-xf',archive,'-C',directory];
  }
  return operation==='create'?['zip','-qyr',archive,directory]:['unzip','-q',archive,'-d',directory];
}
export async function checkArchiveFormat(archive,format) {
  const file=await fs.open(archive,'r');
  try {
    const prefix=Buffer.alloc(4);await file.read(prefix,0,4,0);
    if(format==='zip') {
      // The SDK is never empty. Check the local header AND a real ZIP end
      // record, including a possible comment, before a format-sniffing reader.
      const size=(await file.stat()).size,tail=Buffer.alloc(Math.min(65557,size));
      await file.read(tail,0,tail.length,size-tail.length);
      if(prefix.readUInt32LE()===0x04034b50)for(let i=tail.length-22;i>=0;i--)
        if(tail.readUInt32LE(i)===0x06054b50&&i+22+tail.readUInt16LE(i+20)===tail.length&&tail.readUInt16LE(i+10)>0)return;
    } else if(format==='tar.gz'&&prefix[0]===31&&prefix[1]===139&&prefix[2]===8)return;
    throw Error('NATIVE_SDK_ARCHIVE_FORMAT '+format);
  } finally {await file.close();}
}
