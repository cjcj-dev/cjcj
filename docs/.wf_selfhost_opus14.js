export const meta = {
  name: 'selfhost-opus-match',
  description: 'Add match expressions on Int64 (literal patterns, wildcard _, variable binding; as statement and as value-producing expression) to the real body path; incremental cuts; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus14"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -24`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. The real parser (packages/parse) parses\n" +
  "match expressions (MatchExpr, MatchCase, patterns incl ConstPattern/VarPattern/WildcardPattern). if/else,\n" +
  "while, real CHIR blocks/branches, value-producing if are available; relational ops produce Bool.\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/String(+interpolation)/control-flow/loops(for+while)/\n" +
  "break/continue/funcs/recursion/arrays(Array<Int64> literal/index/size/for-in) + all print forms. Real\n" +
  "programs (FizzBuzz, fib loop, repeat->ababab, find-max-in-array) work end-to-end — keep them working.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    landedCut: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact outputs/exit codes for the match programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus14/match"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/m 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/m\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/m main\n" +
  "  cd " + WTROOT + "/m\n\n" +
  "TASK: Add `match` on an Int64 selector to the REAL body path, INCREMENTALLY (commit each cut green+verified):\n" +
  "  CUT 1: match as a STATEMENT with Int64 literal patterns (`case 1 =>`), wildcard (`case _ =>`), each arm a\n" +
  "    block of statements. Desugar to a chain of compares/branches on the selector value (reuse existing\n" +
  "    if/else + CHIR block machinery). Selector evaluated once.\n" +
  "    Target: main() { let d = 3\\n match (d) { case 1 => println(\"one\")\\n case 2 => println(\"two\")\\n case _ => println(\"many\") } } -> prints `many`\n" +
  "  CUT 2: match as a value-producing EXPRESSION (each arm yields a value of a common type), usable in\n" +
  "    let/var/return/print.\n" +
  "    Target: main(): Int64 { let x = 2\\n let r = match (x) { case 1 => 100\\n case _ => 200 }\\n return r } -> exit 200\n" +
  "    Target: main(): Int64 { let x=2\\n match (x) { case 1 => return 10\\n case 2 => return 20\\n case _ => return 0 } } -> exit 20\n" +
  "  CUT 3: variable-binding pattern (`case n => ...` binds the selector to n in that arm) and multiple\n" +
  "    literal values per case if easy (`case 1 | 2 => ...`); skip `|` if hard.\n" +
  "    Target: main(): Int64 { let x = 7\\n match (x) { case 0 => return -1\\n case n => return n + 1 } } -> exit 8\n" +
  "Keep ADDITIVE + GATED: unsupported match forms (enum patterns, guards, complex destructuring) fall back to\n" +
  "the existing path (no regression). Verify each landed cut via real compile+run. Re-run ALREADY-VERIFIED\n" +
  "slices (FizzBuzz, fib loop, repeat->ababab, interp x=42, array find-max->8, while_break->10, fact(5)->120,\n" +
  "mixed->123). If only CUT 1 lands cleanly, that is acceptable — commit it and report landedCut ACCURATELY\n" +
  "(an independent verifier re-checks every claim; do NOT over-claim). Build green at each commit. Commit on\n" +
  BRANCH + ". Return schema; evidence MUST be real run outputs; set landedCut to exactly what you verified.",
  { schema: SCHEMA, phase: 'Implement', label: 'match', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "match slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The match work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify LANDED match cuts with real runs AND this regression set (every line must hold):\n" +
  "  main(){ let d=3\\n match(d){ case 1=>println(\"one\")\\n case 2=>println(\"two\")\\n case _=>println(\"many\") } } -> many  (CUT1)\n" +
  "  main(): Int64 { let x=2\\n let r=match(x){ case 1=>100\\n case _=>200 }\\n return r } -> 200  (CUT2)\n" +
  "  main(): Int64 { let x=7\\n match(x){ case 0=>return -1\\n case n=>return n+1 } } -> 8  (CUT3)\n" +
  "  main() { let x=42\\n println(\"x=${x}\") } -> x=42 ; main(){ let a=[5,3,8,1]\\n var mx=a[0]\\n for(x in a){if(x>mx){mx=x}}\\n println(mx) } -> 8\n" +
  "  FizzBuzz 1..15 correct ; fib loop -> 0 1 1 2 3 5 8 13 21 34 ; repeat(\"ab\",3) -> ababab\n" +
  "  main(): Int64 { var s=0\\n var i=0\\n while(i<100){i=i+1\\n if(i==5){break}\\n s=s+i}\\n return s } -> 10\n" +
  "  func fact(n: Int64): Int64 {...}\\n main(): Int64 { return fact(5) } -> 120 ; main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123\n" +
  "Only verify match cuts that actually landed. Refresh docs/STATUS.md with the match milestone + remaining\n" +
  "gaps (enum/match-on-enum, structs/classes, Float64, lambdas, generics, collections, silent-fallback\n" +
  "hardening). Clean up worktrees (git worktree remove --force " + WTROOT + "/m + prune + rm -rf " + WTROOT +
  "). Commit. Return schema (verified=ALL applicable pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
