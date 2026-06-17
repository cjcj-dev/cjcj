export const meta = {
  name: 'selfhost-opus-advance-2',
  description: 'Second Opus-driven advance: integer-arithmetic returns, println(int), and a concrete de-isolation plan, via concurrent worktree-isolated agents; then merge and re-verify',
  phases: [
    { title: 'Expand' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus2"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (git, branch main). Build: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "To RUN the self-host cjc set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY): /root/cj_build/cangjie_compiler. Commits: NO AI attribution.\n" +
  "You write code yourself (Codex unavailable). Keep `cjpm build` green. Verify every claim with real runs.\n" +
  "CONTEXT: the integrated pipeline is a literal-spec bridge. The frontend scanner (packages/frontend/src/\n" +
  "CompileStrategy.cj) recognizes literal `return <const>`, folds `let x=<lit>` into returns, and captures\n" +
  "println/print(\"literal\") calls. Those thread via FuncBody -> AST2CHIRFunctionSpec -> CHIR Function\n" +
  "(packages/chir) -> codegen (packages/codegen/src/EmitPrintIR.cj emits puts/fputs; literal returns lower\n" +
  "through CreateLiteralReturnBody). ALREADY VERIFIED & MUST NOT REGRESS: println/print of string literals,\n" +
  "return <int literal> exit code, `let x=<int>; return x` exit code.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" },
    commit: { type: "string" }, branch: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string" }, remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

phase('Expand')
const TASKS = [
  {
    key: 'int-arith-return',
    branch: 'opus2/int-arith-return',
    goal: "Make integer-arithmetic `return` expressions work by COMPILE-TIME folding in the frontend scanner.\n" +
      "Support `return <intexpr>` where intexpr is integer literals combined with + - * / % and parentheses,\n" +
      "and operands may be let-bound integer literals already tracked by the existing let-folding. Compute the\n" +
      "Int64 value at compile time and feed it as the literal return (reuse the literal-return path; do NOT\n" +
      "attempt real CHIR arithmetic). Keep it conservative: only integer literals / folded lets / the listed\n" +
      "operators; if anything else appears, fall back to current behavior. Verify: `return 2 + 3 * 4` exits 14;\n" +
      "`let a = 2\\n let b = 5\\n return a * b` exits 10; `return (7 - 1) / 2` exits 3. Do not regress existing.",
  },
  {
    key: 'println-int',
    branch: 'opus2/println-int',
    goal: "Support `println(<int>)` and `print(<int>)` where the arg is an integer literal or a let-bound integer\n" +
      "literal (reuse the let-int tracking). Print the decimal value (println adds newline). Thread integer\n" +
      "print entries alongside the existing string print entries (FuncBody -> AST2CHIRFunctionSpec -> CHIR\n" +
      "Function -> codegen). In codegen (packages/codegen/src/EmitPrintIR.cj) emit a real libc `printf` call\n" +
      "with a private format-string global (\"%ld\\n\" for println, \"%ld\" for print) and the i64 constant arg\n" +
      "(LLVMConstInt i64). Keep string println/print working unchanged and preserve source order across string\n" +
      "and int prints. Verify: `main(){ println(42)\\n let n=7\\n println(n) }` prints `42` then `7`;\n" +
      "`main(){ print(1); print(2); println(3) }` prints `123` then newline. Do not regress string prints.",
  },
  {
    key: 'deisolation-plan',
    branch: 'opus2/deisolation-plan',
    goal: "READ-ONLY analysis (only create/edit docs/DEISOLATION_PLAN.md; do NOT change any .cj). Produce a\n" +
      "concrete, file-level plan to escape the facade and lower a REAL function body end-to-end, using a\n" +
      "minimal target program `main(): Int64 { let a = 2; let b = 3; return a + b }` lowered WITHOUT compile-time\n" +
      "folding. Investigate and document: (1) packages/parse Parser.ParseTopLevel — does it parse real bodies,\n" +
      "and exactly how its AST node types (parse.File/FuncDecl/Block/Expr) differ from packages/ast's (list the\n" +
      "concrete incompatibilities); recommend unify-vs-adapter with rationale. (2) packages/chir AST2CHIR — is\n" +
      "there a real ast.FuncBody->CHIR path beyond the spec path, and what's missing to lower VarDecl + BinaryExpr\n" +
      "+ ReturnExpr. (3) packages/codegen — does it already lower CHIR arithmetic/local-var/return (cite the\n" +
      "exprs/files). Give an ordered, minimal step list (with files) for the first real-expression slice. Verify\n" +
      "by ensuring the doc exists and build is still green (you changed no code). Commit the doc on your branch.",
  },
]

const SETUP = (t) =>
  "Set up an isolated worktree and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/" + t.key + " 2>/dev/null; git branch -D " + t.branch + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/" + t.key + "\n" +
  "  git worktree add -b " + t.branch + " " + WTROOT + "/" + t.key + " main\n" +
  "  cd " + WTROOT + "/" + t.key + "\n" +
  "Do all edits/builds/runs there; commit on branch " + t.branch + ".\n"

const expanded = await parallel(TASKS.map(t => () =>
  agent(
    PREAMBLE + SETUP(t) + "TASK (" + t.key + "):\n" + t.goal + "\n\n" +
    "Build with cjpm build in your worktree until green; verify with real compiled+run programs (set runtime\n" +
    "env; binary <worktree>/" + CJC + "). Then git add -A && git commit on " + t.branch + ". Return schema, branch=" + t.branch + ".",
    { schema: SCHEMA, phase: 'Expand', label: 'expand:' + t.key, isolation: 'worktree' }
  ).then(r => r ? { ...r, key: t.key, branch: t.branch } : null)
))

const good = expanded.filter(Boolean).filter(r => r.built === true && r.committed === true)
log("Expand: " + good.length + "/" + TASKS.length + " built+committed: " + good.map(r => r.key).join(", "))

phase('Merge')
const mergeList = good.map(r => r.branch).join(" ")
const merge = await agent(
  PREAMBLE +
  "TASK: Merge the successful task branches into main, keep everything green, re-verify, refresh status.\n" +
  "Branches (merge in this order): " + (mergeList || "(none)") + "\n" +
  (mergeList === "" ? "No branches to merge; just re-verify and refresh status.\n" :
    "For each: `cd " + REPO + " && git merge --no-edit <branch>`. Resolve conflicts carefully (int-arith-return\n" +
    "and println-int both touch the frontend scanner + print/return threading — keep BOTH features). After all\n" +
    "merges, `cjpm build` and FIX any break.\n") +
  "Re-verify ALL of these with real runs (set runtime env; binary " + CJC + "), every line must hold:\n" +
  "  main(){ println(\"hello selfhost\") }            -> prints hello selfhost\n" +
  "  main(){ print(\"a\"); print(\"b\"); println(\"c\") } -> abc + newline\n" +
  "  main(): Int64 { return 7 }                       -> exit 7\n" +
  "  main(): Int64 { let x = 42\\n return x }           -> exit 42\n" +
  "  main(): Int64 { return 2 + 3 * 4 }               -> exit 14   (if int-arith merged)\n" +
  "  main(){ println(42)\\n let n=7\\n println(n) }      -> prints 42 then 7   (if println-int merged)\n" +
  "Then refresh docs/STATUS.md with a 'Verified integrated capabilities' section listing exactly what compiles\n" +
  "and runs today, and keep the de-isolation roadmap pointer. Clean up worktrees (git worktree remove --force\n" +
  WTROOT + "/<key> for each + prune + rm -rf " + WTROOT + "). Commit. Return schema (verified=all checks pass).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  expanded: expanded.filter(Boolean).map(r => ({ key: r.key, built: r.built, verified: r.verified, commit: r.commit })),
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
