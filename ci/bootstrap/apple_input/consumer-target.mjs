export function assertAdmission(entry, [recipe, auth, legacy, transport], expected) {
  let reason = null, results = [];
  try {
    for (let step = 0; step < 2; step++) results.push(entry(recipe, auth, legacy, step, transport));
  } catch (error) {reason = error.message;}
  const ok = expected === 'BOUNDARY'
    ? reason === null && results.length === 2 && results.every((r, i) => r.status === 'AUTHORIZED_BOUNDARY_NOT_LAUNCHED' && r.step === i && r.qualification === null)
    : reason === expected && results.length === 0;
  console.log(`TARGET_ASSERTION ${expected} actual=${reason ?? results.at(-1)?.status} steps=${results.length} ${ok ? 'PASS' : 'FAIL'}`);
  if (!ok) throw new Error('TARGET_ASSERTION:' + expected);
}
