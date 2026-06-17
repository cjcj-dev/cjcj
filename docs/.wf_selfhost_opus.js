export const meta = {
  name: 'selfhost-opus-advance',
  description: 'Advance the self-host Cangjie compiler with concurrent Opus subagents: verify the println slice, then fan out independent capability expansions in isolated worktrees, build-gated, then merge and re-verify',
  phases: [
    { title: 'Verify-slice' },
    { title: 'Expand' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const WTROOT = "/root/cj_build/.cjsh_opus"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer working on a self-hosting Cangjie compiler.\n" +
  "Repo: " + REPO + " (a git repo; branch main). Toolchain: cjc/cjpm 1.1 at /root/.cjv/bin.\n" +
  "Build with `cjpm build` from the repo root. Build the runnable compiler binary is " + CJC + ".\n" +
  "To RUN the self-host cjc you MUST set the runtime env first:\n  " + RUNENV + "\n" +
  "C++ reference (READ-ONLY, never modify): /root/cj_build/cangjie_compiler.\n" +
  "Commit messages: NO AI attribution, no Co-Authored-By trailer. Match existing style.\n" +
  "You DO write code yourself (Codex is unavailable). Keep `cjpm build` green. Verify every claim with real commands.\n"

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    built: { type: "boolean", description: "cjpm build succeeded" },
    verified: { type: "boolean", description: "the capability check passed (real run)" },
    committed: { type: "boolean" },
    commit: { type: "string", description: "short hash of the new commit, or empty" },
    branch: { type: "string", description: "branch the work was committed on" },
    summary: { type: "string" },
    evidence: { type: "string", description: "the exact command output proving verified/built" },
    remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

// ---- Phase 1: build + fix + verify the println WIP slice, on main ----
phase('Verify-slice')
const slice = await agent(
  PREAMBLE +
  "TASK: The previous commit (HEAD `12e2466`, message starts 'wip: thread println') threads a\n" +
  "println(\"literal\") vertical slice through frontend -> CHIR -> codegen. It is UNVERIFIED.\n" +
  "Files involved: packages/frontend/src/FrontendModel.cj, packages/frontend/src/CompileStrategy.cj,\n" +
  "packages/frontend/src/CodeGenBridge.cj, packages/chir/src/AST2CHIR.cj, packages/chir/src/TranslateFuncDecl.cj,\n" +
  "packages/chir/src/Value.cj, packages/codegen/src/EmitPrintIR.cj, packages/codegen/src/EmitFunctionIR.cj.\n" +
  "1) Run `cd " + REPO + " && cjpm build`. If it fails, FIX the compile errors (FFI signature mismatches,\n" +
  "   visibility, types) until it builds clean. Do not weaken/remove the print feature.\n" +
  "2) Verify a real hello-world prints: write /tmp/hello_v.cj with `main() { println(\"hello selfhost\") }`,\n" +
  "   then (" + RUNENV + ") and run `" + CJC + " /tmp/hello_v.cj -o /tmp/hello_v && /tmp/hello_v`.\n" +
  "   It MUST print exactly `hello selfhost`. Also verify multiple println lines print in order, and that\n" +
  "   existing literal-return programs still work (`main(): Int64 { return 7 }` exits 7; `return -5` exits 251/251... it is 256-5=251? compute: 256-5=251) — actually just confirm `return 7` exits 7.\n" +
  "3) When green AND printing works, `git add -A && git commit` on main. If build cannot be made to work,\n" +
  "   revert ONLY to keep main green and report built=false.\n" +
  "Return the schema. evidence MUST contain the literal program output you observed.",
  { schema: SCHEMA, phase: 'Verify-slice', label: 'verify-println' }
)

log("Verify-slice: built=" + (slice && slice.built) + " verified=" + (slice && slice.verified) + " commit=" + (slice && slice.commit))

// Only fan out if main is green after phase 1.
if (!slice || slice.built !== true) {
  return { stopped: "println slice did not build; main left green by phase-1 agent", slice }
}

// ---- Phase 2: independent capability expansions, each in its own worktree+branch ----
phase('Expand')
const TASKS = [
  {
    key: 'print-nonewline',
    branch: 'opus/print-nonewline',
    goal: "Add support for top-level `print(\"literal\")` (NO trailing newline) alongside the existing\n" +
      "println. Mirror the println path: capture `print(string-literal)` in the frontend body scanner\n" +
      "(packages/frontend/src/CompileStrategy.cj captureFunctionBodyPrints), thread a parallel list (e.g.\n" +
      "with a per-entry newline flag, or a separate list) through FuncBody -> AST2CHIRFunctionSpec ->\n" +
      "CHIR Function -> codegen. In codegen EmitPrintIR.cj, emit libc `fputs(str, stdout)` (no newline) for\n" +
      "print, keep `puts` (newline) for println. Preserve source order between print and println. Verify\n" +
      "`main() { print(\"a\"); print(\"b\"); println(\"c\") }` outputs `abc` then newline.",
  },
  {
    key: 'const-let-return',
    branch: 'opus/const-let-return',
    goal: "Extend the literal-return recognizer so `main(): Int64 { let x = 7; return x }` exits 7. In\n" +
      "packages/frontend/src/CompileStrategy.cj, when the returned token is an IDENTIFIER, look back for a\n" +
      "top-level `let <id> = <integer-literal>` (or bool/float) earlier in the same body and fold it into the\n" +
      "literal return value. Keep it conservative: only single-assignment literal-initialized immutable lets,\n" +
      "no expressions. Verify `let x = 7; return x` exits 7 and `let x = 3\\n let y = 4\\n return y` exits 4.",
  },
  {
    key: 'warnings',
    branch: 'opus/warnings',
    goal: "Reduce `cjpm build` warnings WITHOUT changing behavior. Current build prints ~13-25 'unused\n" +
      "variable' warnings (e.g. packages/parse/src/ParseDecl.cj ParsePropDecl scopeKind, packages/sema/src/\n" +
      "CheckFunctionLinkage.cj byTy, packages/codegen/src/CGType.cj context). Prefix genuinely-unused params\n" +
      "with `_` or remove dead locals. Do NOT touch print/return-literal logic or any file another task owns\n" +
      "(avoid CompileStrategy.cj, EmitPrintIR.cj, AST2CHIR.cj, TranslateFuncDecl.cj, Value.cj). Verify build\n" +
      "is green with fewer warnings.",
  },
]

const SETUP = (t) =>
  "Set up an isolated worktree for your task and work ONLY inside it:\n" +
  "  cd " + REPO + "\n" +
  "  git worktree remove --force " + WTROOT + "/" + t.key + " 2>/dev/null; git branch -D " + t.branch + " 2>/dev/null\n" +
  "  mkdir -p " + WTROOT + "; rm -rf " + WTROOT + "/" + t.key + "\n" +
  "  git worktree add -b " + t.branch + " " + WTROOT + "/" + t.key + " main\n" +
  "  cd " + WTROOT + "/" + t.key + "\n" +
  "Do all edits, builds, and runs in " + WTROOT + "/" + t.key + ". Commit on branch " + t.branch + ".\n"

const expanded = await parallel(TASKS.map(t => () =>
  agent(
    PREAMBLE + SETUP(t) +
    "TASK (" + t.key + "):\n" + t.goal + "\n\n" +
    "Build with cjpm build IN YOUR WORKTREE until green. Verify the behavior with a real compiled+run\n" +
    "program (set the runtime env shown above; the binary is <worktree>/" + CJC + ").\n" +
    "Then `git add -A && git commit` on " + t.branch + ". Return the schema with branch=" + t.branch + ".",
    { schema: SCHEMA, phase: 'Expand', label: 'expand:' + t.key, isolation: 'worktree' }
  ).then(r => r ? { ...r, key: t.key, branch: t.branch } : null)
))

const good = expanded.filter(Boolean).filter(r => r.built === true && r.committed === true)
log("Expand: " + good.length + "/" + TASKS.length + " tasks built+committed: " + good.map(r => r.key).join(", "))

// ---- Phase 3: merge successful branches to main, rebuild, fix, re-verify ----
phase('Merge')
const mergeList = good.map(r => r.branch).join(" ")
const merge = await agent(
  PREAMBLE +
  "TASK: Merge the successful task branches into main and keep everything green.\n" +
  "Branches to merge (in this order): " + (mergeList || "(none)") + "\n" +
  (mergeList === "" ?
    "There are no branches to merge. Just confirm main builds green and hello-world still prints, then report.\n" :
    "For each branch: `cd " + REPO + " && git merge --no-edit <branch>`. Resolve any conflicts sensibly\n" +
    "(these tasks were designed to touch mostly different files). After all merges, run `cjpm build` and FIX\n" +
    "any integration break. ") +
  "Then verify end-to-end with real runs (set runtime env; binary " + CJC + "):\n" +
  "  - main() { println(\"hello selfhost\") }  -> prints `hello selfhost`\n" +
  "  - main(): Int64 { return 7 }  -> exits 7\n" +
  "Clean up worktrees: `git worktree remove --force " + WTROOT + "/<key>` for each, and prune.\n" +
  "Commit the merge state if not already committed. Return the schema (verified=overall end-to-end check).",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  sliceBuilt: slice.built, sliceVerified: slice.verified,
  expanded: expanded.filter(Boolean).map(r => ({ key: r.key, built: r.built, verified: r.verified, commit: r.commit })),
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
