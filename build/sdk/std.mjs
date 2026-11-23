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
