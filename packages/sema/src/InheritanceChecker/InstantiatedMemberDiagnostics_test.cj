package cjcj::sema.InheritanceChecker

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::basic.{DiagCategory, DiagKindRefactor}
import cjcj::compiler_unittest.*
import cjcj::frontend.CompileStage
import cjcj::sema.TypeManager

private func CheckAmbiguitySites(extended: Bool): Unit {
    // Both parameter type references go through the normal recursive AST walk.
    let header = if (extended) { "class Box<T> {}\nextend<T> Box<T> {" } else { "class Box<T> {" }
    let source = header + "\n    public func pick(x: T): Unit {}\n    public func pick(x: Int64): Unit {}\n}\n" +
        "func first(x: Box<Int64>): Unit {}\nfunc second(x: Box<Int64>): Unit {}"
    let result = CompileSource(source, stage: CompileStage.SEMA)
    let diag = result.instance.faithfulSemaInstance.getOrThrow().diag.getOrThrow()
    let firstMember: Int64 = if (extended) { 3 } else { 2 }
    let firstUse = firstMember + 3
    let at = HashSet<Int64>()
    let errors = diag.GetCategoryDiagnostic(DiagCategory.SEMA)
    @Expect(!result.ok)
    @Expect(result.diag.GetErrorCount(), 2u64)
    @Assert(errors.size, 2)
    for (error in errors) {
        @Expect(error.isRefactor && error.rKind == DiagKindRefactor.sema_generic_instantiation_causes_ambiguous_functions)
        at.add(error.mainHint.range.begin.line)
        @Assert(error.subDiags.size, 2)
        for (i in 0..2) {
            @Expect(error.subDiags[i].subDiagMessage, "found candidate")
            @Expect(error.subDiags[i].mainHint.range.begin.line, firstMember + i)
        }
    }
    @Expect(at.contains(firstUse) && at.contains(firstUse + 1))
}

@Test
public class InstantiatedMemberDiagnosticsTest {
    @TestCase
    public func NominalReportsAtBothUses(): Unit {
        CheckAmbiguitySites(false)
    }

    @TestCase
    public func ExtendReportsAtBothUses(): Unit {
        CheckAmbiguitySites(true)
    }

    @TestCase
    public func DistinctOverloadsDoNotRetainDiagnostics(): Unit {
        let result = CompileSource("""
            interface StaticSide<T> { static func scope(x: T): Unit {} }
            interface InstanceSide { func scope(x: Int64): Unit {} }
            class Legal<T> <: StaticSide<T> & InstanceSide {
                public func mode(this @local!, x: T): Unit {}
                public func mode(this @local?, x: Int64): Unit {}
                public func typed(x: T): Unit {}
                public func typed(x: Bool): Unit {}
            }
            func use(x: Legal<Int64>): Unit {}
            """, stage: CompileStage.SEMA, localMode: true)
        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let pkg = RequireFirstPackage(result)
        let ci = result.instance.faithfulSemaInstance.getOrThrow()
        let checker = StructInheritanceChecker(ci.diag.getOrThrow(), ci.typeManager, pkg, ci.importManager.getOrThrow(),
            opts: ci.globalOptions)
        checker.Check()
        let legal = (pkg.files[0].decls[2] as ClassDecl).getOrThrow()
        let members = checker.GetStoredMembersForDecl(legal)
        for (name in ["scope", "mode", "typed"]) { @Expect(members.Get(name).size, 2) }
        let key = DeclTySeqKey(legal, [TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)])
        @Assert(checker.checkedInstantiatedMemberKeys.contains(key))
        @Expect(checker.instantiatedMemberDiagnostics.size, 0)
        @Expect(ci.diag.getOrThrow().GetErrorCount(), 0u64)
    }

    @TestCase
    public func RepeatedExtendScanKeepsOneConflict(): Unit {
        // Instantiate explicitly so the checker and its cache remain observable after each use.
        let result = CompileSource("""
            class Box<T> {}
            extend<T> Box<T> {
                public func pick(x: T): Unit {}
                public func pick(x: Int64): Unit {}
            }
            func first(): Unit {}
            func second(): Unit {}
            """, stage: CompileStage.SEMA)
        @Assert(result.ok)
        let pkg = RequireFirstPackage(result)
        let ci = result.instance.faithfulSemaInstance.getOrThrow()
        let checker = StructInheritanceChecker(ci.diag.getOrThrow(), ci.typeManager, pkg, ci.importManager.getOrThrow(),
            opts: ci.globalOptions)
        let decl = (pkg.files[0].decls[1] as ExtendDecl).getOrThrow()
        let args = ArrayList<Ty>([TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)])
        let key = DeclTySeqKey(decl, args.toArray())
        for (site in [RequireTopLevelFunc(pkg, "first"), RequireTopLevelFunc(pkg, "second")]) {
            checker.PushInstantiationTrigger(site, decl, args)
            CheckInstMemberSignatures(checker, decl, args)
            checker.PopInstantiationTrigger()
            @Expect(checker.checkedInstantiatedMemberKeys.contains(key))
            @Expect(checker.instantiatedMemberDiagnostics.get(key).getOrThrow().size, 1)
        }
    }
}
