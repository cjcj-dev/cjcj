// GenerateRuntimeProvenance.cmake emits newline-separated provenance fields.
// Match the existing SDK consumers: one distinct clean commit, never dirty.
export function readRuntimeCommit(bytes) {
  const stamps = [...bytes.toString('latin1').matchAll(/CJRT-COMMIT:([A-Za-z0-9_-]+)/g)]
    .map(match => match[1]);
  const unique = [...new Set(stamps)];
  if (unique.length !== 1 || !/^[0-9a-f]{40}$/.test(unique[0])) {
    throw Error('RESUME_SDK_RUNTIME_STAMP_INVALID');
  }
  return unique[0];
}
