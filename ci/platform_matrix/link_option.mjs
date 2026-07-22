import path from 'node:path';

const linkOptionPattern = /^(\s*link-option\s*=\s*)"([^"]*)"(\s*)$/m;

export function assembleCjcLinkOption(platform, cangjieHome, currentLinkOption) {
  if (platform !== 'darwin') return currentLinkOption;

  const llvmDir = path.join(cangjieHome, 'third_party', 'llvm', 'lib');
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

export function platformizeCjcToml(cjpmToml, platform, cangjieHome) {
  const match = cjpmToml.match(linkOptionPattern);
  if (!match) throw new Error('packages/cjc/cjpm.toml has no link-option');

  const linkOption = assembleCjcLinkOption(platform, cangjieHome, match[2]);
  if (linkOption === match[2]) return cjpmToml;
  return cjpmToml.replace(linkOptionPattern, `$1"${linkOption}"$3`);
}
