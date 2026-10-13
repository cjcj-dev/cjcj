import fs from 'node:fs';
export function expectCaptureRejection(entry, spec, destination) {
  let reason = null, record = null;
  try {record = entry(spec, destination);} catch (e) {reason = e.message;}
  const ok = reason === 'apple-required-header' && record === null && !fs.existsSync(destination);
  console.log(`TARGET_ASSERTION apple-required-header actual=${reason ?? 'CAPTURE_WRITTEN'} ${ok ? 'PASS' : 'FAIL'}`);
  if (!ok) throw new Error('TARGET_ASSERTION:apple-required-header');
  return {reason, record, manifest_written: fs.existsSync(destination)};
}
