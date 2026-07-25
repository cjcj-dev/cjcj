package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import cjcj::ast.*
import cjcj::sema.NativeFFI.Java.GetImplRegistryCompanionClassName
import cjcj::utils.CJC_ASSERT

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// GenerateJavaImplRegistryCompanion.h:38-47 and .cpp:23-38.
public class GenerateJavaImplRegistryCompanion <: PreTypeCheckStage {
    public init() {}

    private func GenerateRegistryCompanion(impl: ClassDecl): ClassDecl {
        CJC_ASSERT(IsImpl(impl))
        let regCompanion = CloneClassSkeleton(impl, GetImplRegistryCompanionClassName(impl))
        regCompanion.EnableAttr(Attribute.JAVA_IMPL_REGISTRY_COMPANION)
        return regCompanion
    }

    protected override func Process(ctx: PreTypeCheckContext): Unit {
        for (impl in ctx.javaImpls) {
            ctx.AddGeneratedDecl(GenerateRegistryCompanion(impl))
        }
    }
}
