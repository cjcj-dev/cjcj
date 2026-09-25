package cjcj::sema.NativeFFI.Java

import cjcj::ast.*

public class GenerateJavaImplApiStub {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}

public class GenerateInJavaImplRegistryCompanion {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (companion in ctx.GetJavaImplRegistryCompanions()) {
            if (companion.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
        }
    }
}

public class DesugarJavaImplSuperConstructorCall {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplWrappingConstructor(impl)) {
                continue
            }
        }
    }
}

public class GenerateInJavaImplReferenceWrapper {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}

public class DesugarJavaImplSuperMethodCall {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplWrappingConstructor(impl)) {
                continue
            }
        }
    }
}

public class RewriteJavaImplReferenceWrapperFields {
    public func Process(ctx: AfterTypeCheckContext, desugarPropRef: (Node) -> Unit): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
        let _ = desugarPropRef
    }
}

public class GenerateNativeBridgeForJavaImpl {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}
