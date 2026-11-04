package cjcj::compiler_unittest

import std.collection.{ArrayList, HashMap, HashSet}
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

    // Upstream 16831cf5 DeepInterfaceRedefinitionsResolveToRoot: every interface redefines the
    // same method, so an unshared recursive walk over all transitive ancestors is exponential.
    @TestCase
    public func deepInterfaceRedefinitionsResolveToRoot(): Unit {
        for (modifier in ["static ", ""]) {
            let kind = if (modifier.isEmpty()) { "instance" } else { "static" }
            let depth = 32
            var code = "package deep\npublic interface I_0 { ${modifier}func sf(): Unit {} }\n"
            for (i in 1..=depth) {
                code = code + "public interface I_${i} <: I_${i - 1} { ${modifier}func sf(): Unit {} }\n"
            }
            let dir = getVariable("TMPDIR").getOrThrow() + "/override-deep-" + GenerateRandomHexString()
            let _ = FileUtil.CreateDirs(dir + "/")
            let instance = NewOverrideInstance(code, dir, "deep")
            let ok = instance.Compile(stage: CompileStage.SEMA)
            println("OVERRIDE_DEEP_COMPILE modifier=${kind} ok=${ok}")
            @Assert(ok)
            let funcs = CollectMemberFuncs(instance.GetSourcePackages()[0])
            let leaf = funcs.get("I_${depth}.sf")
            @Assert(leaf.isSome())
            let fd = leaf.getOrThrow()
            let manager = instance.faithfulSemaInstance.getOrThrow().typeManager
            let tops = OverrideFunctionResolver(manager).GetTopOverriddenFuncs(
                fd.outerDecl.getOrThrow().GetTy().getOrThrow(), fd)
            let names = QualNamesOf(tops)
            println("OVERRIDE_DEEP_ASSERT modifier=${kind} size=${tops.size} names=${names} expected=I_0.sf")
            @Expect(tops.size, 1)
            @Expect(names, "I_0.sf,")
            @Expect(QualNameOf(manager.GetTopOverriddenFuncDecl(leaf)), "I_0.sf")
        }
    }

    // Upstream 16831cf5 DiamondPreservesSharedAndIndependentRoots: a cached Root.f subproblem
    // must not hide the independent Other.f root reached only through Right.
    @TestCase
    public func diamondPreservesSharedAndIndependentRoots(): Unit {
        let tops = TopsOfNamedFunc("""
package diamond
public interface Root { func f(): Unit }
public interface Other { func f(): Unit }
public interface Left <: Root { func f(): Unit {} }
public interface Right <: Root & Other { func f(): Unit {} }
public interface Leaf <: Left & Right { func f(): Unit {} }
""", "diamond", "Leaf.f")
        println("OVERRIDE_DIAMOND_ASSERT names=${tops} expected=Other.f,Root.f,")
        @Expect(tops, "Other.f,Root.f,")
    }

    // Upstream 16831cf5 GenericDiamondResolvesToSharedRoot.
    @TestCase
    public func genericDiamondResolvesToSharedRoot(): Unit {
        let tops = TopsOfNamedFunc("""
package gdiamond
public interface Root<T> { func f(x: T): T { x } }
public interface Left<T> <: Root<T> { func f(x: T): T { x } }
public interface Right<T> <: Root<T> { func f(x: T): T { x } }
public interface Leaf <: Left<Int64> & Right<Int64> { func f(x: Int64): Int64 { x } }
""", "gdiamond", "Leaf.f")
        println("OVERRIDE_GDIAMOND_ASSERT names=${tops} expected=Root.f,")
        @Expect(tops, "Root.f,")
    }

    // Generic diamond reached only through an extend of a class: the extend's super interfaces are
    // part of the same query, and both generic paths share the Root<T> subproblem.
    @TestCase
    public func genericExtendDiamondResolvesToSharedRoot(): Unit {
        let tops = TopsOfNamedFunc("""
package gextend
public interface Root<T> { func f(x: T): T }
public interface Left<T> <: Root<T> { func f(x: T): T { x } }
public interface Right<T> <: Root<T> { func f(x: T): T { x } }
public class A {
    public func f(x: Int64): Int64 { x }
}
extend A <: Left<Int64> & Right<Int64> {}
""", "gextend", "A.f")
        println("OVERRIDE_GEXTEND_ASSERT names=${tops} expected=Root.f,")
        @Expect(tops, "Root.f,")
    }

    // Upstream 16831cf5 UnrelatedMethodsHaveNoOverriddenRoot: empty results are cached and still
    // make GetTopOverriddenFuncDecl return the function itself.
    @TestCase
    public func unrelatedMethodsHaveNoOverriddenRoot(): Unit {
        let dir = getVariable("TMPDIR").getOrThrow() + "/override-unrelated-" + GenerateRandomHexString()
        let _ = FileUtil.CreateDirs(dir + "/")
        let instance = NewOverrideInstance("""
package unrelated
public interface Root { static func f(): Unit {} }
public interface Leaf <: Root { static func g(): Unit {} }
""", dir, "unrelated")
        let ok = instance.Compile(stage: CompileStage.SEMA)
        @Assert(ok)
        let funcs = CollectMemberFuncs(instance.GetSourcePackages()[0])
        let manager = instance.faithfulSemaInstance.getOrThrow().typeManager
        let resolver = OverrideFunctionResolver(manager)
        for (name in ["Root.f", "Leaf.g"]) {
            let found = funcs.get(name)
            @Assert(found.isSome())
            let fd = found.getOrThrow()
            let tops = resolver.GetTopOverriddenFuncs(fd.outerDecl.getOrThrow().GetTy().getOrThrow(), fd)
            let top = manager.GetTopOverriddenFuncDecl(found)
            println("OVERRIDE_UNRELATED_ASSERT name=${name} size=${tops.size} top=${QualNameOf(top)}")
            @Expect(tops.isEmpty())
            @Expect(top.isSome() && SameDecl(top.getOrThrow(), fd))
        }
    }
}

private func TopsOfNamedFunc(code: String, pkgName: String, qualName: String): String {
    let dir = getVariable("TMPDIR").getOrThrow() + "/override-" + pkgName + "-" + GenerateRandomHexString()
    let _ = FileUtil.CreateDirs(dir + "/")
    let instance = NewOverrideInstance(code, dir, pkgName)
    let ok = instance.Compile(stage: CompileStage.SEMA)
    println("OVERRIDE_COMPILE pkg=${pkgName} ok=${ok}")
    if (!ok) {
        return "<compile failed>"
    }
    let found = CollectMemberFuncs(instance.GetSourcePackages()[0]).get(qualName)
    if (found.isNone()) {
        return "<missing ${qualName}>"
    }
    let fd = found.getOrThrow()
    let manager = instance.faithfulSemaInstance.getOrThrow().typeManager
    return QualNamesOf(OverrideFunctionResolver(manager).GetTopOverriddenFuncs(
        fd.outerDecl.getOrThrow().GetTy().getOrThrow(), fd))
}

// Source-declared member functions keyed by "Owner.name"; extends are skipped on purpose.
private func CollectMemberFuncs(pkg: Package): HashMap<String, FuncDecl> {
    let funcs = HashMap<String, FuncDecl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl is ExtendDecl) {
                continue
            }
            for (member in decl.GetMemberDecls()) {
                if (let Some(fd) <- (member as FuncDecl)) {
                    funcs[decl.identifier.Val() + "." + fd.identifier.Val()] = fd
                }
            }
        }
    }
    return funcs
}

// Sorted, comma-terminated qualified names, so set comparisons do not depend on iteration order.
private func QualNamesOf(tops: Iterable<FuncDecl>): String {
    let names = ArrayList<String>()
    let seen = HashSet<String>()
    for (top in tops) {
        let name = QualNameOf(Some(top))
        if (seen.add(name)) {
            names.add(name)
        }
    }
    // Insertion sort: at most a handful of roots.
    for (i in 1..names.size) {
        var j = i
        while (j > 0 && names[j] < names[j - 1]) {
            let tmp = names[j]
            names[j] = names[j - 1]
            names[j - 1] = tmp
            j--
        }
    }
    var out = ""
    for (name in names) {
        out = out + name + ","
    }
    return out
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
