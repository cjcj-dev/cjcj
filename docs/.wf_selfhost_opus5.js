export const meta = {
  name: 'selfhost-opus-func-calls',
  description: 'Extend real (non-facade) body lowering to user-defined function calls (parameters, return values, multiple functions, recursion) via real CHIR Apply; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus5"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY): /root/cj_build/cangjie_compiler. Commits: NO AI attribution. Verify with real runs.\n" +
  "NOTE on exit codes: the Cangjie runtime CLAMPS process exit codes to 0..255 (matches the reference cjc);\n" +
  "use return values <= 255 in tests, or print values, to verify correctness.\n" +
  "You write code yourself (Codex unavailable). Keep `cjpm build` green at every commit.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists and is the foundation to extend. Read:\n" +
  "  - docs/DEISOLATION_PLAN.md (architecture).\n" +
  "  - packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement model in AST2CHIR.cj\n" +
  "    (hasRealBody + AST2CHIRStmtSpec), gated in TranslateFuncDecl.cj LowerFunction.\n" +
  "  - frontend real-parse adapter (commits a96db6e then 54659e9 added var/assign/if/while). Study them:\n" +
  "    `git log --oneline -8` then `git show 54659e9 --stat` and `git show a96db6e --stat`.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: real let/var/assign, arithmetic (+ - * / %), relational, if/else,\n" +
  "while loops (e.g. sum 1..5 -> 15); string/int println/print; literal & folded-arith returns.\n" +
  "The CHIR builder has Apply (function call) and codegen lowers Apply (see packages/codegen ApplyImpl.cj).\n" +
  "Functions are lowered into the package; you can resolve a callee Function by name (chir package lookup,\n" +
  "e.g. TryGetFunction / package global funcs) inside the real-body translator.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" },
    commit: { type: "string" }, branch: { type: "string" },
    recursionConfirmed: { type: "boolean", description: "a recursive user function computed correctly at runtime" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact run outputs for the call/recursion programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus5/func-calls"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/fc 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/fc\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/fc main\n" +
  "  cd " + WTROOT + "/fc\n\n" +
  "TASK: Extend the REAL body-lowering path to support USER-DEFINED FUNCTION CALLS for Int64:\n" +
  "  - calling a user function with value arguments and using its return value in expressions / let / var /\n" +
  "    return / call args (e.g. `add(2, mul(3,4))`);\n" +
  "  - multiple top-level functions; and RECURSION (a function calling itself).\n" +
  "Implement by: (a) the frontend real-parse adapter recognizing parse.CallExpr whose callee is a simple\n" +
  "function name (RefExpr) with Int64-expression args, mapping it into the CHIR statement/expr model; the\n" +
  "non-main functions must ALSO go through the real body path (their bodies parsed by the real parser), not\n" +
  "just main. (b) the CHIR real-body translator (TranslateFuncBody.cj) emitting a real Apply to the resolved\n" +
  "callee Function (resolve by mangled/identifier name among lowered package functions; ensure callee is\n" +
  "lowered before/independently of the call site — function lowering order must not matter, so resolve the\n" +
  "callee Function reference at lowering time, creating/declaring it if needed). Keep ADDITIVE + GATED:\n" +
  "any unsupported construct falls back to the existing summary/fold path (no regression).\n" +
  "PRIMARY TARGETS (must run, runtime-computed):\n" +
  "  func add(a: Int64, b: Int64): Int64 { return a + b }\\n main(): Int64 { return add(2, 3) }            -> exit 5\n" +
  "  func sq(x: Int64): Int64 { return x * x }\\n main(): Int64 { let r = sq(7)\\n return r }                 -> exit 49\n" +
  "  func fact(n: Int64): Int64 { if (n <= 1) { return 1 } else { return n * fact(n - 1) } }\\n main(): Int64 { return fact(5) }  -> exit 120 (recursion; set recursionConfirmed)\n" +
  "Use `" + CJC + " --dump-chir --dump-to-screen <file>` to confirm a real Apply (call) appears. Re-run the\n" +
  "ALREADY-VERIFIED slices (loops/conditionals/strings) to confirm no regression. If too large in one pass,\n" +
  "land a smaller GREEN+VERIFIED+committed cut first (non-recursive 2-arg call), then add recursion.\n" +
  "Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST include fact(5)->120.",
  { schema: SCHEMA, phase: 'Implement', label: 'func-calls', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " recursion=" + (impl && impl.recursionConfirmed) + " commit=" + (impl && impl.commit))

if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "func-calls slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify ALL with real runs (runtime env; binary " + CJC + "); every line must hold:\n" +
  "  func add(a: Int64, b: Int64): Int64 { return a + b }\\n main(): Int64 { return add(2, 3) }   -> exit 5\n" +
  "  func fact(n: Int64): Int64 { if (n<=1){return 1} else {return n*fact(n-1)} }\\n main(): Int64 { return fact(5) } -> exit 120\n" +
  "  main(): Int64 { var sum=0\\n var i=1\\n while (i<=5){ sum=sum+i\\n i=i+1 }\\n return sum }       -> exit 15\n" +
  "  main(): Int64 { let a=7\\n if (a>3){return 1} else {return 0} }                             -> exit 1\n" +
  "  main(): Int64 { let a=2\\n let b=3\\n return a+b }  -> 5 ;  main(){ println(\"hello selfhost\") } -> hello selfhost\n" +
  "  main(): Int64 { return 2 + 3 * 4 } -> 14 ;  main(){ println(42) } -> 42\n" +
  "Refresh docs/STATUS.md with the function-calls milestone + remaining follow-ups (println of runtime values,\n" +
  "more types/strings, retire summary parser). Clean up worktrees (git worktree remove --force " + WTROOT +
  "/fc + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass; recursionConfirmed).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, recursion: impl.recursionConfirmed, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, recursion: merge && merge.recursionConfirmed, commit: merge && merge.commit },
}
