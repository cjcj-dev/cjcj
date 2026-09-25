package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::frontend.CompileStage
import cjcj::sema.Test.MockUtils

private func RequireClass(pkg: Package, name: String): ClassDecl {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                if (classDecl.identifier.Val() == name) {
                    return classDecl
                }
            }
        }
    }
    throw IllegalStateException("missing class: " + name)
}

private func RequireExtendOf(pkg: Package, typeName: String): ExtendDecl {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
                        if (typeDecl.identifier.Val() == typeName) {
                            return extendDecl
                        }
                    }
                }
            }
        }
    }
    throw IllegalStateException("missing extend of: " + typeName)
}

private func CountGeneratedDefaultAccessors(decl: Decl): Int64 {
    var count: Int64 = 0
    for (member in decl.GetMemberDecls()) {
        if (member.TestAttr(Attribute.GENERATED_TO_MOCK) &&
            member.identifier.Val().contains(MockUtils.defaultAccessorSuffix)) {
            count++
        }
    }
    return count
}

@Test
public class MockDefaultPrepareTest {
    @TestCase
    public func transitiveSuperInterfaceDefaultIsPreparedOnce(): Unit {
        let result = CompileSource("""
            package mock_defaults
            public interface Grand {
                func fromGrand(): Int64 { 3 }
            }
            public interface Mid <: Grand {}
            public class Child <: Mid {}
            """, stage: CompileStage.DESUGAR_AFTER_SEMA, mockOn: true)
        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let child = RequireClass(RequireFirstPackage(result), "Child")
        let count = CountGeneratedDefaultAccessors(child)
        println("TRANSITIVE_BUDDY_COUNT=${count}")
        @Expect(count, 1)
    }

    @TestCase
    public func directSupertypePreferredOverExtend(): Unit {
        let result = CompileSource("""
            package mock_defaults
            public interface Grand {
                func fromGrand(): Int64 { 7 }
            }
            public interface Mid1 <: Grand {}
            public interface Mid2 <: Grand {}
            public class Host <: Mid1 {}
            extend Host <: Mid2 {}
            """, stage: CompileStage.DESUGAR_AFTER_SEMA, mockOn: true)
        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let pkg = RequireFirstPackage(result)
        let host = RequireClass(pkg, "Host")
        let extendDecl = RequireExtendOf(pkg, "Host")
        let onClass = CountGeneratedDefaultAccessors(host)
        let onExtend = CountGeneratedDefaultAccessors(extendDecl)
        println("DIRECT_CLASS_BUDDY=${onClass}")
        println("DIRECT_EXTEND_BUDDY=${onExtend}")
        @Expect(onClass == 1 && onExtend == 0)
    }
}
