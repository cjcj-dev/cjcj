package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.CreateThrowException
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{GetStringDecl, WithinFile}
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, GetRootPackageName}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/Utils.cpp:23-34.
private func CloneVisibilityAttribute(from: Decl, to: Node): Unit {
    if (from.TestAttr(Attribute.PUBLIC)) {
        to.EnableAttr(Attribute.PUBLIC)
    } else if (from.TestAttr(Attribute.INTERNAL)) {
        to.EnableAttr(Attribute.INTERNAL)
    } else if (from.TestAttr(Attribute.PROTECTED)) {
        to.EnableAttr(Attribute.PROTECTED)
    } else if (from.TestAttr(Attribute.PRIVATE)) {
        to.EnableAttr(Attribute.PRIVATE)
    }
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/Utils.cpp:37-56.
public func CloneClassSkeleton(sample: ClassLikeDecl, name: String): ClassDecl {
    let cd = WithinFile(ClassDecl(), sample.curFile)
    CloneVisibilityAttribute(sample, cd)

    cd.EnableAttr(Attribute.COMPILER_ADD)
    cd.identifier = SrcIdentifier(name)
    cd.identifier.SetPos(sample.identifier.Begin(), sample.identifier.End())

    cd.fullPackageName = sample.curFile.getOrThrow().curPackage.getOrThrow().fullPackageName
    cd.begin = sample.begin
    cd.end = sample.end

    let body = WithinFile(ClassBody(), sample.curFile)
    body.begin = sample.begin
    body.end = sample.end
    cd.body = body
    cd.moduleName = GetRootPackageName(sample.fullPackageName)

    return cd
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/Utils.cpp:58-73.
public func InsertMethodStub(fd: FuncDecl, importManager: SemaImportManager, typeManager: TypeManager): Unit {
    CJC_ASSERT(fd.funcBody.isSome())
    let argTy = GetStringDecl(importManager).GetTy().getOrThrow()
    let arg = CreateLitConstExpr(LitConstKind.STRING, "It's compiler generated stub.", argTy)
    let args = ArrayList<Expr>()
    args.add(arg)

    // C++ caches this lookup in a function-local static. Cangjie has no equivalent construct;
    // repeated core-declaration lookup returns the same declaration during one compilation.
    let exception = GetExceptionDecl(importManager)
    let throwExpr = CreateThrowException(exception, args, fd.curFile.getOrThrow(), typeManager)

    let nodes = ArrayList<Node>()
    nodes.add(throwExpr)
    fd.funcBody.getOrThrow().body = CreateBlock(nodes)
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/Utils.cpp:75-87.
public func GetExceptionDecl(importManager: SemaImportManager): ClassDecl {
    let exceptionDecl = importManager.GetCoreDecl<Decl>("Exception")
    CJC_NULLPTR_CHECK(exceptionDecl)

    let exception = exceptionDecl.getOrThrow() as ClassDecl
    CJC_NULLPTR_CHECK(exception)
    return exception.getOrThrow()
}
