package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::frontend.*

// Use a fresh, untyped reference at a real source position. Reusing a typed
// expression would take SynReferenceSeparately's type-only shortcut and would
// not exercise the public context -> lexical lookup connection.
private func LookupAt(instance: CompilerInstance, pkg: Package, site: Expr, name: String): Candidate {
    let ref = RefExpr(SrcIdentifier(name))
    ref.begin = site.begin
    ref.end = site.end
    ref.curFile = site.curFile
    ref.scopeName = site.scopeName
    ref.scopeLevel = site.scopeLevel
    return instance.GetGivenReferenceTarget(instance.GetASTContextByPackage(pkg).getOrThrow(),
        site.scopeName, ref, true)
}

private func CheckPublicContextLookup(incomplete: Bool): Unit {
    let expression = if (incomplete) { "__completionHole" } else { "parameter" }
    let result = CompileSource(
        "package context_lookup\n" +
        "func use(parameter: Int64): Unit {\n" +
        "    let shadow: Int64 = 1\n" +
        "    if (true) {\n" +
        "        let shadow: Bool = true\n" +
        "        let result = " + expression + "\n" +
        "        let later: Int64 = 2\n" +
        "    }\n}\n", stage: CompileStage.SEMA)
    let instance = result.instance
    try {
        @Assert(result.ok, !incomplete)
        @Assert(result.diag.GetErrorCount(), if (incomplete) { 1u64 } else { 0u64 })
        let pkg = RequireFirstPackage(result)
        let sites = ArrayList<Expr>()
        let innerShadows = ArrayList<Decl>()
        let parameters = ArrayList<Decl>()
        Walker(pkg, visitPre: { node: Node =>
            if (let Some(param) <- (node as FuncParam)) {
                if (param.identifier.Val() == "parameter") { parameters.add(param) }
            }
            if (let Some(decl) <- (node as VarDecl)) {
                if (decl.identifier.Val() == "result") { sites.add(decl.initializer.getOrThrow()) }
                if (decl.identifier.Val() == "shadow" &&
                    decl.GetTy().getOrThrow().kind == TypeKind.TYPE_BOOLEAN) {
                    innerShadows.add(decl)
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Assert(sites.size, 1)
        @Assert(innerShadows.size, 1)
        @Assert(parameters.size, 1)
        let site = sites[0]
        @Assert(!site.scopeName.isEmpty())
        @Assert(site.curFile.isSome())
        @Expect(!instance.GetASTContextByPackage(pkg).getOrThrow().symbolTable.isEmpty())
        let shadow = LookupAt(instance, pkg, site, "shadow")
        @Assert(shadow.decls.size, 1)
        @Expect(SameDecl(shadow.decls[0], innerShadows[0]))
        let parameter = LookupAt(instance, pkg, site, "parameter")
        @Assert(parameter.decls.size, 1)
        @Expect(SameDecl(parameter.decls[0], parameters[0]))
        @Expect(LookupAt(instance, pkg, site, "later").decls.isEmpty())
        @Expect(LookupAt(instance, pkg, site, "missing").decls.isEmpty())

        // Refreshing parse contexts must not replace the live semantic context.
        instance.RefreshASTContexts()
        let refreshed = LookupAt(instance, pkg, site, "parameter")
        @Assert(refreshed.decls.size, 1)
        @Expect(SameDecl(refreshed.decls[0], parameters[0]))
        let unrelated = Package()
        unrelated.fullPackageName = pkg.fullPackageName
        @Expect(instance.GetASTContextByPackage(unrelated).isNone())
        @Expect(result.diag.GetErrorCount(), if (incomplete) { 1u64 } else { 0u64 })
        instance.DestroyASTResources()
        instance.JoinDestroyASTResources()
        @Expect(instance.GetASTContextByPackage(pkg).isNone())
    } finally {
        instance.DestroyASTResources()
        instance.JoinDestroyASTResources()
    }
}

@Test
public class ASTContextLookupTest {
    @TestCase
    public func completeSourceUsesSemanticContext(): Unit {
        CheckPublicContextLookup(false)
    }

    @TestCase
    public func incompleteSourceRetainsSemanticLookup(): Unit {
        CheckPublicContextLookup(true)
    }

    @TestCase
    public func parseOnlyRetainsStageContext(): Unit {
        let result = CompileSource("package parse_context\nfunc f(): Int64 { 1 }", stage: CompileStage.PARSE)
        let instance = result.instance
        try {
            @Assert(result.ok)
            @Expect(instance.faithfulSemaInstance.isNone())
            let pkg = RequireFirstPackage(result)
            let context = instance.GetASTContextByPackage(pkg).getOrThrow()
            @Expect(context.curPackage.getOrThrow() == pkg)
            @Expect(context.symbolTable.isEmpty())
            let unknown = Package()
            unknown.fullPackageName = "unknown_package"
            @Expect(instance.GetASTContextByPackage(unknown).isNone())
        } finally {
            instance.DestroyASTResources()
            instance.JoinDestroyASTResources()
        }
    }
}
