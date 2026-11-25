import path from 'node:path';

export function testEvidenceDirectory(...parts) {
  const root = process.env.RELEASE_EVIDENCE_TEST_ROOT;
  if (!root) throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
  return path.join(root, ...parts);
}
