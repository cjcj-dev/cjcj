export const meta = {
  name: 'selfhost-opus-print-runtime',
  description: 'Extend real (non-facade) body lowering so println/print of RUNTIME Int64 values (variables, arithmetic, function results) emit real output as in-body calls; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus6"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY): /root/cj_build/cangjie_compiler. Commits: NO AI attribution. Verify with real runs.\n" +
  "You write code yourself (Codex unavailable). Keep `cjpm build` green at every commit.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study recent\n" +
  "commits: `git log --oneline -10`, `git show 7e207d0 --stat` (func calls), 54659e9 (control flow),\n" +
  "a96db6e (first real body). Real path = packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement\n" +
  "model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend. The CHIR builder has Apply; codegen lowers Apply (packages/codegen/src/ApplyImpl.cj)\n" +
  "and can call C/foreign functions (it already declares + calls runtime funcs in EmitPackageIR.cj; the int\n" +
  "literal print side-channel in EmitPrintIR.cj emits a real libc printf with a format-string global).\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: real let/var/assign, arithmetic, relational, if/else, while, user\n" +
  "function calls + recursion (fact(5)->120, add(2,mul(3,4))->14), string println/print, int-literal\n" +
  "println/print, literal/folded-arith returns. Exit codes are CLAMPED to 0..255 by the runtime (matches\n" +
  "reference) so VERIFY PRINTED OUTPUT for values >255 (e.g. fact(10)).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" },
    commit: { type: "string" }, branch: { type: "string" },
    runtimePrintConfirmed: { type: "boolean", description: "a computed (non-literal) value was printed correctly" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact printed outputs (esp. loop sum 55 and fact(10) 3628800)" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus6/print-runtime"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/pr 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/pr\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/pr main\n" +
  "  cd " + WTROOT + "/pr\n\n" +
  "TASK: In the REAL body-lowering path, support println(<int expr>) and print(<int expr>) where the argument\n" +
  "is a RUNTIME Int64 value (a local var/let, an arithmetic expression, or a user-function-call result) — not\n" +
  "just a literal. The print must execute AT ITS POSITION in the body (after preceding statements run), so it\n" +
  "must be lowered as a real in-body statement that evaluates the expression to a CHIR value and then calls a\n" +
  "C print routine on it (e.g. a real CHIR Apply to libc `printf` with a private \"%ld\\n\" / \"%ld\" format-string\n" +
  "global and the Int64 value as the variadic arg; declare printf as a foreign/variadic C function — see how\n" +
  "EmitPrintIR.cj / EmitPackageIR.cj declare and call C functions, and the isCFunc/hasVariableLenArg support\n" +
  "in the function spec). Do NOT use the entry-block side-channel for runtime values (it cannot see values\n" +
  "computed later). Keep the existing literal-string/literal-int print behavior working. Keep ADDITIVE + GATED:\n" +
  "any unsupported construct falls back to the existing path (no regression).\n" +
  "PRIMARY TARGETS (verify PRINTED output):\n" +
  "  main() { let x = 6 * 7\\n println(x) }                                                  -> prints 42\n" +
  "  main() { var s = 0\\n var i = 1\\n while (i <= 10) { s = s + i\\n i = i + 1 }\\n println(s) } -> prints 55\n" +
  "  func fact(n: Int64): Int64 { if (n<=1){return 1} else {return n*fact(n-1)} }\\n main() { println(fact(10)) } -> prints 3628800\n" +
  "  main() { print(1)\\n print(2)\\n let y = 1 + 2\\n println(y) }                              -> prints `123` then newline (12 then 3)\n" +
  "Set runtimePrintConfirmed when a computed value prints correctly. Re-run the ALREADY-VERIFIED slices\n" +
  "(funcs/recursion/loops/strings/literal-int prints) to confirm no regression. If too large in one pass,\n" +
  "land a smaller GREEN+VERIFIED+committed cut first (println of a local var), then expressions, then call\n" +
  "results. Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST include 55 and 3628800.",
  { schema: SCHEMA, phase: 'Implement', label: 'print-runtime', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " runtimePrint=" + (impl && impl.runtimePrintConfirmed) + " commit=" + (impl && impl.commit))

if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "print-runtime slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify ALL with real runs (runtime env; binary " + CJC + "); every line must hold:\n" +
  "  main() { var s=0\\n var i=1\\n while (i<=10){ s=s+i\\n i=i+1 }\\n println(s) }              -> prints 55\n" +
  "  func fact(n: Int64): Int64 { if(n<=1){return 1}else{return n*fact(n-1)} }\\n main(){ println(fact(10)) } -> prints 3628800\n" +
  "  func add(a: Int64, b: Int64): Int64 { return a + b }\\n main(): Int64 { return add(2, 3) }  -> exit 5\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) }                        -> exit 120\n" +
  "  main(): Int64 { var sum=0\\n var i=1\\n while(i<=5){sum=sum+i\\n i=i+1}\\n return sum }        -> exit 15\n" +
  "  main(){ println(\"hello selfhost\") } -> hello selfhost ; main(){ println(42) } -> 42 ; main(): Int64 { return 2+3*4 } -> 14\n" +
  "Refresh docs/STATUS.md with the runtime-print milestone + remaining follow-ups (Bool/String values, more\n" +
  "operators, for-in, retire summary parser / unify ASTs). Clean up worktrees (git worktree remove --force " +
  WTROOT + "/pr + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass; runtimePrintConfirmed).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, runtimePrint: impl.runtimePrintConfirmed, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, runtimePrint: merge && merge.runtimePrintConfirmed, commit: merge && merge.commit },
}
