export const meta = {
  name: 'selfhost-opus-real-expr',
  description: 'Implement the first REAL (non-facade) expression slice per docs/DEISOLATION_PLAN.md: lower main(){let a=2;let b=3;return a+b} through a real CHIR body (Allocate/Store/Load/Add/Exit) with no compile-time folding; then merge and re-verify all slices',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus3"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY): /root/cj_build/cangjie_compiler. Commits: NO AI attribution. Verify with real runs.\n" +
  "You write code yourself (Codex unavailable). Keep `cjpm build` green at every commit.\n" +
  "READ docs/DEISOLATION_PLAN.md IN FULL FIRST — it is the authoritative, file-and-line plan for this task.\n" +
  "ALREADY-VERIFIED slices that MUST NOT REGRESS (re-test them): println/print of string literals;\n" +
  "`return <int literal>` exit code; `let x=<int>; return x`; integer-arithmetic folded returns (e.g.\n" +
  "`return 2+3*4`->14); println/print of integers. The new real-body path must be ADDITIVE and GATED\n" +
  "(a `hasRealBody` flag defaulting false) so these existing behaviors are byte-for-byte unchanged.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" },
    commit: { type: "string" }, branch: { type: "string" },
    realAddConfirmed: { type: "boolean", description: "CHIR/IR dump shows a real Add (value NOT constant-folded)" },
    summary: { type: "string" }, evidence: { type: "string", description: "exact run output + dump excerpt proving runtime computation" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "opus3/real-expr"

phase('Implement')
const impl = await agent(
  PREAMBLE +
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/real 2>/dev/null; git branch -D " + BRANCH + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/real\n" +
  "  git worktree add -b " + BRANCH + " " + WTROOT + "/real main\n" +
  "  cd " + WTROOT + "/real\n\n" +
  "TASK: Implement the FIRST REAL EXPRESSION SLICE exactly as laid out in docs/DEISOLATION_PLAN.md\n" +
  "section 4 (steps 1-6), using the adapter approach (section 1b). Goal: the self-host cjc compiles\n" +
  "  main(): Int64 { let a = 2; let b = 3; return a + b }\n" +
  "to an executable that exits with code 5, where 5 is computed at RUNTIME by a real CHIR Add\n" +
  "(NOT folded in the frontend). Implementation outline (follow the plan's file/line references):\n" +
  "  1. packages/chir/src/AST2CHIR.cj: add `hasRealBody` + an ordered statement model\n" +
  "     (AST2CHIRStmtSpec: LocalLetLiteral / LocalLetBinary / ReturnExpr over Int64 locals+literals)\n" +
  "     to AST2CHIRFunctionSpec, with builder methods. Default off.\n" +
  "  2. new packages/chir/src/TranslateFuncBody.cj: CreateRealBody(fn, spec) emitting\n" +
  "     EnsureReturnSlot + Allocate/Constant/Store per let, Load/Load/CreateBinaryExpression(ADD) for\n" +
  "     a+b, store into return slot, CreateExit(result) — using existing CHIRBuilder calls and a\n" +
  "     HashMap<String,Value> for locals. Gate it FIRST in TranslateFuncDecl.LowerFunction\n" +
  "     (if hasRealBody -> CreateRealBody else existing branches).\n" +
  "  3-5. Frontend: run the real parser parse.Parser(...).ParseTopLevel() for the body and adapt\n" +
  "     parse.FuncBody.body (VarDecl-with-literal, VarDecl-with-binary, ReturnExpr) into the CHIR\n" +
  "     statement model on the AST2CHIRFunctionSpec built in CodeGenBridge.buildFunctionSpec; set\n" +
  "     hasRealBody=true ONLY when the whole body matches this small grammar, else fall back to the\n" +
  "     existing summary path (NO regression). Add `parse` to packages/frontend/cjpm.toml deps if needed.\n" +
  "     Handle the Int64 return type via the parsed retType.\n" +
  "  6. cjpm build green; then (" + RUNENV + ") compile+run the target -> exit 5; use\n" +
  "     `" + CJC + " --dump-chir --dump-to-screen <file>` to CONFIRM a real Add appears (set\n" +
  "     realAddConfirmed). Re-run ALL already-verified slices to confirm no regression.\n" +
  "If the full a+b proves too large, first land the plan's 'smallest first cut' (`let a=2; return a`,\n" +
  "real Allocate/Store/Load/Exit, no Add) GREEN+VERIFIED+committed, then add the Add case.\n" +
  "Commit on " + BRANCH + ". Return the schema; evidence MUST include the real run output and a CHIR dump excerpt.",
  { schema: SCHEMA, phase: 'Implement', label: 'real-expr', isolation: 'worktree' }
)

log("Implement: built=" + (impl && impl.built) + " verified=" + (impl && impl.verified) +
  " realAdd=" + (impl && impl.realAddConfirmed) + " commit=" + (impl && impl.commit))

if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "real-expr slice not landed; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE +
  "TASK: Merge branch " + BRANCH + " into main and keep everything green + verified.\n" +
  "  cd " + REPO + " && git merge --no-edit " + BRANCH + "\n" +
  "Run `cjpm build`; FIX any integration break. Then re-verify ALL with real runs (set runtime env;\n" +
  "binary " + CJC + "), every line must hold:\n" +
  "  main(): Int64 { let a = 2; let b = 3; return a + b }   -> exit 5 (REAL Add; confirm via --dump-chir)\n" +
  "  main(){ println(\"hello selfhost\") }                    -> prints hello selfhost\n" +
  "  main(){ print(\"a\"); print(\"b\"); println(\"c\") }         -> abc + newline\n" +
  "  main(): Int64 { return 7 }                              -> exit 7\n" +
  "  main(): Int64 { let x = 42\\n return x }                  -> exit 42\n" +
  "  main(): Int64 { return 2 + 3 * 4 }                      -> exit 14\n" +
  "  main(){ println(42)\\n let n=7\\n println(n) }             -> prints 42 then 7\n" +
  "Refresh docs/STATUS.md: add the real-expression milestone (first non-facade body lowering) and note\n" +
  "the remaining de-isolation follow-ups (more statement kinds, retire frontend summary parser). Clean up\n" +
  "worktrees (git worktree remove --force " + WTROOT + "/real + prune + rm -rf " + WTROOT + "). Commit.\n" +
  "Return schema (verified=ALL checks pass; realAddConfirmed from the dump).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, verified: impl.verified, realAdd: impl.realAddConfirmed, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, realAdd: merge && merge.realAddConfirmed, commit: merge && merge.commit },
}
