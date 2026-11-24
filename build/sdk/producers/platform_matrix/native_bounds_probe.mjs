// The libboundscheck export a native consumer binds and calls. On Windows the
// boundscheck target compiles only memset_s/snprintf_s/vsnprintf_s because the
// C runtime already supplies the remaining secure functions
// (runtime/third_party/third_party_bounds_checking_function/CMakeLists.txt), so
// libboundscheck.dll never defines memcpy_s. Linux and Darwin build every source.
export function boundsProbeSymbol(os) {
  if (os === 'win32') return 'memset_s';
  if (os === 'linux' || os === 'darwin') return 'memcpy_s';
  throw new Error(`NATIVE_BOUNDS_PROBE_PLATFORM ${os}`);
}
