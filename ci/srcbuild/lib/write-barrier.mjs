// Generational write barrier check for a built std.
//
// assertStdBarriers already proves the *read* side — g_cjLoadBadMask, the tag
// test, CJ_MCC_Read* — and passes a std that has colouring. It says nothing
// about the *write* side, so a std built with colouring but without the
// generational post barrier walks straight through it. That combination is not
// hypothetical: ci/llvm_pin.env pins an llc whose -cj-generational-post-barrier
// still defaults to cl::init(false), so anything compiled by a driver that does
// not pass the flag itself lands in exactly that state.
//
// Shape being detected (CJBarrierLowering.cpp SplitFastPathAndSlowPath):
//
//     mov 0x8(%r15),%rax     ; CJTLS + MutatorOffsetInCJTLS
//     mov (%rax),%eax        ; ->GCPhase
//     cmp $0x8/$0x9,%eax     ; icmp sle kGCPhaseInit
//     jcc <slow>             ; fast arm inlines a plain store, slow arm calls CJ_MCC_*
//
// With the flag on, fastBarrier() returns false for the five write-side
// intrinsics, so their CJ_MCC_ calls are unconditional and no such sequence
// guards them. A guarded one therefore means the write bypassed the runtime.
//
// Static-slot writes are excluded on purpose: cj_gcwrite_static_{ref,struct}
// are not in that list, so they keep the fast path even with the flag on.
// Static slots are roots, enumerated every cycle, so they need no remembered
// set entry. Counting them would reject a correctly built std.

const BLOCKED_CALLEES = [
  'CJ_MCC_WriteRefField',
  'CJ_MCC_WriteStructField',
  'CJ_MCC_ArrayCopyRef',
  'CJ_MCC_ArrayCopyStruct',
  'CJ_MCC_AtomicWriteReference',
];
const STATIC_CALLEES = ['CJ_MCC_WriteStaticRef', 'CJ_MCC_WriteStaticStruct'];

// Two disassemblers, two dialects, one machine code. GNU objdump is what
// assertStdBarriers calls today; llvm-objdump is the one that can also read
// aarch64 and Mach-O, so the patterns have to survive both. Measured on the same
// archive, the same instruction reads:
//
//   GNU   `     347:\t49 8b 47 08          \tmov    0x8(%r15),%rax`
//   LLVM  `     347: 49 8b 47 08                  \tmovq\t8(%r15), %rax`
//
// Seven differences, three of which silently kill a pattern written for the
// other: the address separator (tab vs space), the size suffix on the mnemonic
// (mov vs movq), and the immediate radix ($0x9 vs $9, 0x8(%r15) vs 8(%r15)).
// Relocations also move: GNU -w appends them to the instruction line, llvm-objdump
// gives each its own.
const INSTRUCTION = /^\s+([0-9a-f]+):[\t ](.*)$/;
const RAW_BYTES = /^[0-9a-f]{2}(?: [0-9a-f]{2})*\s*$/;
const RELOCATION_TAG = /^[0-9a-f]+:\s+\S+$/;
// Addresses restart at every function, and an archive holds many members, so a
// single address map lets a branch in one member resolve onto an instruction in
// another. Cut the stream at function headers and resolve within one function.
const FUNCTION_HEADER = /^[0-9a-f]+\s+<(.+)>:$/;
// `mov` or `movq`; `0x8(%r15)` or `8(%r15)`.
const TLS_LOAD = /^mov\w*\s+(?:0x)?8\(%r15\),%rax$/;
const PHASE_LOAD = /^mov\w*\s+\(%rax\),%eax$/;
// icmp sle kGCPhaseInit(8), emitted as `cmp $0x8`/`cmp $0x9` or `cmpl $8`/`$9`.
const PHASE_COMPARE = /^cmp\w*\s+\$(?:0x)?[89],/;
const CONDITIONAL = /^j(?!mp\b)\w+\s+(?:0x)?([0-9a-f]+)/;
const TERMINATOR = /^(?:jmp\w*|ret\w*)\b/;
// In an unlinked archive the call target lives on a relocation line, not inside
// the instruction text. Relocation lines start with tabs and put a space after
// the address; instruction lines start with spaces and put a tab there, so the
// two never collide. Reading only the instruction text finds no callee at all
// in a .a, which turns every phase check into 'unresolved'.
const RELOCATION = /^\t+[0-9a-f]+:\s+(\S+)\s+(\S+)\s*$/;

const ARM_LIMIT = 16;
const COMPARE_LIMIT = 8;

function callee(instruction) {
  if (instruction.callee) return instruction.callee;
  const match = /<([^>]+)>/.exec(instruction.text);
  return match ? match[1].split('@')[0] : '';
}

function relocationSymbol(text) {
  return text.split('-')[0].split('+')[0].replace(/^\*/, '');
}

// The slow arm holds exactly one barrier call, and the join block falls through
// behind it with no terminator to stop on, so take the first CJ_MCC_ callee and
// stop — reading further picks up the next, unrelated write.
function firstBarrierCall(instructions, start) {
  if (start === undefined) return '';
  for (let i = start; i < Math.min(start + ARM_LIMIT, instructions.length); i += 1) {
    const name = callee(instructions[i]);
    if (name.startsWith('CJ_MCC_')) return name;
    if (i > start && TERMINATOR.test(instructions[i].text)) break;
  }
  return '';
}

/**
 * @param {string} disassembly output of `objdump -drwC <archive>`
 * @returns {{phaseChecks: number, staticGuarded: number, bypassed: number, unresolved: number}}
 */
export function inspectWriteBarriers(disassembly) {
  // functions/instructions are the lexer's own account of what it read. Comparing
  // two disassemblers' verdicts is only meaningful if both front-ends saw the same
  // program, and a front-end that silently read nothing reports zero everywhere.
  const result = {phaseChecks: 0, staticGuarded: 0, bypassed: 0, unresolved: 0,
    functions: 0, instructions: 0};
  let instructions = [];
  const flush = () => {
    if (instructions.length) {
      result.functions += 1;
      result.instructions += instructions.length;
      inspectFunction(instructions, result);
    }
    instructions = [];
  };
  for (const line of disassembly.split('\n')) {
    if (FUNCTION_HEADER.test(line)) {
      flush();
      continue;
    }
    // Relocation on a line of its own (objdump without -w).
    const standalone = RELOCATION.exec(line);
    if (standalone && instructions.length) {
      const previous = instructions[instructions.length - 1];
      if (!previous.callee) previous.callee = relocationSymbol(standalone[2]);
      continue;
    }
    const match = INSTRUCTION.exec(line);
    if (!match) continue;
    let fields = match[2].split('\t');
    if (fields.length > 1 && RAW_BYTES.test(fields[0].trim())) fields = fields.slice(1);
    // Relocation appended to the instruction line (objdump with -w).
    let attached = '';
    let body;
    if (fields.length >= 3 && RELOCATION_TAG.test(fields[1])) {
      attached = relocationSymbol(fields[2]);
      body = fields[0];
    } else {
      // llvm-objdump splits mnemonic and operands across the tab, so keeping only
      // the first field would drop every operand and match nothing.
      body = fields.join(' ');
    }
    instructions.push({
      address: parseInt(match[1], 16),
      // Collapse whitespace and drop the space llvm-objdump puts after commas, so
      // `%rsp, %rbp` and `%rsp,%rbp` compare as the same operand list.
      text: body.split('#')[0].trim().replace(/\s+/g, ' ').replace(/, /g, ','),
      callee: attached,
    });
  }
  flush();
  return result;
}

function inspectFunction(instructions, result) {
  const byAddress = new Map();
  instructions.forEach((instruction, index) => {
    if (!byAddress.has(instruction.address)) byAddress.set(instruction.address, index);
  });

  for (let i = 0; i + 1 < instructions.length; i += 1) {
    if (!TLS_LOAD.test(instructions[i].text) || !PHASE_LOAD.test(instructions[i + 1].text)) continue;
    result.phaseChecks += 1;
    let branch;
    for (let j = i + 2; j < Math.min(i + 2 + COMPARE_LIMIT, instructions.length); j += 1) {
      if (!PHASE_COMPARE.test(instructions[j].text)) continue;
      for (let k = j + 1; k < Math.min(j + 4, instructions.length); k += 1) {
        const jump = CONDITIONAL.exec(instructions[k].text);
        if (jump) {
          branch = {index: k, target: parseInt(jump[1], 16)};
          break;
        }
      }
      break;
    }
    if (!branch) {
      result.unresolved += 1;
      continue;
    }
    const guarded = new Set([
      firstBarrierCall(instructions, byAddress.get(branch.target)),
      firstBarrierCall(instructions, branch.index + 1),
    ]);
    if (BLOCKED_CALLEES.some(name => guarded.has(name))) result.bypassed += 1;
    else if (STATIC_CALLEES.some(name => guarded.has(name))) result.staticGuarded += 1;
    else result.unresolved += 1;
  }
}

/**
 * Fail-closed. The condition the previous comment set for flipping this -- "once
 * the pin moves past 743f41f7" -- has been met: ci/llvm_pin.env pins
 * LLVM_SHA=70a40482, `git merge-base --is-ancestor 743f41f7 70a40482` exits 0,
 * and 70a40482..main is empty, so the pinned llc defaults the generational post
 * barrier on. packages/driver/src/ToolOptions.cj:195 passes it explicitly too.
 *
 * What this checker reads is build-stage3.mjs:232 finalCore, the std this stage
 * just built from source (:223 build.py install --prefix), never the bootstrap
 * SDK's. Measured on kkk2 with the pinned llc and driver, both disassemblers
 * agreeing: source-built core 19/19/0/0 (all nineteen resolve to the
 * deliberately-allowed CJ_MCC_WriteStaticRef guard), stock nightly core
 * 426/14/7/405. Flipping was verified both directions -- the stock arm exits 1,
 * the source-built arm exits 0 -- so this blocks a real regression rather than
 * the build that has to fix it.
 *
 * Only linux-x86_64 reaches here; assertStdBarriers returns early on the other
 * targets, and Windows final std is produced on a path that does not call this
 * at all. Those remain unchecked, not proven clean.
 */
export const WRITE_BARRIER_FAIL_CLOSED = true;

export function assertWriteBarriers(disassembly, label, {failClosed = WRITE_BARRIER_FAIL_CLOSED} = {}) {
  const counts = inspectWriteBarriers(disassembly);
  const summary = `${label} phase_checks=${counts.phaseChecks} static_guarded=${counts.staticGuarded}`
    + ` unresolved=${counts.unresolved} bypassed=${counts.bypassed}`;

  // bypassed === 0 means "found no bypass", which is only good news if we found
  // anything at all. Two states reach zero while proving nothing, and both are
  // how this check fails in practice rather than in theory:
  //
  //   phase_checks === 0            the disassembly produced no fast-path
  //                                 machinery — wrong object, wrong objdump
  //                                 flags, or a build with no fast path at all
  //                                 (-O0 emits none: runOnFunction guards
  //                                 writeBarrierFastPath on OptLevel != None)
  //   nothing resolved to a callee  every phase check was found but none could
  //                                 be tied to a CJ_MCC_ call, which is exactly
  //                                 what an unlinked .a looks like when the
  //                                 relocations are not being read
  //
  // The second one is not hypothetical: during development, reading `-drwC`
  // output with the wrong field split produced phase_checks=426 with all 426
  // unresolved and bypassed=0, and the old code called that a PASS.
  //
  // The floor is "> 0" rather than a measured number because zero is the only
  // value that is definitionally "the device left no trace"; any positive count
  // is a real observation whose size depends on the package. For scale, the four
  // real std cores measured while building this check sit at 426, 467, 19 and 19
  // phase checks, so a legitimate build is nowhere near the floor.
  const resolved = counts.staticGuarded + counts.bypassed;
  const blind = counts.phaseChecks === 0 ? 'no-phase-checks-resolved'
    : resolved === 0 ? 'no-phase-check-tied-to-a-callee'
      : '';
  if (blind) {
    const reason = `STAGE3_WRITE_BARRIER_INDETERMINATE reason=${blind} ${summary}`;
    if (failClosed) throw new Error(reason);
    // ⭐ Report-only eats the verdict's exit code, never the device's: a check
    // that could not look is not reporting, it is broken. Same rule as
    // tools/emitpop_gate.sh, which exits 2 on an empty population in both modes.
    console.error(reason);
    console.error('STAGE3_WRITE_BARRIER_INDETERMINATE this run proves nothing about the write side');
    return counts;
  }

  if (counts.bypassed === 0) {
    console.log(`STAGE3_WRITE_BARRIER_PASS ${summary}`);
    return counts;
  }
  if (failClosed) throw new Error(`generational write barrier bypassed: ${summary}`);
  console.error(`STAGE3_WRITE_BARRIER_REPORT_ONLY ${summary}`);
  console.error('STAGE3_WRITE_BARRIER_REPORT_ONLY set WRITE_BARRIER_FAIL_CLOSED=true to block on this');
  return counts;
}
