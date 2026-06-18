export const meta = {
  name: 'selfhost-opus-deiso-type',
  description: 'De-isolation CUT 3: migrate parse Type nodes (TypeNodes.cj: PrimitiveType/RefType/QualifiedType/OptionType/ConstantType/VArrayType/ParenType/TupleType/FuncType/ThisType/InvalidType + Generic/GenericConstraint) onto the real cangjie_compiler::ast Type nodes; extend ast where a field/ctor is missing; update consumers (frontend RealParseBridge/CompileStrategy + macro); delete parse/src/TypeNodes.cj; whole-workspace build green; branch-in-main-repo; then merge + re-verify facade regressions',
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
  "C++ REFERENCE (READ-ONLY, never modify): " + REF + " (src/Parse/ParseType*, src/AST, include/cangjie/AST/Types*).\n" +
  "Commits: NO AI attribution. You write the code yourself. Keep `cjpm build` GREEN for the WHOLE workspace at every commit.\n" +
  "Use MCP tool cangjie_search_docs (cj-mcp) when unsure of syntax. Pkg qualified name `organization::package` uses `::`; members\n" +
  "use `.`; alias import `import a::b.Member as Alias`.\n"

const CONTEXT =
  "BIG PICTURE: packages/parse re-declares its OWN duplicate AST node classes instead of using packages/ast (the #1 island).\n" +
  "De-isolation order: (a) SrcIdentifier [DONE], (b) isBroken/hasBroken->AttributePack [DONE], (c) Type [THIS RUN], (d) Pattern,\n" +
  "(e) Expr, (f) Decl/Import/File; then delete the 5 parse *Nodes.cj. You are doing ONLY (c). It is the first cut that DELETES a\n" +
  "dup file (packages/parse/src/TypeNodes.cj). Bounded to Type — complete it, build green, commit. Do NOT migrate Expr/Decl/Pattern\n" +
  "node classes this run.\n\n" +
  "VERIFIED FACTS (re-confirm by reading, then act):\n" +
  "  - parse TypeNodes.cj (205 lines) defines: Type(base), InvalidType, PrimitiveType, RefType, QualifiedType, OptionType,\n" +
  "    ConstantType, VArrayType, ParenType, TupleType, FuncType, ThisType, Generic, GenericConstraint.\n" +
  "  - ast TypeNodes.cj already defines: Type, InvalidType, RefType, ThisType, PrimitiveType, ParenType, QualifiedType,\n" +
  "    OptionType, ConstantType, VArrayType, FuncType, TupleType. (Generic / GenericConstraint may live in a DIFFERENT ast file\n" +
  "    or be MISSING — check packages/ast/src; if missing, ADD them to ast faithfully per the C++ reference.)\n" +
  "  - KNOWN field-shape divergences to reconcile (verify, then handle):\n" +
  "      * parse.PrimitiveType{name:String, tokenKind:TokenKind} + 4-arg ctor  VS  ast.PrimitiveType{str:String, kind:TypeKind}.\n" +
  "      * parse.RefType{identifier:SrcIdentifier}  VS  ast.RefType{ref:Reference} (the identifier lives at ref.identifier).\n" +
  "    Map each parse field to the ast field; where ast genuinely lacks something parse needs, ADD it to ast (do NOT keep a\n" +
  "    forked parse-local copy).\n" +
  "  - ~40 Type construction sites are in packages/parse/src/ParseType.cj. Consumers that READ parse Type nodes: frontend\n" +
  "    (RealParseBridge.cj — 3575 lines, reads Type fields; CompileStrategy.cj; FrontendModel.cj) and macro (MacroExpansion.cj,\n" +
  "    NodeSerialization.cj, MacroCompatibility.cj, ExprSerialization.cj, TestEntryConstructor.cj). Update them to the ast field shape.\n"

const SCHEMA = {
  type: "object", additionalProperties: false,
  properties: {
    built: { type: "boolean" }, verified: { type: "boolean" }, committed: { type: "boolean" }, commit: { type: "string" }, branch: { type: "string" },
    typeNodesDeleted: { type: "boolean" }, astExtended: { type: "string" }, consumersUpdated: { type: "string" }, completeness: { type: "integer", minimum: 0, maximum: 100 },
    summary: { type: "string" }, evidence: { type: "string" }, remaining: { type: "string" },
  },
  required: ["built", "verified", "committed", "summary"],
}

const BRANCH = "deisolate/type"

phase('Implement')
const impl = await agent(
  PREAMBLE + "\n" + CONTEXT + "\n" +
  "Work on a BRANCH IN THE MAIN REPO (NO worktree):\n" +
  "  cd " + REPO + "\n" +
  "  git checkout main && git branch -D " + BRANCH + " 2>/dev/null; git checkout -b " + BRANCH + "\n\n" +
  "CUT 3 — migrate parse Type nodes onto ast Type nodes (this run's ONLY scope):\n" +
  "  1. Read parse/src/TypeNodes.cj + ParseType.cj AND ast's Type node defs AND the C++ reference Type AST. Build a field-by-field\n" +
  "     map parse Type node -> ast Type node.\n" +
  "  2. Repoint the ~40 Type construction sites in parse (mainly ParseType.cj, also anywhere else that builds Type nodes) to build\n" +
  "     ast.* Type nodes. Add the needed `import cangjie_compiler::ast.*`/aliases in parse.\n" +
  "  3. Where ast lacks a field/ctor/node parse needs (e.g. a convenience ctor for PrimitiveType taking name+tokenKind, or the\n" +
  "     Generic/GenericConstraint classes), ADD it to packages/ast faithfully per the C++ AST. Do NOT fork a parse-local copy.\n" +
  "  4. Update consumers to the ast field shape: frontend RealParseBridge.cj / CompileStrategy.cj / FrontendModel.cj, and macro\n" +
  "     (MacroExpansion / NodeSerialization / MacroCompatibility / ExprSerialization / TestEntryConstructor). Use ast accessors\n" +
  "     (e.g. RefType identifier via ref.identifier; PrimitiveType via str/kind).\n" +
  "  5. DELETE packages/parse/src/TypeNodes.cj once every Type class is migrated + unused. (If Generic/GenericConstraint are NOT\n" +
  "     Type nodes and belong to a later cut, you MAY keep ONLY those two in a small file and delete the rest — but delete all the\n" +
  "     Type-proper classes; report exactly what remains and why.)\n" +
  "  6. `cjpm build` (whole workspace) until GREEN; FIX errors. Commit incrementally: git add -A && git commit -m\n" +
  "     \"deisolate(parse): migrate Type nodes onto cangjie_compiler::ast\" (NO AI attribution).\n\n" +
  "MUST NOT REGRESS the facade end-to-end subset (frontend uses parse Type nodes for signatures). After your change rebuild the\n" +
  "self-host cjc and confirm via real compile+run: `main(){return 42}`->exit 42; `main(){println(\"hi\")}`->hi;\n" +
  "`main(){println(6*7)}`->42; FizzBuzz 1..15 correct; fact(5)->120; AND a typed program exercising Type nodes:\n" +
  "  `func add(a: Int64, b: Int64): Int64 { return a + b }\\n main(){ println(add(20, 22)) }` -> prints 42.\n" +
  "If anything breaks, FIX it before finishing. Report schema honestly (independent verifier re-checks). evidence MUST show final\n" +
  "`cjpm build` result, `ls packages/parse/src/TypeNodes.cj` (gone or what remains), and the facade probe outputs.",
  { schema: SCHEMA, phase: 'Implement', label: 'type-nodes' }
)

log("Implement: built=" + (impl && impl.built) + " committed=" + (impl && impl.committed) +
  " typeNodesDeleted=" + (impl && impl.typeNodesDeleted) + " completeness=" + (impl && impl.completeness) + " commit=" + (impl && impl.commit))
if (!impl || impl.built !== true || impl.committed !== true) {
  return { stopped: "Type-node migration not landed green; main untouched", impl }
}

phase('Merge')
const merge = await agent(
  PREAMBLE + "\n" +
  "TASK: Merge branch " + BRANCH + " into main ONLY IF it passes; keep whole workspace green; refresh status.\n" +
  "  cd " + REPO + " && git checkout main && git merge --no-edit " + BRANCH + " ; cjpm build  (FIX any cross-module break;\n" +
  "  converge on the real ast Type nodes; do NOT re-stub or re-add parse-local Type copies).\n" +
  "Implementer reports: typeNodesDeleted=" + (impl.typeNodesDeleted) + " astExtended=[" + (impl.astExtended || "?") + "] completeness=" + (impl.completeness || 0) + "%.\n" +
  "RE-VERIFY (if any fails: `git reset --hard <pre-merge HEAD>` and report verified=false):\n" +
  "  (a) `cjpm build` GREEN for the whole workspace.\n" +
  "  (b) parse Type nodes are gone/migrated: `ls packages/parse/src/TypeNodes.cj` (should be absent, or contain ONLY\n" +
  "      Generic/GenericConstraint if deferred — verify the Type-proper classes are gone and parse builds ast.* Type nodes).\n" +
  "  (c) NO facade regression — real compile+run: `main(){return 42}`->42, `main(){println(\"hi\")}`->hi, `main(){println(6*7)}`->42,\n" +
  "      FizzBuzz 1..15 correct, fact(5)->120, and `func add(a:Int64,b:Int64):Int64{return a+b}\\n main(){println(add(20,22))}`->42.\n" +
  "Refresh docs/STATUS.md: parse->ast de-isolation CUT 3 (Type nodes on ast; TypeNodes.cj deleted) done; next = Pattern, then Expr,\n" +
  "then Decl/Import/File, then the last dup files gone. Commit. Else reset and report verified=false. Return schema.",
  { schema: SCHEMA, phase: 'Merge', label: 'merge' }
)

return {
  implemented: { built: impl.built, committed: impl.committed, typeNodesDeleted: impl.typeNodesDeleted, astExtended: impl.astExtended, completeness: impl.completeness, commit: impl.commit },
  merged: { built: merge && merge.built, verified: merge && merge.verified, commit: merge && merge.commit },
}
