export const meta = {
  name: 'selfhost-opus-deiso-srcid',
  description: 'De-isolation CUT 1 (bounded, proven-doable): unify SrcIdentifier — delete parse-local SrcIdentifier, make parse + macro use the real cangjie_compiler::ast SrcIdentifier, reconcile the 5-arg vs 4-arg ctor; whole-workspace build green; branch-in-main-repo; then merge + re-verify facade regressions',
  phases: [
    { title: 'Implement' },
    { title: 'Merge' },
  ],
}

const REPO = "/root/cj_build/cangjie_compiler_selfhost"
const CJC = "./target/release/bin/cangjie_compiler::cjc"
const REF = "/root/cj_build/cangjie_compiler"
const RUNENV = "export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029; " +
  "export LD_LIBRARY_PATH=\"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH\""

const PREAMBLE =
  "You are an expert Cangjie/LLVM compiler engineer on a self-hosting Cangjie compiler (faithful rewrite of the C++ cangjie_compiler).\n" +
  "Repo: " + REPO + " (git, branch main). Build whole workspace: `cjpm build` from repo root. Compiler binary: " + CJC + ".\n" +
  "RUN the self-host cjc with this env first:\n  " + RUNENV + "\n" +
  "C++ REFERENCE (READ-ONLY, never modify): " + REF + " (src/Parse, src/AST, include/cangjie/AST, src/Macro).\n" +
  "Commits: NO AI attribution. You write the code yourself. Keep `cjpm build` GREEN for the WHOLE workspace at every commit.\n" +
  "Use MCP tool cangjie_search_docs (cj-mcp) when unsure of syntax. Pkg qualified name `organization::package` uses `::`\n" +
  "(e.g. cangjie_compiler::ast); members/sub-packages use `.`; alias import `import a::b.Member as Alias`.\n"

const CONTEXT =
  "BIG PICTURE: packages/parse re-declares its OWN duplicate AST node classes instead of using packages/ast — the #1 island\n" +
  "blocking a real end-to-end pipeline. A prior investigation established the node sets are STRUCTURALLY divergent and the\n" +
  "correct de-isolation order is: (a) unify SrcIdentifier FIRST, (b) isBroken->ast AttributePack IS_BROKEN, (c) Type, (d) Pattern,\n" +
  "(e) Expr, (f) Decl/Import/File. You are doing ONLY step (a) this run. It is BOUNDED and PROVEN DOABLE — complete it; do NOT\n" +
  "decline as 'too risky'. Land it fully, build green, commit.\n\n" +
  "VERIFIED FACTS about SrcIdentifier (re-confirm by reading the files, then act):\n" +
  "  - parse defines its OWN SrcIdentifier in packages/parse/src/ASTCore.cj with public fields .value/.rawValue/.isRaw and a\n" +
  "    5-arg ctor SrcIdentifier(value, rawValue, begin, end, isRaw).\n" +
  "  - the REAL ast.SrcIdentifier is in packages/ast/src/Identifier.cj: 4-arg ctor SrcIdentifier(value, begin, end, isRaw), no\n" +
  "    separate rawValue (GetRawText derives backticks from the raw flag). Method surface (Val/Empty/Begin/End/GetRawText) matches.\n" +
  "  - the 5-arg ctor is called at ~10 sites in parse (ParseImports.cj, ParseQuote.cj, ParserUtils.cj, ParseDecl.cj,\n" +
  "    ParseAnnotations.cj, ...) and once in macro (packages/macro/src/MacroEvaluation.cj ~line 202, EvalParsedSrcIdentifier).\n" +
  "  - packages/frontend's FrontendModel.cj defines a SEPARATE frontend-model SrcIdentifier — that is a DIFFERENT type; do NOT\n" +
  "    touch it unless the build forces it. Only RealParseBridge.cj reads parse nodes' identifier via Val/Begin/End (method surface).\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    parseLocalSrcIdGone: { type: "boolean" }, ctorStrategy: { type: "string" }, sitesFixed: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string", description: "build result + grep proving parse-local SrcIdentifier is gone + facade probes" }, remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "deisolate/srcid"

phase('Implement')
const impl = await agent(
  PREAMBLE + "\n" + CONTEXT + "\n" +
  "Work on a BRANCH IN THE MAIN REPO (NO worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n\n" +
  "CUT 1 — UNIFY SrcIdentifier (this run's ONLY scope):\n" +
  "  1. DELETE the parse-local SrcIdentifier definition in packages/parse/src/ASTCore.cj (keep anything else in that file).\n" +
  "  2. Make parse use the REAL ast.SrcIdentifier: add `import cangjie_compiler::ast.SrcIdentifier` (and ast.Identifier if used)\n" +
  "     to the parse files that need it (or a public re-export if ASTCore.cj re-exports types for the package).\n" +
  "  3. Reconcile the ctor arity. Prefer the LEAST-INVASIVE faithful option: ADD a 5-arg convenience ctor/overload to\n" +
  "     ast.SrcIdentifier `init(value: String, rawValue: String, begin, end, isRaw: Bool)` that preserves existing semantics\n" +
  "     (store/derive rawValue consistently with GetRawText). If adding the overload is clean, the ~10 parse sites + macro's\n" +
  "     EvalParsedSrcIdentifier need NO change. Otherwise change those ~11 call sites to the 4-arg form. Pick whichever keeps\n" +
  "     `GetRawText`/backtick semantics correct and the build green; report which in ctorStrategy.\n" +
  "  4. Ensure every consumer still compiles: parse nodes that embed SrcIdentifier, packages/macro (EvalParsedSrcIdentifier +\n" +
  "     any .rawValue/.value/.isRaw field access — switch to the ast method surface Val()/GetRawText() etc.), and\n" +
  "     packages/frontend RealParseBridge.cj (reads identifier via methods). Do NOT migrate any *node* class this run — only\n" +
  "     SrcIdentifier. The 5 parse *Nodes.cj stay; they just now hold ast.SrcIdentifier fields.\n" +
  "  5. `cjpm build` (whole workspace) until GREEN; read errors and FIX. Commit: git add -A && git commit -m\n" +
  "     \"deisolate(parse): unify SrcIdentifier onto cangjie_compiler::ast\" (NO AI attribution). You may commit in sub-steps.\n\n" +
  "MUST NOT REGRESS the facade end-to-end subset (frontend uses parse) — after your change rebuild the self-host cjc and confirm\n" +
  "via real compile+run: `main(){return 42}`->exit 42; `main(){println(\"hi\")}` prints hi; `main(){println(6*7)}`->42;\n" +
  "FizzBuzz 1..15 correct; fact(5)->120. If any breaks, FIX it before finishing.\n" +
  "This cut is bounded — DO complete and commit it. Report schema honestly (independent verifier re-checks). evidence MUST show\n" +
  "final `cjpm build` result, `grep -rn 'class SrcIdentifier' packages/parse/src` (should be empty = parse-local gone), and the\n" +
  "facade probe outputs.",
  { schema: SCHEMA, phase: 'Implement', label: 'unify-srcid' }
)

log("Implement: built=" + (impl && impl.built) + " committed=" + (impl && impl.committed) +
  " parseLocalGone=" + (impl && impl.parseLocalSrcIdGone) + " ctor=" + (impl && impl.ctorStrategy) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "SrcIdentifier unify not landed green; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE + "\n" +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep whole workspace green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any cross-module break; converge\n" +
  "  on the real ast.SrcIdentifier; do NOT re-stub or re-add a parse-local copy).\n" +
  "Implementer reports: parseLocalSrcIdGone=" + (impl.parseLocalSrcIdGone) + " ctorStrategy=[" + (impl.ctorStrategy || "?") + "].\n" +
  "RE-VERIFY (if any fails: `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  (a) `cjpm build` GREEN for the whole workspace.\n" +
  "  (b) parse-local SrcIdentifier is GONE: `grep -rn 'class SrcIdentifier' packages/parse/src` is empty; parse references\n" +
  "      ast.SrcIdentifier instead.\n" +
  "  (c) NO facade regression — real compile+run: `main(){return 42}`->42, `main(){println(\"hi\")}`->hi, `main(){println(6*7)}`->42,\n" +
  "      FizzBuzz 1..15 correct, fact(5)->120.\n" +
  "Refresh docs/STATUS.md: parse->ast de-isolation CUT 1 (SrcIdentifier unified) done; next cuts = isBroken->IS_BROKEN, then Type/\n" +
  "Pattern/Expr/Decl node migration, then delete the 5 parse *Nodes.cj. Commit. Else reset and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, committed: impl.committed, parseLocalSrcIdGone: impl.parseLocalSrcIdGone, ctorStrategy: impl.ctorStrategy, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
