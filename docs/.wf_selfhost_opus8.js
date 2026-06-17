export const meta = {
  name: 'selfhost-opus-bool',
  description: 'Extend real (non-facade) body lowering with first-class Bool: Bool vars/params/returns, logical && || !, comparison results as values, conditions on Bool vars, and println of Bool (true/false); then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus8"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists and is the foundation to extend. Read\n" +
  "docs/DEISOLATION_PLAN.md and study `git log --oneline -14` (esp. real-expr a96db6e, control-flow 54659e9,\n" +
  "func-calls 7e207d0, print-runtime 5dbf2a2, mixed-print fix bf8315a). Real path: packages/chir/src/\n" +
  "TranslateFuncBody.cj (CreateRealBody) + statement/expr model in AST2CHIR.cj (hasRealBody), gated in\n" +
  "TranslateFuncDecl.cj; frontend real-parse adapter in packages/frontend/src/RealParseBridge.cj +\n" +
  "CodeGenBridge.cj. CHIR builds real blocks/branches/Apply; relational ops already produce Bool-typed\n" +
  "CHIR BinaryExpression used as branch conditions; codegen lowers them. The CHIR builder/types support Bool.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: real let/var/assign, Int64 arithmetic, relational, if/else, while,\n" +
  "user function calls + recursion, println/print of string/int literals AND runtime Int64 values (incl mixed).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the Bool programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus8/bool"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/b 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/b\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/b main\n" +
  "  cd " + WTROOT + "/b\n\n" +
  "TASK: Add first-class Bool support to the REAL body-lowering path:\n" +
  "  - Bool literals `true`/`false`; Bool-typed `let`/`var` locals, assignment, Bool function params and\n" +
  "    Bool return type; using a Bool var/param/expr directly as an if/while condition.\n" +
  "  - logical operators: `&&`, `||` (short-circuit is acceptable but a non-short-circuit lowering via\n" +
  "    And/Or on i1 is fine for this slice), and unary `!`.\n" +
  "  - comparison results (a relational BinaryExpr) usable as a Bool value (stored in a Bool local, returned,\n" +
  "    passed as an arg), not only inline as a branch condition.\n" +
  "  - `println(<bool>)` / `print(<bool>)` print `true` / `false` (lower like the runtime-int print but pick\n" +
  "    the string based on the i1 value — e.g. select between two format/string globals, or call a tiny\n" +
  "    helper; reuse the in-body print mechanism added for runtime ints).\n" +
  "Use the existing real CHIR primitives/types (Bool/i1). Keep ADDITIVE + GATED: unsupported constructs fall\n" +
  "back to the existing path (no regression).\n" +
  "PRIMARY TARGETS:\n" +
  "  main(): Int64 { let b = 3 > 2\\n if (b) { return 1 } else { return 0 } }                  -> exit 1\n" +
  "  main(): Int64 { let a = true\\n let b = false\\n if (a && !b) { return 7 } else { return 0 } } -> exit 7\n" +
  "  func isEven(n: Int64): Bool { return n % 2 == 0 }\\n main(): Int64 { if (isEven(10)) { return 1 } else { return 0 } } -> exit 1\n" +
  "  main() { println(5 > 3)\\n println(2 > 4) }                                                -> prints `true` then `false`\n" +
  "  main() { let ok = true\\n println(ok) }                                                    -> prints `true`\n" +
  "Confirm via real compile+run. Re-run the ALREADY-VERIFIED slices (ints/loops/funcs/recursion/prints incl\n" +
  "mixed `print(1);print(2);let y=1+2;println(y)`->`123`). If too large in one pass, land a smaller\n" +
  "GREEN+VERIFIED+committed cut first (Bool literals + Bool var + if on bool), then logical ops, then bool print.\n" +
  "Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST include the true/false prints.",
  { schema: SCHEMA, phase: 'Implement', label: 'bool', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "bool slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify ALL with real runs (runtime env; binary " + CJC + "); every line must hold:\n" +
  "  main(): Int64 { let b = 3 > 2\\n if (b) { return 1 } else { return 0 } }  -> exit 1\n" +
  "  main(): Int64 { let a = true\\n let b = false\\n if (a && !b) { return 7 } else { return 0 } } -> exit 7\n" +
  "  func isEven(n: Int64): Bool { return n % 2 == 0 }\\n main(): Int64 { if (isEven(10)) {return 1} else {return 0} } -> exit 1\n" +
  "  main() { println(5 > 3)\\n println(2 > 4) }  -> true / false\n" +
  "  main() { print(1)\\n print(2)\\n let y=1+2\\n println(y) } -> 123 ; main(){ println(fact(10)) } (fact defined) -> 3628800\n" +
  "  main(): Int64 { return fact(5) } -> 120 ; main(): Int64 { var s=0\\n var i=1\\n while(i<=5){s=s+i\\n i=i+1}\\n return s } -> 15\n" +
  "  main(){ println(\"hello selfhost\") } -> hello selfhost ; main(): Int64 { return 2+3*4 } -> 14\n" +
  "Refresh docs/STATUS.md with the Bool milestone + remaining follow-ups (String values, for-in, more types,\n" +
  "retire summary parser / unify ASTs). Clean up worktrees (git worktree remove --force " + WTROOT +
  "/b + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
