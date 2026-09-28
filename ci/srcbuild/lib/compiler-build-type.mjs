// cangjie_compiler/cmake/{linux,darwin,mingw_x86_64}_toolchain.cmake:
// release executables are stripped by the linker. Use the driver's portable
// --strip-all option before linking, so provenance describes the final bytes.
export function compilerBuildTypeToml(toml, buildType) {
  return toml.replace(/^(\s*compile-option\s*=\s*")([^"\n]*)("[^\n]*)$/m,
    (_, prefix, options, suffix) => {
      const flags = options.split(/\s+/).filter(flag => flag && flag !== '--strip-all');
      if (buildType === 'release') flags.push('--strip-all');
      return `${prefix}${flags.join(' ')}${suffix}`;
    });
}
