package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import cjcj::ast.*

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// GenerateJavaMirrorInterfaceDefaultMethodStub.cpp:21-33.
private func RemoveAbstractAttributeForJavaHasDefaultMethods(decl: InterfaceDecl): Unit {
    for (member in decl.GetMemberDeclPtrs()) {
        if (member.TestAttr(Attribute.JAVA_HAS_DEFAULT)) {
            member.DisableAttr(Attribute.ABSTRACT)
            member.EnableAttr(Attribute.DEFAULT)
        }
    }
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// GenerateJavaMirrorInterfaceDefaultMethodStub.h:26-35 and .cpp:37-57.
public class GenerateJavaMirrorInterfaceDefaultMethodStub <: PreTypeCheckStage {
    public init() {}

    private func InsertJavaHasDefaultMethodStubs(ctx: PreTypeCheckContext, id: InterfaceDecl): Unit {
        for (decl in id.GetMemberDeclPtrs()) {
            if (let Some(fd) <- (decl as FuncDecl)) {
                if (fd.TestAttr(Attribute.JAVA_HAS_DEFAULT)) {
                    InsertMethodStub(fd, ctx.importManager, ctx.typeManager)
                }
            }
        }
    }

    public func Process(ctx: PreTypeCheckContext): Unit {
        for (mirror in ctx.javaMirrors) {
            if (let Some(mirrorInterface) <- (mirror as InterfaceDecl)) {
                RemoveAbstractAttributeForJavaHasDefaultMethods(mirrorInterface)
                InsertJavaHasDefaultMethodStubs(ctx, mirrorInterface)
            }
        }
    }
}
