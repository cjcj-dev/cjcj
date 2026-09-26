package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{GetConstructorMarkerFQName, GetJavaJniClassName, GetParamTys, NormalizeJavaSignature, Utils}
import cjcj::utils.CJC_ASSERT

public class JavaMemberSignature {
    public let classTypeJniName: String
    public let name: String
    public let signature: String
    public let isStatic: Bool

    public init(classTypeJniName: String, name: String, signature: String, isStatic: Bool) {
        this.classTypeJniName = classTypeJniName
        this.name = name
        this.signature = signature
        this.isStatic = isStatic
    }

    public static func FromConstructor(utils: Utils, ctor: FuncDecl, withMarker: Bool): JavaMemberSignature {
        CJC_ASSERT(ctor.outerDecl.isSome())
        CJC_ASSERT(ctor.TestAttr(Attribute.CONSTRUCTOR))
        let outerDecl = (ctor.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        let className = GetJavaJniClassName(utils, outerDecl.GetTy().getOrThrow())
        let paramTys = GetParamTys(ctor.funcBody.getOrThrow().paramLists[0])
        var signature = "("
        for (paramTy in paramTys) {
            signature = signature + utils.GetJavaTypeSignature(paramTy)
        }
        if (withMarker) {
            signature = signature + "L" + NormalizeJavaSignature(GetConstructorMarkerFQName()) + ";"
        }
        signature = signature + ")V"
        return JavaMemberSignature(className, "<init>", signature, false)
    }
}
