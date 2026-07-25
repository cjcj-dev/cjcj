package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import cjcj::ast.*
import cjcj::sema.NativeFFI.WithinFile
import cjcj::sema.NativeFFI.Java.GetMirrorReferenceWrapperNameFromClassLike
import cjcj::utils.{CJC_ASSERT, INTEROP_JOBJECT_NAME}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// GenerateJavaMirrorReferenceWrapperClass.cpp:26-35.
private func InsertSuperTypes(wrapper: ClassDecl, mirror: ClassLikeDecl): Unit {
    if (mirror.astKind == ASTKind.INTERFACE_DECL) {
        let jobject = WithinFile(CreateRefType(INTEROP_JOBJECT_NAME), mirror.curFile)
        jobject.begin = mirror.begin
        jobject.end = mirror.end
        wrapper.inheritedTypes.add(jobject)
    }
    wrapper.inheritedTypes.add(CreateRefType(mirror))
}

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// GenerateJavaMirrorReferenceWrapperClass.h:39-53 and .cpp:38-65.
public class GenerateJavaMirrorReferenceWrapperClass <: PreTypeCheckStage {
    public init() {}

    private func ShouldHaveMirrorReferenceWrapper(node: Node): Bool {
        return IsMirror(node) && (node.IsInterfaceDecl() || node.IsAbstractClass())
    }

    private func GenerateWrapperClass(mirror: ClassLikeDecl): ClassDecl {
        CJC_ASSERT(ShouldHaveMirrorReferenceWrapper(mirror))
        let wrapper = CloneClassSkeleton(mirror, GetMirrorReferenceWrapperNameFromClassLike(mirror))
        wrapper.EnableAttr(Attribute.JAVA_MIRROR)
        wrapper.EnableAttr(Attribute.JAVA_MIRROR_SUBTYPE)
        wrapper.EnableAttr(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)

        InsertSuperTypes(wrapper, mirror)
        return wrapper
    }

    public func Process(ctx: PreTypeCheckContext): Unit {
        for (mirror in ctx.javaMirrors) {
            if (!ShouldHaveMirrorReferenceWrapper(mirror)) {
                continue
            }
            ctx.AddGeneratedDecl(GenerateWrapperClass(mirror))
        }
    }
}
