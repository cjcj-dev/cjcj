package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import cjcj::ast.*

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/
// RewriteJavaMirrorFields.h:26-34 and .cpp:19-27.
public class RewriteJavaMirrorFields <: PreTypeCheckStage {
    public init() {}

    public func Process(ctx: PreTypeCheckContext): Unit {
        for (mirror in ctx.javaMirrors) {
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                InsertMirrorVarProp(mirrorClass, Attribute.JAVA_MIRROR)
            }
        }
    }
}
