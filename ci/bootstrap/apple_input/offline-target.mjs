export function expectHeaderRejection(entry, args) {
  let reason = null, admitted = null;
  try {admitted = entry(...args);} catch (e) {reason = e.message;}
  const ok = reason === 'apple-header-drift' && admitted === null;
  console.log(`TARGET_ASSERTION apple-header-drift actual=${reason ?? admitted?.status} ${ok ? 'PASS' : 'FAIL'}`);
  if (!ok) throw new Error('TARGET_ASSERTION:apple-header-drift');
  return {status: 'HEADER_DRIFT_REJECTED', reason, admitted};
}
