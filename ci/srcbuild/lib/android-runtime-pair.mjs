// Private Android build: the target's sole change from the host runtime is
// forwarding the Android NDK/API to the nested stdlib PCRE2 configure.
export function assertAndroidRuntimePair(hostRef, targetRef, stage) {
  if (!/^[0-9a-f]{40}$/.test(hostRef) || stage?.runtimeCommit !== hostRef)
    throw Error('ANDROID_INSTALL_RUNTIME_PAIR');
  if (targetRef === hostRef) return;
  if (hostRef !== '9991cf4f4c9cb3465bb5aec28a5590f6c529be4e' ||
      targetRef !== '20995aae195f134ecc2c94bb6a90239c31b673f4' ||
      stage.sources?.runtime?.commit !== hostRef || stage.sources?.std?.commit !== hostRef ||
      stage.compilerCommit !== 'ea6d3b5fc73b5e4cc2926535005a46a92109b2b9' ||
      stage.sources?.llvm?.commit !== 'f2a8e33d2dbb6797d65813cd20f529d9567843a1' ||
      !((stage.phase === 'stage3' && stage.compilerSha256 === '5190316791e889c882684361d79a8fc70f7a1f9d606316b3cde032bf0c5f6fc1') ||
        (stage.phase === 'stage2' && stage.compilerSha256 === 'ab8e03d32d95b8a84da42a4d11520b2644796cc339e50825426bb38bf5c33be0')))
    throw Error('ANDROID_INSTALL_RUNTIME_PAIR');
}
