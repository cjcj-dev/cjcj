import path from 'node:path';

const linkOptionPattern = /^(\s*link-option\s*=\s*)"([^"]*)"(\s*)$/m;

export function assembleCjcLinkOption(
  platform, cangjieHome, currentLinkOption, llvmLinkRsp = '', mingwCxxLinkRsp = '') {
  const llvmDir = path.join(cangjieHome, 'third_party', 'llvm', 'lib');
  if (platform === 'darwin') {
    return [
      '-export_dynamic',
      'runtime_shim/cjselfhost_llvmshim.o',
      'runtime_shim/cjc_runtime_config.o',
      path.join(llvmDir, 'libLLVM.dylib'),
      '-lc++',
      '-rpath',
      llvmDir,
    ].join(' ');
  }
  if (platform === 'win32') {
    if (!llvmLinkRsp) throw new Error('Windows LLVM static link response is required');
    if (!mingwCxxLinkRsp) throw new Error('Windows MinGW C++ link response is required');
    // PE link: no --export-dynamic / -rpath (ELF-only; round-17 lld rejected
    // both). The tuple response keeps LLVM archives lazy and grouped.
    // --stack: the PE default reserve is 1MB and the compiler's recursion plus
    // the Cangjie runtime overflow it at startup (round-14 STATUS_STACK_OVERFLOW,
    // SizeOfStackReserve=0x100000); Linux runs on the 8MB ulimit default, so
    // reserve 64MB to match the deep-recursion headroom.
    return [
      '--stack=0x4000000',
      'runtime_shim/cjselfhost_llvmshim.o',
      'runtime_shim/cjc_runtime_config.o',
      `@${llvmLinkRsp.replaceAll('\\', '/')}`,
      `@${mingwCxxLinkRsp.replaceAll('\\', '/')}`,
    ].join(' ');
  }
  return currentLinkOption;
}

export function platformizeCjcToml(
  cjpmToml, platform, cangjieHome, llvmLinkRsp = '', mingwCxxLinkRsp = '') {
  const match = cjpmToml.match(linkOptionPattern);
  if (!match) throw new Error('packages/cjc/cjpm.toml has no link-option');

  const linkOption = assembleCjcLinkOption(
    platform, cangjieHome, match[2], llvmLinkRsp, mingwCxxLinkRsp);
  if (linkOption === match[2]) return cjpmToml;
  return cjpmToml.replace(linkOptionPattern, `$1"${linkOption}"$3`);
}
