import assert from 'node:assert/strict';
import test from 'node:test';
import {assertWriteBarriers, inspectWriteBarriers} from '../../ci/srcbuild/lib/write-barrier.mjs';

// The verdict columns, without the lexer's own bookkeeping.
const verdict = ({phaseChecks, staticGuarded, bypassed, unresolved}) =>
  ({phaseChecks, staticGuarded, bypassed, unresolved});

function capture(fn) {
  const lines = [];
  const out = console.log; const err = console.error;
  console.log = (...a) => lines.push(['out', a.join(' ')]);
  console.error = (...a) => lines.push(['err', a.join(' ')]);
  try { fn(); } finally { console.log = out; console.error = err; }
  return lines;
}

// objdump -drwC shape: address, raw bytes, mnemonic, and (wide) the relocation
// appended to the same line.
function line(address, bytes, text, relocation) {
  const parts = [`   ${address}:`, bytes, text];
  const body = relocation ? `${parts.slice(1).join('\t')}\t${relocation}` : parts.slice(1).join('\t');
  return `   ${address}:\t${body}`;
}

// The off shape from CJBarrierLowering.cpp SplitFastPathAndSlowPath: phase check,
// fast arm inlines the store, slow arm calls the runtime.
const guarded = callee => [
  '0000000000000340 <_CNat4Test1fHv>:',
  line('347', '49 8b 47 08', 'mov    0x8(%r15),%rax'),
  line('34b', '8b 00', 'mov    (%rax),%eax'),
  line('34d', '83 f8 09', 'cmp    $0x9,%eax'),
  line('350', '7d 05', 'jge    357 <_CNat4Test1fHv+0x17>'),
  line('352', '4c 89 22', 'mov    %r12,(%rdx)'),
  line('355', 'eb 0b', 'jmp    362 <_CNat4Test1fHv+0x22>'),
  line('357', '4c 89 e7', 'mov    %r12,%rdi'),
  line('35d', 'e8 00 00 00 00', 'call   362 <_CNat4Test1fHv+0x22>', `35e: R_X86_64_PLT32\t${callee}-0x4`),
  line('362', 'c3', 'ret'),
].join('\n');

// The on shape: the same write, called unconditionally.
const unguarded = [
  '0000000000000340 <_CNat4Test1fHv>:',
  line('347', '4c 89 e7', 'mov    %r12,%rdi'),
  line('34a', 'e8 00 00 00 00', 'call   34f <_CNat4Test1fHv+0xf>', '34b: R_X86_64_PLT32\tCJ_MCC_WriteRefField-0x4'),
  line('34f', 'c3', 'ret'),
].join('\n');

test('a phase-guarded heap write counts as bypassed', () => {
  const counts = inspectWriteBarriers(guarded('CJ_MCC_WriteRefField'));
  assert.deepEqual(verdict(counts), {phaseChecks: 1, staticGuarded: 0, bypassed: 1, unresolved: 0});
});

test('a phase-guarded static write is the intended fast path, not a bypass', () => {
  // cj_gcwrite_static_ref is not in the list fastBarrier() blocks, so it keeps the
  // fast path even with the flag on. Counting it would reject a correct std.
  const counts = inspectWriteBarriers(guarded('CJ_MCC_WriteStaticRef'));
  assert.deepEqual(verdict(counts), {phaseChecks: 1, staticGuarded: 1, bypassed: 0, unresolved: 0});
});

test('an unconditional heap write is what the barrier looks like when it is on', () => {
  const counts = inspectWriteBarriers(unguarded);
  assert.deepEqual(verdict(counts), {phaseChecks: 0, staticGuarded: 0, bypassed: 0, unresolved: 0});
});

test('addresses do not resolve across function boundaries', () => {
  // Two functions whose addresses overlap: the branch in the first must not land
  // on an instruction belonging to the second.
  const counts = inspectWriteBarriers(`${guarded('CJ_MCC_WriteRefField')}\n${unguarded}`);
  assert.equal(counts.bypassed, 1);
  assert.equal(counts.phaseChecks, 1);
});

test('an empty disassembly is indeterminate, never a pass', () => {
  // bypassed is 0 here only because nothing was looked at. Reading that as green
  // is how this check fails in practice: point it at the wrong object, or run
  // objdump with flags whose line shape the patterns do not match, and every
  // counter is zero.
  const lines = capture(() => assertWriteBarriers('', 'label=empty'));
  assert.equal(lines.filter(([, text]) => text.includes('STAGE3_WRITE_BARRIER_PASS')).length, 0);
  assert.match(lines[0][1], /STAGE3_WRITE_BARRIER_INDETERMINATE reason=no-phase-checks-resolved/);
  assert.equal(lines[0][0], 'err');
});

test('phase checks that tie to no callee are indeterminate, never a pass', () => {
  // The real shape of this: an unlinked .a whose relocations are not being read,
  // so the call targets are invisible. Measured once at phase_checks=426 with all
  // 426 unresolved and bypassed=0.
  const opaque = [
    '0000000000000340 <_CNat4Test1fHv>:',
    line('347', '49 8b 47 08', 'mov    0x8(%r15),%rax'),
    line('34b', '8b 00', 'mov    (%rax),%eax'),
    line('34d', '83 f8 09', 'cmp    $0x9,%eax'),
    line('350', '7d 05', 'jge    357 <_CNat4Test1fHv+0x17>'),
    line('352', '4c 89 22', 'mov    %r12,(%rdx)'),
    line('355', 'eb 0b', 'jmp    362 <_CNat4Test1fHv+0x22>'),
    line('357', 'e8 00 00 00 00', 'call   362 <_CNat4Test1fHv+0x22>'),
    line('362', 'c3', 'ret'),
  ].join('\n');
  const counts = inspectWriteBarriers(opaque);
  assert.equal(counts.phaseChecks, 1);
  assert.equal(counts.bypassed, 0);
  const lines = capture(() => assertWriteBarriers(opaque, 'label=opaque'));
  assert.match(lines[0][1], /STAGE3_WRITE_BARRIER_INDETERMINATE reason=no-phase-check-tied-to-a-callee/);
});

test('fail-closed refuses a run that proved nothing', () => {
  assert.throws(() => assertWriteBarriers('', 'label=empty', {failClosed: true}),
    /STAGE3_WRITE_BARRIER_INDETERMINATE reason=no-phase-checks-resolved/);
});

test('a resolved population still passes', () => {
  const lines = capture(() => assertWriteBarriers(guarded('CJ_MCC_WriteStaticRef'), 'label=good'));
  assert.match(lines[0][1], /STAGE3_WRITE_BARRIER_PASS/);
  assert.equal(lines[0][0], 'out');
});
