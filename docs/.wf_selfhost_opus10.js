export const meta = {
  name: 'selfhost-opus-fix-while-bc',
  description: 'Fix break/continue inside standalone while loops (currently such bodies fall back to the summary path and silently return 0); verify thoroughly and keep all slices green',
  phases: [
    { title: 'Fix' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "Commits: NO AI attribution. You write code yourself (Codex unavailable). Keep `cjpm build` green.\n" +
  "BACKGROUND: real (non-facade) body lowering lives in packages/chir/src/TranslateFuncBody.cj (CreateRealBody)\n" +
  "+ statement/expr model in AST2CHIR.cj (hasRealBody), gated in TranslateFuncDecl.cj; frontend real-parse\n" +
  "adapter in packages/frontend/src/RealParseBridge.cj. `for (v in a..b)` desugars to a while with break/continue\n" +
  "support via a loop-block stack (commit 6e75a65). Read that commit: `git show 6e75a65`.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" },
    rootCause: { type: "string" }, fix: { type: "string" }, summary: { type: "string" }, evidence: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

phase('Fix')
const fix = await agent(
  PREAMBLE +
  "Work directly on main in " + REPO + " (single agent, no worktree).\n\n" +
  "BUG (reproduce first, runtime env set): `break`/`continue` work inside `for` loops but NOT inside a\n" +
  "standalone `while` loop. A while body containing break or continue is NOT adapted by the real path and\n" +
  "falls back to the summary path, so the function silently returns 0 (CHIR dump shows only `Exit`). Repro:\n" +
  "  while_break (expect 10): main(): Int64 { var s=0\\n var i=0\\n while (i<100){ i=i+1\\n if(i==5){break}\\n s=s+i }\\n return s }\n" +
  "  while_cont  (expect 12): main(): Int64 { var s=0\\n var i=0\\n while (i<5){ i=i+1\\n if(i==3){continue}\\n s=s+i }\\n return s }\n" +
  "  combined    (expect 18): main(): Int64 { var s=0\\n var i=0\\n while (i<10){ i=i+1\\n if(i==3){continue}\\n if(i==7){break}\\n s=s+i }\\n return s }\n" +
  "Both currently return 0. Plain while (no break/continue) works (->15), and for-loop break/continue work\n" +
  "(0..100 break@5 ->10; 0..6 continue@3 ->12) — do not regress those.\n\n" +
  "ROOT CAUSE then FIX: the standalone `while` lowering does not register its (continueTarget=cond block,\n" +
  "breakTarget=exit block) on the loop stack the way the `for` desugaring does, so a while body with break/\n" +
  "continue isn't recognized by the adapter/translator and the whole function falls back. Make the real path\n" +
  "support break/continue in standalone while loops: push the while's cond block as the continue target and\n" +
  "its exit block as the break target onto the same loop stack used by `for`, and ensure the adapter accepts\n" +
  "while bodies containing break/continue (no fallback). Nested loops must resolve to the innermost loop.\n" +
  "Keep additive/gated; bodies still outside the supported grammar fall back as before.\n\n" +
  "VERIFY (build green; runtime env; binary " + CJC + "); EVERY line must hold:\n" +
  "  while_break -> exit 10 ; while_cont -> exit 12 ; combined -> exit 18\n" +
  "  for break (var s=0\\n for(i in 0..100){if(i==5){break}\\n s=s+i}\\n return s) -> 10\n" +
  "  for continue (var s=0\\n for(i in 0..6){if(i==3){continue}\\n s=s+i}\\n return s) -> 12\n" +
  "  plain while (var s=0\\n var i=1\\n while(i<=5){s=s+i\\n i=i+1}\\n return s) -> 15\n" +
  "  for(i in 1..=5) sum -> 15 ; for(i in 0..3){println(i)} -> 0/1/2\n" +
  "  fact(5) -> exit 120 ; main(){let a=true\\n let b=false\\n if(a&&!b){return 7}else{return 0}} -> 7\n" +
  "  main(){print(1)\\n print(2)\\n let y=1+2\\n println(y)} -> 123 ; main(){println(\"hello selfhost\")} -> hello selfhost\n" +
  "Use `--dump-chir --dump-to-screen` on the combined case to confirm real blocks/branches (not just Exit).\n" +
  "Then `git add -A && git commit` on main. Return schema with rootCause + fix + evidence (10/12/18).",
  { schema: SCHEMA, phase: 'Fix', label: 'fix-while-bc' }
)

return { fix: { built: fix && fix.built, verified: fix && fix.verified, commit: fix && fix.commit, rootCause: fix && fix.rootCause } }
