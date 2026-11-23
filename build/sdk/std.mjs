// One std configuration for every target: same source, same dependency closure, explicit local-mode surface.
export const API_TUPLE = 'linux_x86_64_cjnative';

// Native and cross std are always parsed in local mode with the public API compiled out; only the
// Linux x64 native std may opt in to the API (local_mode_api=on) through the real build.py switch.
export function stdCompileFlags(tuple, {localModeApi = false} = {}) {
  if (typeof tuple !== 'string' || !/_cjnative$/.test(tuple)) throw new Error(`STD_TUPLE ${tuple}`);
  if (localModeApi && tuple !== API_TUPLE) throw new Error(`STD_LOCAL_MODE_API_TUPLE ${tuple}`);
  return ['--experimental', '--enable-local-mode', '--cfg', `local_mode_api=${localModeApi ? 'on' : 'off'}`];
}

// Arguments for the std producer entry (ci/bootstrap/sdk-native-stage.mjs --kind std).
export function stdProducerArgs(tuple, {localModeApi = false} = {}) {
  stdCompileFlags(tuple, {localModeApi});
  return localModeApi ? ['--local-mode-api'] : [];
}

// Wasm WASI P1: the full std including std.core is built by one producer with the same flags.
export function wasmStdPlan() {
  return {tuple: 'wasi_wasm32_cjnative', packages: 'full', includesCore: true, flags: stdCompileFlags('wasi_wasm32_cjnative')};
}

export const WASM_TUPLE = 'wasi_wasm32_cjnative';
export const WASM_TARGET = '--target=wasm32-wasi';
export const WASM_OPT_LEVELS = Object.freeze(['O2', 'default']);

// cjc argv for one Wasm std package. Every package carries the same local-mode flags as native std.
// std.core is the prelude package (--no-prelude, no reflection). The aggregate root package `std` only
// re-exports its sub-packages, so it alone is built without --no-sub-pkg; the flag is added by name,
// never removed by position, so no other option (e.g. --enable-local-mode) can be dropped with it.
export function wasmStdPackageArgv({name, dir, output, importPath, opt = 'O2'}) {
  if (!WASM_OPT_LEVELS.includes(opt)) throw new Error(`WASM_STD_OPT ${opt}`);
  if (typeof name !== 'string' || !/^std(\.[a-z_][a-z0-9_]*)*$/.test(name)) throw new Error(`WASM_STD_PACKAGE ${name}`);
  if (!dir || !output) throw new Error(`WASM_STD_PATHS ${name}`);
  const level = opt === 'O2' ? ['-O2'] : [];
  const flags = stdCompileFlags(WASM_TUPLE);
  if (name === 'std.core') return [WASM_TARGET, ...level, ...flags, '--no-prelude', '--no-sub-pkg', '-p', dir,
    '--output-type=staticlib', '--disable-reflection', `--output=${output}`, '-V'];
  if (!importPath) throw new Error(`WASM_STD_IMPORT_PATH ${name}`);
  return [WASM_TARGET, ...level, ...flags, ...(name === 'std' ? [] : ['--no-sub-pkg']), '-p', dir,
    '--output-type=staticlib', `--output=${output}`, `--import-path=${importPath}`, '-Woff', 'all'];
}

// -O2 first, then the compiler default level; the producer records which attempt built the package
// and never reports a default-level package as -O2.
export function wasmStdAttempts(pkg) {
  return WASM_OPT_LEVELS.map(opt => ({opt, argv: wasmStdPackageArgv({...pkg, opt})}));
}
