function exitCode(result) {
  if (Number.isInteger(result?.exitCode)) return result.exitCode;
  if (Number.isInteger(result?.status)) return result.status;
  return null;
}

function oneLine(value) {
  return `${value || ''}`.split(/\r?\n/).map(line => line.trim()).filter(Boolean).join(' | ');
}

export function commandFailure(result, label) {
  if (!label) throw new Error('probe label is required');
  const code = exitCode(result);
  const detail = [result?.stderr, result?.stdout, result?.error?.message]
    .map(oneLine).filter(Boolean).join(' | ').slice(0, 512) || 'no diagnostic output';
  return new Error(`${label} failed (exit=${code ?? 'spawn'}): ${detail}`);
}

export function assertCommandSucceeded(result, label) {
  if (exitCode(result) !== 0) throw commandFailure(result, label);
  return result;
}

export async function runRequiredProbe({label, run}) {
  if (typeof run !== 'function') throw new Error(`${label || 'required probe'} runner is required`);
  return assertCommandSucceeded(await run(), label);
}

export async function runGrepProbe({label, run}) {
  if (typeof run !== 'function') throw new Error(`${label || 'grep probe'} runner is required`);
  const result = await run();
  const code = exitCode(result);
  if (code === 0) return {matched: true, result};
  if (code === 1) return {matched: false, result};
  throw commandFailure(result, label);
}
