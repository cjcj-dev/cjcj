export const meta = {
  name: 'selfhost-opus-deiso-isbroken',
  description: 'De-isolation CUT 2: replace parse.Node\'s plain isBroken/hasBroken Bool fields with the REAL ast AttributePack (Attribute.IS_BROKEN/HAS_BROKEN) machinery, backed via a mut prop so the ~94 call sites stay unchanged; whole-workspace build green; branch-in-main-repo; then merge + re-verify facade regressions',
  phases: [ { title: 'Implement' }, { title: 'Merge' } ],
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
  "C++ REFERENCE (READ-ONLY, never modify): " + REF + " (src/Parse, src/AST, include/cangjie/AST).\n" +
  "Commits: NO AI attribution. You write the code yourself. Keep `cjpm build` GREEN for the WHOLE workspace at every commit.\n" +
  "Use MCP tool cangjie_search_docs (cj-mcp) when unsure of syntax. Pkg qualified name `organization::package` uses `::`; members\n" +
  "use `.`; alias import `import a::b.Member as Alias`. Cangjie supports `mut prop` with custom get/set.\n"

const CONTEXT =
  "BIG PICTURE: packages/parse re-declares its OWN duplicate AST node classes instead of using packages/ast (the #1 island). The\n" +
  "agreed de-isolation order: (a) unify SrcIdentifier [DONE — parse now public-imports cangjie_compiler::ast.{Identifier,\n" +
  "SrcIdentifier}], (b) isBroken/hasBroken -> ast AttributePack [THIS RUN], (c) Type, (d) Pattern, (e) Expr, (f) Decl/Import/File.\n" +
  "You are doing ONLY step (b). BOUNDED — complete it, build green, commit; do NOT decline as 'too risky'.\n\n" +
  "VERIFIED FACTS (re-confirm by reading, then act):\n" +
  "  - parse.Node (packages/parse/src/ASTCore.cj) has a plain `public var isBroken: Bool = false` field (and parse uses a\n" +
  "    `hasBroken` notion too, e.g. ParseImports.cj). There are ~94 references to isBroken across packages/parse/src (almost all\n" +
  "    are `node.isBroken = true` writes or boolean reads).\n" +
  "  - the REAL ast attribute machinery: packages/ast/src/AttributePack.cj defines `enum Attribute { ... | IS_BROKEN | HAS_BROKEN\n" +
  "    ... }` and `class AttributePack` with TestAttr; packages/ast/src/Node.cj has `func EnableAttr(attr: Attribute)` and\n" +
  "    `func TestAttr(attr: Attribute): Bool`; ast nodes mark brokenness via EnableAttr(Attribute.IS_BROKEN)/TestAttr (see\n" +
  "    ast/src/NodeX.cj IsBroken/SetBroken helpers). This is how the C++ AST does it (Attribute bitset), so it is the faithful target.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    strategy: { type: "string" }, parseUsesAstAttr: { type: "boolean" }, plainBoolGone: { type: "boolean" }, sitesTouched: { type: "string" },
    summary: { type: "string" }, evidence: { type: "string" }, remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "deisolate/isbroken"

phase('Implement')
const impl = await agent(
  PREAMBLE + "\n" + CONTEXT + "\n" +
  "Work on a BRANCH IN THE MAIN REPO (NO worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n\n" +
  "CUT 2 — adopt ast's AttributePack for brokenness (this run's ONLY scope):\n" +
  "  RECOMMENDED LOW-CHURN STRATEGY (use unless you find something cleaner that keeps build green):\n" +
  "   1. In parse.Node (ASTCore.cj): import ast's attribute types (`import cangjie_compiler::ast.{Attribute, AttributePack}` —\n" +
  "      or whatever names ast exports) and give parse.Node a real `AttributePack` instance + `EnableAttr`/`TestAttr` methods\n" +
  "      that DELEGATE to ast's AttributePack (mirror ast/src/Node.cj). This makes parse.Node use ast's attribute machinery.\n" +
  "   2. REPLACE the plain `public var isBroken: Bool` with a `mut prop isBroken: Bool` backed by the AttributePack:\n" +
  "      get() = TestAttr(Attribute.IS_BROKEN); set(v) = if v EnableAttr(Attribute.IS_BROKEN) else DisableAttr/clear (all current\n" +
  "      writes are `= true`, so a set that enables on true is sufficient; mirror ast semantics). Do the SAME for `hasBroken`\n" +
  "      (Attribute.HAS_BROKEN) if parse has such a field. This keeps the ~94 `.isBroken`/`.hasBroken` call sites UNCHANGED.\n" +
  "   3. Do NOT migrate any node CLASS this run — only the broken-flag mechanism on the base Node. The 5 parse *Nodes.cj stay.\n" +
  "   4. `cjpm build` (whole workspace) until GREEN; FIX errors. Commit: git add -A && git commit -m\n" +
  "      \"deisolate(parse): back isBroken/hasBroken with ast AttributePack\" (NO AI attribution). Sub-step commits OK.\n\n" +
  "MUST NOT REGRESS the facade end-to-end subset (frontend uses parse). After your change rebuild the self-host cjc and confirm\n" +
  "via real compile+run: `main(){return 42}`->exit 42; `main(){println(\"hi\")}`->hi; `main(){println(6*7)}`->42;\n" +
  "FizzBuzz 1..15 correct; fact(5)->120. Also confirm broken-input still diagnoses (a syntactically broken program still errors,\n" +
  "not silently 'ok'). If anything breaks, FIX it before finishing.\n" +
  "BOUNDED — DO complete and commit. Report schema honestly (independent verifier re-checks). evidence MUST show final `cjpm\n" +
  "build` result, that parse.Node no longer has a plain `var isBroken: Bool` (now prop-backed by ast AttributePack), and the\n" +
  "facade probe outputs.",
  { schema: SCHEMA, phase: 'Implement', label: 'isbroken' }
)

log("Implement: built=" + (impl && impl.built) + " committed=" + (impl && impl.committed) +
  " parseUsesAstAttr=" + (impl && impl.parseUsesAstAttr) + " plainBoolGone=" + (impl && impl.plainBoolGone) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "isBroken cut not landed green; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE + "\n" +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep whole workspace green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any cross-module break;\n" +
  "  converge on ast's AttributePack; do NOT re-stub or re-add a plain Bool field).\n" +
  "Implementer reports: strategy=[" + (impl.strategy || "?") + "] parseUsesAstAttr=" + (impl.parseUsesAstAttr) + " plainBoolGone=" + (impl.plainBoolGone) + ".\n" +
  "RE-VERIFY (if any fails: `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  (a) `cjpm build` GREEN for the whole workspace.\n" +
  "  (b) parse.Node no longer declares a plain `var isBroken: Bool` storage field — brokenness now goes through ast's\n" +
  "      AttributePack (grep parse/src for the prop + `Attribute.IS_BROKEN`/AttributePack usage).\n" +
  "  (c) NO facade regression — real compile+run: `main(){return 42}`->42, `main(){println(\"hi\")}`->hi, `main(){println(6*7)}`->42,\n" +
  "      FizzBuzz 1..15 correct, fact(5)->120; a deliberately broken program still errors (not silently ok).\n" +
  "Refresh docs/STATUS.md: parse->ast de-isolation CUT 2 (broken-flags on ast AttributePack) done; next = migrate Type nodes, then\n" +
  "Pattern/Expr/Decl, then delete the 5 parse *Nodes.cj. Commit. Else reset and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, committed: impl.committed, parseUsesAstAttr: impl.parseUsesAstAttr, plainBoolGone: impl.plainBoolGone, strategy: impl.strategy, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
