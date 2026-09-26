package cjcj::compiler_unittest

import std.collection.ArrayList
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::frontend.*
import cjcj::sema.OverrideFunctionResolver
import cjcj::driver.HostTripleInfo
import cjcj::option.{OutputMode, OptimizationLevel}
import cjcj::utils.{FileUtil, GenerateRandomHexString}

private func NewOverrideInstance(code: String, dir: String, source: String): CompilerInstance {
    let path = FileUtil.JoinPath(dir, source + ".cj")
    let _ = FileUtil.WriteToFile(path, code)
    let invocation = CompilerInvocation()
    let opts = invocation.globalOptions
    let home = getVariable("CANGJIE_HOME").getOrThrow()
    opts.cangjieHome = home
    opts.executablePath = home + "/bin/cjc"
    opts.host = HostTripleInfo()
    opts.target = HostTripleInfo()
    opts.srcFiles.add(path)
    opts.importPaths.add(dir)
    opts.outputMode = OutputMode.STATIC_LIB
    opts.output = dir + "/" + source + ".a"
    opts.disableCodeGen = true
    opts.optimizationLevel = OptimizationLevel.O2
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName(source)
    let instance = CompilerInstance(invocation, DiagnosticEngine())
    instance.buildTrie = false
    return instance
}

@Test
public class GetTopOverriddenFuncDeclTest {
    // Upstream 0bbc4bd0 GetTopOverriddenFuncThatSourceExported02/03.
    // Both imported-source shapes share one invariant and one cut-sensitive test.
    @TestCase
    public func sourceImportedExtendImplementationReachesInterfaceRoot(): Unit {
        let bodies = [
            """
            public class A {}
            extend A {
                public func f(a: Int64): Int64 { return 1 }
            }
            extend A <: I<Int64> {}
            @Frozen
            public func foo() { return A().f(5) }
            """,
            """
            public open class A {
                public open func f(a: Int64): Int64 { return a + 1 }
            }
            extend A <: I<Int64> {}
            public class B <: A {
                public func f(a: Int64): Int64 { return a + 1 }
            }
            @Frozen
            public func foo() { B().f(1) }
            """
        ]
        for (i in 0..bodies.size) {
            let dir = getVariable("TMPDIR").getOrThrow() + "/override-" + GenerateRandomHexString()
            let _ = FileUtil.CreateDirs(dir + "/")
            let dep = NewOverrideInstance("package dep\npublic interface I<T> { func f(a: T): Int64 }\n" +
                bodies[i], dir, "dep")
            let depOk = dep.Compile(stage: CompileStage.DESUGAR_AFTER_SEMA)
            println("OVERRIDE_DEP case=${i} ok=${depOk} packages=${dep.GetSourcePackages().size}")
            @Assert(depOk)
            let data = dep.ExportAST(false, dep.GetSourcePackages()[0])
            @Assert(FileUtil.WriteBufferToASTFile(dir + "/dep.cjo", data))
            let mainInstance = NewOverrideInstance("import dep.*\nmain(): Int64 { foo() }", dir, "main")
            mainInstance.importManager.getOrThrow().SetSourceCodeImportStatus(true)
            let mainOk = mainInstance.Compile(stage: CompileStage.SEMA)
            println("OVERRIDE_MAIN case=${i} ok=${mainOk} imported=${mainInstance.importManager.getOrThrow().GetAllImportedPackages().size}")
            @Assert(mainOk)
            let foo = mainInstance.importManager.getOrThrow().GetImportedDecl<FuncDecl>("dep", "foo").getOrThrow()
            let callees = ArrayList<FuncDecl>()
            let _ = Walker(foo, visitPre: Some({ node: Node =>
                if (let Some(call) <- (node as CallExpr)) {
                    if (let Some(member) <- call.baseFunc.flatMap({ expr => expr as MemberAccess })) {
                        if (member.field == "f") {
                            if (let Some(fd) <- call.resolvedFunction) { callees.add(fd) }
                        }
                    }
                }
                VisitAction.WALK_CHILDREN
            })).Walk()
            @Assert(!callees.isEmpty())
            let callee = Some(callees[callees.size - 1])
            @Expect(callee.getOrThrow().TestAttr(Attribute.IMPORTED))
            let manager = mainInstance.faithfulSemaInstance.getOrThrow().typeManager
            let top = manager.GetTopOverriddenFuncDecl(callee)
            let actual = if (let Some(fd) <- top) {
                fd.outerDecl.getOrThrow().identifier.Val() + "." + fd.identifier.Val()
            } else { "<none>" }
            println("OVERRIDE_TOP_ASSERT case=${i} actual=${actual} expected=I.f")
            @Expect(actual, "I.f")
            @Expect(top.isSome() && top.getOrThrow().TestAttr(Attribute.ABSTRACT))
        }
    }

    @TestCase
    public func alreadyTopReturnsItself(): Unit {
        let dir = getVariable("TMPDIR").getOrThrow() + "/override-control-" + GenerateRandomHexString()
        let _ = FileUtil.CreateDirs(dir + "/")
        let instance = NewOverrideInstance("package control\npublic interface I { func f(): Int64 }", dir, "control")
        let ok = instance.Compile(stage: CompileStage.SEMA)
        @Assert(ok)
        let decl = (instance.GetSourcePackages()[0].files[0].decls[0] as InterfaceDecl).getOrThrow()
        let fd = (decl.GetMemberDecls()[0] as FuncDecl).getOrThrow()
        let top = instance.faithfulSemaInstance.getOrThrow().typeManager.GetTopOverriddenFuncDecl(Some(fd))
        @Expect(top.isSome() && SameDecl(top.getOrThrow(), fd))
        println("OVERRIDE_CONTROL_ASSERT top=I.f")
    }

    @TestCase
    public func unrelatedConstraintStaysOnItsInterface(): Unit {
        let dir = getVariable("TMPDIR").getOrThrow() + "/override-norelation-" + GenerateRandomHexString()
        let _ = FileUtil.CreateDirs(dir + "/")
        let instance = NewOverrideInstance("""
package norelation
public interface AAA {
    func foo(x: Int64): Int64
}
public interface BBB {
    func foo(x: Int64): Int64
}
func posion<T>(x: T): Int64 where T <: AAA & BBB {
    0
}
public func goo<R>(x: R): Int64 where R <: BBB {
    x.foo(1)
}
main() {}
""", dir, "norelation")
        let ok = instance.Compile(stage: CompileStage.SEMA)
        println("OVERRIDE_NORELATION_COMPILE ok=${ok}")
        @Assert(ok)
        let callee = FindNamedCallee(instance.GetSourcePackages()[0], "foo")
        @Assert(callee.isSome())
        let top = instance.faithfulSemaInstance.getOrThrow().typeManager.GetTopOverriddenFuncDecl(callee)
        let actual = QualNameOf(top)
        println("OVERRIDE_NORELATION_ASSERT actual=${actual} expected=BBB.foo")
        @Expect(actual, "BBB.foo")
    }

    @TestCase
    public func multiSuperPicksEarliestPosition(): Unit {
        let dir = getVariable("TMPDIR").getOrThrow() + "/override-multisuper-" + GenerateRandomHexString()
        let _ = FileUtil.CreateDirs(dir + "/")
        let instance = NewOverrideInstance("""
package multisuper
public interface AAA {
    func foo(x: Int64): Int64
}
public interface BBB {
    func foo(x: Int64): Int64
}
public class CCC <: AAA & BBB {
    public func foo(x: Int64): Int64 {
        x
    }
}
main() {
    CCC().foo(1)
}
""", dir, "multisuper")
        let ok = instance.Compile(stage: CompileStage.SEMA)
        println("OVERRIDE_MULTI_COMPILE ok=${ok}")
        @Assert(ok)
        let callee = FindNamedCallee(instance.GetSourcePackages()[0], "foo")
        @Assert(callee.isSome())
        let fd = callee.getOrThrow()
        let manager = instance.faithfulSemaInstance.getOrThrow().typeManager
        let tops = OverrideFunctionResolver(manager).GetTopOverriddenFuncs(
            fd.outerDecl.getOrThrow().GetTy().getOrThrow(), fd)
        var hasAAA = false
        var hasBBB = false
        var listed = ""
        for (top in tops) {
            let name = top.outerDecl.getOrThrow().identifier.Val() + "." + top.identifier.Val()
            listed = listed + name + ","
            if (name == "AAA.foo") {
                hasAAA = true
            }
            if (name == "BBB.foo") {
                hasBBB = true
            }
        }
        println("OVERRIDE_MULTI_SET size=${tops.size} names=${listed}")
        @Expect(tops.size, 2)
        @Expect(hasAAA)
        @Expect(hasBBB)
        var i: Int64 = 0
        while (i < 32) {
            let actual = QualNameOf(manager.GetTopOverriddenFuncDecl(callee))
            println("OVERRIDE_MULTI_ASSERT i=${i} actual=${actual} expected=AAA.foo")
            @Expect(actual, "AAA.foo")
            i++
        }
    }

    @TestCase
    public func extendChainSourceDeclReachesInterfaceRoot(): Unit {
        let dir = getVariable("TMPDIR").getOrThrow() + "/override-chain-" + GenerateRandomHexString()
        let _ = FileUtil.CreateDirs(dir + "/")
        let instance = NewOverrideInstance("""
package chain
public interface I<T> {
    func f(a: T): Int64
}
public open class A {
    public open func f(a: Int64): Int64 {
        a + 1
    }
}
extend A <: I<Int64> {}
public class B <: A {
    public func f(a: Int64): Int64 {
        a + 1
    }
}
main() {
    B().f(1)
}
""", dir, "chain")
        let ok = instance.Compile(stage: CompileStage.SEMA)
        println("OVERRIDE_CHAIN_COMPILE ok=${ok}")
        @Assert(ok)
        var sourceBF: Option<FuncDecl> = None
        for (file in instance.GetSourcePackages()[0].files) {
            for (decl in file.decls) {
                if (let Some(classDecl) <- (decl as ClassDecl)) {
                    if (classDecl.identifier.Val() == "B") {
                        for (member in classDecl.GetMemberDecls()) {
                            if (let Some(funcDecl) <- (member as FuncDecl)) {
                                if (funcDecl.identifier.Val() == "f") {
                                    sourceBF = Some(funcDecl)
                                }
                            }
                        }
                    }
                }
            }
        }
        @Assert(sourceBF.isSome())
        let manager = instance.faithfulSemaInstance.getOrThrow().typeManager
        let actual = QualNameOf(manager.GetTopOverriddenFuncDecl(sourceBF))
        println("OVERRIDE_CHAIN_ASSERT actual=${actual} expected=I.f")
        @Expect(actual, "I.f")
    }
}

private func FindNamedCallee(pkg: Package, name: String): Option<FuncDecl> {
    let found = ArrayList<FuncDecl>()
    for (file in pkg.files) {
        let _ = Walker(file, visitPre: Some({ node: Node =>
            if (let Some(call) <- (node as CallExpr)) {
                if (let Some(member) <- call.baseFunc.flatMap({ expr => expr as MemberAccess })) {
                    if (member.field == name) {
                        if (let Some(resolved) <- call.resolvedFunction) {
                            found.add(resolved)
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        })).Walk()
    }
    if (found.isEmpty()) {
        return None
    }
    return Some(found[found.size - 1])
}

private func QualNameOf(top: Option<FuncDecl>): String {
    if (let Some(fd) <- top) {
        return fd.outerDecl.getOrThrow().identifier.Val() + "." + fd.identifier.Val()
    }
    return "<none>"
}
