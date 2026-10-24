// Existing native entry provides separate H and target loaders at exec time.
// Entry files contain only relative execution paths; they are not certificates.
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectBuildJobs} from '../build-resources.mjs';
import {fileURLToPath} from 'node:url';
import {command, relative, privateRoot} from './sdk-flow.mjs';
import {entryPlatformName, sdkPlatform} from './sdk-platform.mjs';

// Decode the executable header itself; no undeclared `file` subprocess.
export async function assertLauncherFormat({binary, native, platform}) {
  const bytes=await fs.readFile(binary);
  let os,arch;
  if(bytes.length>=64 && bytes.subarray(0,4).equals(Buffer.from([127,69,76,70])) && bytes[4]===2 && [1,2].includes(bytes[5])) {
    const machine=bytes[5]===1?bytes.readUInt16LE(18):bytes.readUInt16BE(18);
    os='linux';arch=({62:'x64',183:'arm64'})[machine];
  } else if(bytes.length>=32 && bytes.readUInt32LE(0)===0xfeedfacf) {
    os='darwin';arch=({[0x01000007]:'x64',[0x0100000c]:'arm64'})[bytes.readUInt32LE(4)];
  } else if(bytes.length>=64 && bytes.readUInt16LE(0)===0x5a4d) {
    const offset=bytes.readUInt32LE(60);
    if(offset+94<=bytes.length && bytes.readUInt32LE(offset)===0x4550 && bytes.readUInt16LE(offset+24)===0x20b && bytes.readUInt16LE(offset+92)===3) {
      os='win32';arch=({[0x8664]:'x64',[0xaa64]:'arm64'})[bytes.readUInt16LE(offset+4)];
    }
  }
  const actual={os:os||'unknown',arch:arch||'unknown'};
  if(os!==native.os || arch!==native.arch) throw new Error(`ENTRY_LAUNCHER_FORMAT ${platform}: ${JSON.stringify(actual)}`);
  console.log(`ENTRY_LAUNCHER_FORMAT_PASS platform=${platform} result=${JSON.stringify(actual)}`);
  return actual;
}
export async function installEntries({root, build, groups, tools = {}, records, platform}) {
  // The launcher refuses an entry whose platform is not the one it was built
  // for, so this field has to name the target, not the machine producing it. A
  // Windows cell cross-built on Linux otherwise writes `linux` into every
  // recipe, and each one refuses to start on the platform it was built for.
  // The producer's own consumer (compiler_identity.mjs) reads the same field
  // and expects the target's name, so deriving it from process.platform also
  // made the installation disagree with its own verification. Checked before the
  // launcher is built, so a missing target platform costs nothing.
  if (typeof platform !== 'string' || !platform) throw new Error('ENTRY_PLATFORM_REQUIRED');
  const system = entryPlatformName(platform);
  const native = sdkPlatform(platform);
  root = await privateRoot(root);
  const source = fileURLToPath(new URL('./native-launcher/', import.meta.url));
  // The launcher is produced for the platform its recipes name. A cross cell
  // installs it into a target SDK, so building the host's launcher and writing
  // the target's name into the recipe ships a host-format binary that the target
  // OS rejects before it can read that name. The executable name follows the
  // target for the same reason: it is the file the target platform starts.
  const hostOs = process.platform;
  const cross = native.os !== hostOs || native.arch !== process.arch;
  const cmakeToolchain = [];
  if (cross && !(tools.targetToolchain || tools.cxx && tools.targetTriple && tools.targetSysroot)) {
    throw new Error(`ENTRY_TARGET_TOOLCHAIN_REQUIRED ${platform}: `
      + `the launcher is produced on ${hostOs}/${process.arch} but its recipes name ${native.os}/${native.arch}`);
  }
  if(cross && native.os!=='win32') {
    if(!tools.cxx || !tools.targetTriple || !tools.targetSysroot) throw new Error(`ENTRY_TARGET_TOOLCHAIN_REQUIRED ${platform}`);
    cmakeToolchain.push('-DCMAKE_SYSTEM_NAME='+({linux:'Linux',darwin:'Darwin'})[native.os],
      '-DCMAKE_SYSTEM_PROCESSOR='+({x64:'x86_64',arm64:'aarch64'})[native.arch],
      '-DCMAKE_CXX_COMPILER='+tools.cxx,'-DCMAKE_CXX_COMPILER_TARGET='+tools.targetTriple,
      '-DCMAKE_SYSROOT='+tools.targetSysroot);
  }
  if (cross && native.os === 'win32') {
    for(const name of ['x86_64-w64-mingw32-clang','x86_64-w64-mingw32-clang++','x86_64-w64-mingw32-windres']) {
      await fs.access(path.join(tools.targetToolchain,name),fs.constants.X_OK);
    }
    // The cross cell already holds the MinGW toolchain it builds the target
    // products with; the launcher is one more target product.
    cmakeToolchain.push(
      '-DCMAKE_SYSTEM_NAME=Windows',
      '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
      '-DCMAKE_C_COMPILER=' + path.join(tools.targetToolchain, 'x86_64-w64-mingw32-clang'),
      '-DCMAKE_CXX_COMPILER=' + path.join(tools.targetToolchain, 'x86_64-w64-mingw32-clang++'),
      '-DCMAKE_RC_COMPILER=' + path.join(tools.targetToolchain, 'x86_64-w64-mingw32-windres'),
      '-DCMAKE_FIND_ROOT_PATH=' + path.dirname(tools.targetToolchain),
      '-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER',
      '-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY',
      '-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY',
    );
  }
  const binary = path.join(build, 'cjcj-sdk-entry' + native.exe);
  await command([tools.cmake || 'cmake','-G','Ninja','-S',source,'-B',build,'-DCMAKE_BUILD_TYPE=Release',
    ...cmakeToolchain,
    ...(native.os==='darwin'?['-DCMAKE_OSX_ARCHITECTURES='+({x64:'x86_64',arm64:'arm64'})[native.arch]]:[]),
    ...(tools.cxx && !cross ? ['-DCMAKE_CXX_COMPILER='+tools.cxx] : []),
    ...(tools.launcher ? ['-DCMAKE_CXX_COMPILER_LAUNCHER='+tools.launcher] : [])], {records});
  await command([tools.cmake || 'cmake','--build',build,'--config','Release','--target','cjcj-sdk-entry','--parallel',String(await selectBuildJobs())], {records});
  // The produced bytes have to be the format the target expects, not merely
  // named for it. A launcher that silently came out in the host's format must
  // not be installed under a target recipe.
  await assertLauncherFormat({binary, native, platform});
  for (const group of groups) {
    relative(group.directory);relative(group.retain);
    const directory=path.join(root,group.directory);
    for (const name of await fs.readdir(directory)) {
      if(group.names&&!group.names.includes(name)||group.exclude?.includes(name))continue;
      const entry=path.join(directory,name),st=await fs.lstat(entry);
      if(!st.isFile()||(!(st.mode&0o111)&&!(process.platform==='win32'&&name.endsWith('.exe'))))continue; // Preserve actual native aliases.
      const realRel=path.posix.join(group.retain,name),real=path.join(root,realRel);
      await privateRoot(path.dirname(real));await fs.mkdir(path.dirname(real),{recursive:true});
      await fs.copyFile(entry,real,fs.constants.COPYFILE_EXCL); // Original tool bytes remain ordinary files.
      await fs.copyFile(binary,entry);await fs.chmod(entry,0o755);
      const ascent=group.directory.split('/').length;
      const libraries=group.libraries.map(relative);
      await fs.writeFile(entry+'.entry',['cjcj-sdk-entry-v1',ascent,realRel,system,'native-target:'+native.arch,...libraries].join('\n')+'\n');
    }
  }
}
