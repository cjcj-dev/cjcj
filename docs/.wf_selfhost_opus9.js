export const meta = {
  name: 'selfhost-opus-loops',
  description: 'Extend real (non-facade) body lowering with for-in over integer ranges (.. and ..=) plus break/continue in for/while loops, via real CHIR blocks/branches; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus9"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists. Read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -16` (control-flow 54659e9 added while/if via real CHIR blocks: while.cond/body/exit,\n" +
  "if.then/else/join with CreateBranch/CreateGoTo). Real path: packages/chir/src/TranslateFuncBody.cj\n" +
  "(CreateRealBody) + statement/expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj;\n" +
  "frontend real-parse adapter in packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64 let/var/assign, +-*/% , relational, if/else, while, user\n" +
  "function calls + recursion, Bool (literals/vars/params/returns, && || !, comparison-as-value, println bool),\n" +
  "println/print of string/int literals + runtime Int64 values (incl mixed). Cangjie ranges: `a..b` is\n" +
  "half-open [a,b); `a..=b` is inclusive [a,b].\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the loop programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus9/loops"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/l 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/l\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/l main\n" +
  "  cd " + WTROOT + "/l\n\n" +
  "TASK: Extend the REAL body-lowering path with richer loops for Int64:\n" +
  "  (1) `for (v in a..b) { body }` and `for (v in a..=b) { body }` where a,b are Int64 expressions —\n" +
  "      desugar to the existing real while-loop lowering: introduce a fresh Int64 induction local v = a,\n" +
  "      loop while (v < b) (or v <= b for ..=), run body, then v = v + 1. v is a normal local readable in body.\n" +
  "  (2) `break` and `continue` inside for AND while loops — lower to real CHIR gotos: break -> branch to the\n" +
  "      loop's exit block; continue -> branch to the loop's update/cond block (for `for`, continue must still\n" +
  "      run the v = v + 1 increment, so continue targets the increment/cond, not skipping it). Maintain a\n" +
  "      stack of (continueTarget, breakTarget) blocks so nested loops and break/continue resolve to the\n" +
  "      innermost loop.\n" +
  "Keep ADDITIVE + GATED: unsupported constructs fall back to the existing path (no regression).\n" +
  "PRIMARY TARGETS:\n" +
  "  main(): Int64 { var s = 0\\n for (i in 0..5) { s = s + i }\\n return s }                 -> exit 10 (0+1+2+3+4)\n" +
  "  main(): Int64 { var s = 0\\n for (i in 1..=5) { s = s + i }\\n return s }                -> exit 15\n" +
  "  main() { for (i in 0..3) { println(i) } }                                               -> prints 0,1,2 (each line)\n" +
  "  main(): Int64 { var s = 0\\n for (i in 0..100) { if (i == 5) { break }\\n s = s + i }\\n return s } -> exit 10\n" +
  "  main(): Int64 { var s = 0\\n for (i in 0..6) { if (i == 3) { continue }\\n s = s + i }\\n return s }  -> exit 12 (0+1+2+4+5)\n" +
  "  main(): Int64 { var s = 0\\n var i = 0\\n while (i < 10) { i = i + 1\\n if (i == 3) { continue }\\n if (i == 7) { break }\\n s = s + i }\\n return s } -> exit 1+2+4+5+6=18\n" +
  "Confirm via real compile+run. Re-run ALREADY-VERIFIED slices (ints/bool/funcs/recursion/prints/while).\n" +
  "If too large in one pass, land a smaller GREEN+VERIFIED+committed cut first (for-in .. only), then ..=,\n" +
  "then break/continue. Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST\n" +
  "include the break(10) and continue(12) exit codes.",
  { schema: SCHEMA, phase: 'Implement', label: 'loops', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "loops slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify ALL with real runs (runtime env; binary " + CJC + "); every line must hold:\n" +
  "  main(): Int64 { var s=0\\n for (i in 0..5) { s=s+i }\\n return s }                        -> exit 10\n" +
  "  main(): Int64 { var s=0\\n for (i in 1..=5) { s=s+i }\\n return s }                       -> exit 15\n" +
  "  main(): Int64 { var s=0\\n for (i in 0..100) { if (i==5){break}\\n s=s+i }\\n return s }    -> exit 10\n" +
  "  main(): Int64 { var s=0\\n for (i in 0..6) { if (i==3){continue}\\n s=s+i }\\n return s }    -> exit 12\n" +
  "  main(){ for (i in 0..3) { println(i) } }  -> 0/1/2\n" +
  "  func isEven(n: Int64): Bool { return n%%2==0 }\\n main(): Int64 { if(isEven(10)){return 1}else{return 0} } -> exit 1\n" +
  "  main(){ println(5 > 3) } -> true ; main(){ print(1)\\n print(2)\\n let y=1+2\\n println(y) } -> 123\n" +
  "  func fact(n: Int64): Int64 { if(n<=1){return 1}else{return n*fact(n-1)} }\\n main(): Int64 { return fact(5) } -> exit 120\n" +
  "  main(): Int64 { var s=0\\n var i=1\\n while(i<=5){s=s+i\\n i=i+1}\\n return s } -> 15 ; main(){ println(\"hello selfhost\") } -> hello selfhost\n" +
  "Refresh docs/STATUS.md with the richer-loops milestone + remaining follow-ups (String values, more types,\n" +
  "retire summary parser / unify ASTs). Clean up worktrees (git worktree remove --force " + WTROOT +
  "/l + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
