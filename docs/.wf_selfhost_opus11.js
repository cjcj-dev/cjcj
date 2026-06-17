export const meta = {
  name: 'selfhost-opus-string',
  description: 'Extend real (non-facade) body lowering with first-class String: String let/var locals, concatenation with +, String params/returns, and println/print of String values; land a minimal cut first then expand; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus11"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: a REAL (non-facade) body-lowering path exists; read docs/DEISOLATION_PLAN.md and study\n" +
  "`git log --oneline -18`. Real path: packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + statement/\n" +
  "expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse adapter in\n" +
  "packages/frontend/src/RealParseBridge.cj + CodeGenBridge.cj. The real parser (packages/parse) drives bodies.\n" +
  "Today the real path covers Int64 (full arith/relational), Bool (full), if/else/while/for, break/continue,\n" +
  "user functions + recursion, and println/print of string LITERALS (via C-string+puts side-channel/in-body) +\n" +
  "runtime Int64/Bool values. The HARD part for String VARIABLES/CONCATENATION is the runtime String type:\n" +
  "investigate how packages/codegen and the Cangjie runtime represent String (CGCStringType / CGType / how\n" +
  "the REFERENCE cjc at /root/cj_build/cangjie_compiler lowers String literals, concat `+`, and println(String)\n" +
  "— inspect the reference C++ and the runtime symbols). You may need to call a runtime String-construct/concat\n" +
  "/print function via a real CHIR Apply (like the printf approach for ints).\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: Int64/Bool/control-flow/loops/funcs/recursion + all current print forms\n" +
  "(string literal, int literal, runtime int/bool, mixed `print(1);print(2);let y=1+2;println(y)`->123).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    supported: { type: "string" }, landedCut: { type: "string", description: "which String capabilities actually landed+verified" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact printed outputs for the String programs" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus11/string"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/s 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/s\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/s main\n" +
  "  cd " + WTROOT + "/s\n\n" +
  "TASK: Add first-class String support to the REAL body-lowering path, INCREMENTALLY. Land each cut\n" +
  "GREEN+VERIFIED+committed before starting the next, so partial progress is preserved:\n" +
  "  CUT 1 (minimal): String let/var local bound to a string literal, and println/print of that String\n" +
  "    variable prints its contents. Target: main() { let s = \"hello\"\\n println(s) } -> prints `hello`.\n" +
  "  CUT 2: concatenation with `+` of String values (literals and String vars). Targets:\n" +
  "    main() { let a = \"foo\"\\n let b = \"bar\"\\n println(a + b) } -> `foobar`;\n" +
  "    main() { var s = \"a\"\\n s = s + \"b\"\\n s = s + \"c\"\\n println(s) } -> `abc`.\n" +
  "  CUT 3: String function params and String return type. Target:\n" +
  "    func greet(name: String): String { return \"hi \" + name }\\n main() { println(greet(\"cj\")) } -> `hi cj`.\n" +
  "Use the real runtime String representation (study the reference cjc + runtime); lower literal->String,\n" +
  "concat, and println(String) via real CHIR (Apply to the runtime String/print functions as needed). Keep\n" +
  "ADDITIVE + GATED: anything outside the supported grammar/types falls back to the existing path (no\n" +
  "regression). Do NOT break existing string-literal println/print or int/bool prints.\n" +
  "VERIFY each landed cut via real compile+run. Re-run the ALREADY-VERIFIED slices (ints/bool/loops/funcs/\n" +
  "recursion/prints incl mixed->123, while_break->10). If only CUT 1 lands cleanly, that is acceptable\n" +
  "progress — commit it and report landedCut accurately (do NOT claim cuts you did not actually run).\n" +
  "Build green at each commit. Commit on " + BRANCH + ". Return schema; evidence MUST be real run outputs;\n" +
  "set landedCut to exactly what you verified.",
  { schema: SCHEMA, phase: 'Implement', label: 'string', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " landed=" + (impl && impl.landedCut) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "string slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "The String work landed these cuts (per implementer): " + (impl.landedCut || "(unknown)") + ".\n" +
  "Re-verify the LANDED String cuts with real runs AND this regression set (every line must hold):\n" +
  "  main() { let s = \"hello\"\\n println(s) }  -> hello   (if CUT1 landed)\n" +
  "  main() { let a=\"foo\"\\n let b=\"bar\"\\n println(a + b) } -> foobar  (if CUT2 landed)\n" +
  "  func greet(name: String): String { return \"hi \" + name }\\n main() { println(greet(\"cj\")) } -> hi cj  (if CUT3 landed)\n" +
  "  main(): Int64 { var s=0\\n var i=0\\n while(i<100){i=i+1\\n if(i==5){break}\\n s=s+i}\\n return s } -> exit 10\n" +
  "  main(): Int64 { var s=0\\n for (i in 0..5) { s=s+i }\\n return s } -> exit 10\n" +
  "  func fact(n: Int64): Int64 { if(n<=1){return 1}else{return n*fact(n-1)} }\\n main(): Int64 { return fact(5) } -> 120\n" +
  "  main(){ println(5 > 3) } -> true ; main(){ print(1)\\n print(2)\\n let y=1+2\\n println(y) } -> 123\n" +
  "  main(){ println(\"hello selfhost\") } -> hello selfhost ; main(){ println(42) } -> 42 ; main(): Int64 { return 2+3*4 } -> 14\n" +
  "Only verify String cuts that actually landed (per landedCut). Refresh docs/STATUS.md with the String\n" +
  "milestone (note which cuts) + remaining follow-ups. Clean up worktrees (git worktree remove --force " +
  WTROOT + "/s + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL applicable pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, landedCut: impl.landedCut, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
