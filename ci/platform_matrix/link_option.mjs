import path from 'node:path';

const linkOptionPattern = /^(\s*link-option\s*=\s*)"([^"]*)"(\s*)$/m;

export function assembleCjcLinkOption(platform, cangjieHome, currentLinkOption) {
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
    // PE link: no --export-dynamic / -rpath (ELF-only; round-17 lld rejected
    // both), and the LLVM import library resolves via -L + -lLLVM-15.
    return [
      'runtime_shim/cjselfhost_llvmshim.o',
      'runtime_shim/cjc_runtime_config.o',
      `-L${llvmDir.replaceAll('\\', '/')}`,
      '-lLLVM-15',
      '-lstdc++',
    ].join(' ');
  }
  return currentLinkOption;
}

export function platformizeCjcToml(cjpmToml, platform, cangjieHome) {
  const match = cjpmToml.match(linkOptionPattern);
  if (!match) throw new Error('packages/cjc/cjpm.toml has no link-option');

  const linkOption = assembleCjcLinkOption(platform, cangjieHome, match[2]);
  if (linkOption === match[2]) return cjpmToml;
  return cjpmToml.replace(linkOptionPattern, `$1"${linkOption}"$3`);
}
