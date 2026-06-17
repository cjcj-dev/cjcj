export const meta = {
  name: 'selfhost-opus-control-flow',
  description: 'Extend the real (non-facade) body lowering to mutable var + assignment + relational ops + if/else + while, so a real loop algorithm compiles and runs; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus4"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY): /root/cj_build/cangjie_compiler. Commits: NO AI attribution. Verify with real runs.\n" +
  "You write code yourself (Codex unavailable). Keep `cjpm build` green at every commit.\n" +
  "BACKGROUND: A REAL (non-facade) body-lowering path already exists and is the foundation to extend:\n" +
  "  - docs/DEISOLATION_PLAN.md (the architecture); read it.\n" +
  "  - packages/chir/src/TranslateFuncBody.cj (CreateRealBody) + the statement model in\n" +
  "    packages/chir/src/AST2CHIR.cj (hasRealBody + AST2CHIRStmtSpec) — gated branch in\n" +
  "    packages/chir/src/TranslateFuncDecl.cj LowerFunction.\n" +
  "  - The frontend adapter that runs the REAL parser (packages/parse Parser.ParseTopLevel) and maps\n" +
  "    parse.FuncBody statements into that model (in packages/frontend, see CodeGenBridge.cj / the real-parse\n" +
  "    bridge added by commit a96db6e). Study commit a96db6e (`git show a96db6e --stat` and the diffs).\n" +
  "ALREADY VERIFIED, MUST NOT REGRESS: real `let a=2;let b=3;return a+b`->5 (runtime Add); string\n" +
  "println/print; literal/arith/let returns; println/print(<int>). The CHIR builder already has blocks,\n" +
  "CreateBranch/CreateMultiBranch/conditional terminators, and codegen lowers blocks/branches generically.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" },
    commit: { type: "string" }, branch: { type: "string" },
    loopConfirmed: { type: "boolean", description: "a real while-loop program computed the right value at runtime" },
    supported: { type: "string", description: "which constructs now lower through the real path" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact run outputs proving the loop/conditional work" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus4/control-flow"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/cf 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/cf\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/cf main\n" +
  "  cd " + WTROOT + "/cf\n\n" +
  "TASK: Extend the REAL body-lowering path (NOT the facade/folding path) to support, for Int64 locals:\n" +
  "  (1) mutable `var x = <expr>` and reassignment `x = <expr>` (reuse the local name->slot map; a var is an\n" +
  "      Allocate slot; assignment is a Store to the existing slot);\n" +
  "  (2) relational operators in expressions: < <= > >= == != (CHIR has these; codegen lowers them);\n" +
  "  (3) `if (cond) { ... } else { ... }` and `while (cond) { ... }` using real CHIR basic blocks +\n" +
  "      conditional branch terminators (study how CHIRBuilder creates blocks/branches; codegen already\n" +
  "      walks successors generically).\n" +
  "Extend BOTH the CHIR statement/translator model (packages/chir: AST2CHIR.cj statement specs +\n" +
  "TranslateFuncBody.cj CreateRealBody) AND the frontend adapter (map parse.IfExpr/WhileExpr/AssignExpr/\n" +
  "var-VarDecl/BinaryExpr-with-relational into the model). Keep it ADDITIVE and GATED: any body containing a\n" +
  "construct outside the supported real grammar must fall back to the existing summary/fold path (no regression).\n" +
  "PRIMARY TARGET (must run, computed at runtime, NO folding):\n" +
  "  main(): Int64 { var sum = 0\\n var i = 1\\n while (i <= 5) { sum = sum + i\\n i = i + 1 }\\n return sum }  -> exit 15\n" +
  "ALSO verify:\n" +
  "  main(): Int64 { var x = 2\\n x = x + 3\\n return x }  -> exit 5\n" +
  "  main(): Int64 { let a = 7\\n if (a > 3) { return 1 } else { return 0 } }  -> exit 1\n" +
  "Confirm via `" + CJC + " --dump-chir --dump-to-screen <file>` that loops/branches produce real CHIR blocks\n" +
  "(multiple Blocks + Branch), not folded constants (set loopConfirmed). Re-run the ALREADY-VERIFIED slices.\n" +
  "If the full set is too large in one pass, land a smaller GREEN+VERIFIED+committed cut first (e.g. var+assign+\n" +
  "return, then add while, then if), committing as you go. Build green in your worktree at each commit.\n" +
  "Commit on " + BRANCH + ". Return schema; evidence MUST include the real run outputs (esp. the loop -> 15).",
  { schema: SCHEMA, phase: 'Implement', label: 'control-flow', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " loop=" + (impl && impl.loopConfirmed) + " commit=" + (impl && impl.commit))

if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "control-flow slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main, keep green, re-verify, refresh status.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any break).\n" +
  "Re-verify ALL with real runs (set runtime env; binary " + CJC + "); every line must hold:\n" +
  "  main(): Int64 { var sum=0\\n var i=1\\n while (i<=5){ sum=sum+i\\n i=i+1 }\\n return sum }  -> exit 15\n" +
  "  main(): Int64 { var x = 2\\n x = x + 3\\n return x }                                        -> exit 5\n" +
  "  main(): Int64 { let a = 7\\n if (a > 3) { return 1 } else { return 0 } }                    -> exit 1\n" +
  "  main(): Int64 { let a = 2\\n let b = 3\\n return a + b }                                      -> exit 5\n" +
  "  main(){ println(\"hello selfhost\") }   -> hello selfhost ;  main(): Int64 { return 7 } -> exit 7\n" +
  "  main(): Int64 { return 2 + 3 * 4 } -> 14 ;  main(){ println(42) } -> 42\n" +
  "Refresh docs/STATUS.md with the control-flow milestone + remaining de-isolation follow-ups (function calls,\n" +
  "println of runtime values, retire summary parser). Clean up worktrees (git worktree remove --force " +
  WTROOT + "/cf + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=ALL pass; loopConfirmed).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, loop: impl.loopConfirmed, supported: impl.supported, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, loop: merge && merge.loopConfirmed, commit: merge && merge.commit },
}
