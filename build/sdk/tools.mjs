// SDK consumers built on the installed SDK: stdx, Java interop (installer option) and the 10 tools.
export const TOOL_NAMES = Object.freeze(['cjpm', 'cjfmt', 'hle', 'lsp', 'cjcov', 'cjtrace-recover', 'cjlint', 'cjprof', 'cjcompat', 'cjhead']);

export function stdxArgs({globals}) { return [...globals, 'build', 'stdx']; }

export function toolsArgs({globals, sdk, frontend, frontendRef, product, llvmLibrary, stdxJsonBuild, jdk, runtimeHeader, lombok}) {
  return [...globals,
    '--tools-analysis-sdk', sdk, '--tools-frontend-source', frontend, '--tools-frontend-ref', frontendRef,
    '--tools-compiler-libs', `${product}/share/cjcj/cjo`,
    '--tools-runtime-config', `${product}/share/cjcj/runtime_shim/cjc_runtime_config.o`,
    '--tools-llvm-shim', `${product}/share/cjcj/runtime_shim/cjselfhost_llvmshim.o`, '--tools-llvm-library', llvmLibrary,
    '--tools-json-build', stdxJsonBuild, '--tools-jni-home', jdk, '--tools-runtime-header', runtimeHeader,
    '--tools-lombok-jar', lombok, '--tools-mangle-source', `${frontend}/packages/mangle/src`,
    '--tools-build-set', 'all', '--tools-phase', 'all', 'build', 'tools'];
}

export function checkTools(inputs, toolsCommit) {
  const rows = Object.values(inputs.files ?? {});
  if (rows.length !== TOOL_NAMES.length) throw new Error(`TOOLS_COUNT ${rows.length}`);
  for (const row of rows) {
    const p = row.producer;
    if (p.source.commit !== toolsCommit || p.build.rc !== 0 || p.install.rc !== 0) throw new Error(`TOOLS_PRODUCER ${JSON.stringify(p.source)}`);
  }
  return rows.length;
}
