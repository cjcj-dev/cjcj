package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{GetJavaMemberName, GetParamTys, Utils}
import cjcj::utils.CJC_ASSERT

private enum JavaMemberKind <: Equatable<JavaMemberKind> {
    | FIELD | METHOD | CONSTRUCTOR

    public operator func ==(other: JavaMemberKind): Bool {
        return match ((this, other)) {
            case (FIELD, FIELD) | (METHOD, METHOD) | (CONSTRUCTOR, CONSTRUCTOR) => true
            case _ => false
        }
    }

    public operator func !=(other: JavaMemberKind): Bool {
        return !(this == other)
    }
}

public class JavaMemberSignature <: Hashable & Equatable<JavaMemberSignature> {
    public let classSignature: JavaClassSignature
    public prop classTypeJniName: String { get() { return classSignature.GetJniClassName() } }
    public let name: String
    public let signature: String
    public let isStatic: Bool
    private let kind: JavaMemberKind
    public prop isMethod: Bool { get() { return kind == JavaMemberKind.METHOD } }
    public prop isField: Bool { get() { return kind == JavaMemberKind.FIELD } }

    private init(classSignature: JavaClassSignature, name: String, signature: String, kind: JavaMemberKind,
        isStatic!: Bool = false) {
        this.classSignature = classSignature
        this.name = name
        this.signature = signature
        this.isStatic = isStatic
        this.kind = kind
        CJC_ASSERT(kind != JavaMemberKind.CONSTRUCTOR || !isStatic)
    }

    public func GetClassSignature(): JavaClassSignature {
        return classSignature
    }

    public func GetClassTypeJniName(): String {
        return classSignature.GetJniClassName()
    }

    public func UnqualifiedTypeName(): String {
        return classSignature.GetUnqualifiedTypeName(nestedDelimiter: "$")
    }

    // JavaMemberSignature.cpp:147-162. Class identity is JavaClassSignature, not the JNI spelling.
    public operator func ==(other: JavaMemberSignature): Bool {
        if (signature != other.signature) {
            return false
        }
        if (kind != other.kind) {
            return false
        }
        if (isStatic != other.isStatic) {
            return false
        }
        if (classSignature != other.classSignature) {
            return false
        }
        return name == other.name
    }

    public operator func !=(other: JavaMemberSignature): Bool {
        return !(this == other)
    }

    public func hashCode(): Int64 {
        return (GetClassTypeJniName() + "$" + name + "$$" + signature + if (isStatic) { "1" } else { "0" }).hashCode()
    }

    public static func FromMethod(utils: Utils, method: FuncDecl): JavaMemberSignature {
        CJC_ASSERT(method.outerDecl.isSome())
        let outerDecl = (method.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        CJC_ASSERT(!method.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.FINALIZER))
        CJC_ASSERT(IsMirror(outerDecl) || IsImpl(outerDecl))
        let className = JavaClassSignature.FromDecl(outerDecl)
        let body = method.funcBody.getOrThrow()
        let signature = utils.GetJavaTypeSignature(body.retType.getOrThrow().GetTy().getOrThrow(),
            GetParamTys(body.paramLists[0]), fullPackageName: method.fullPackageName)
        return JavaMemberSignature(className, GetJavaMemberName(method), signature, JavaMemberKind.METHOD,
            isStatic: method.TestAttr(Attribute.STATIC))
    }

    public static func FromConstructor(utils: Utils, ctor: FuncDecl, withMarker: Bool): JavaMemberSignature {
        CJC_ASSERT(ctor.outerDecl.isSome())
        CJC_ASSERT(ctor.TestAttr(Attribute.CONSTRUCTOR))
        let outerDecl = (ctor.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        let className = JavaClassSignature.FromDecl(outerDecl)
        let paramTys = GetParamTys(ctor.funcBody.getOrThrow().paramLists[0])
        var signature = "("
        for (paramTy in paramTys) {
            signature = signature + utils.GetJavaTypeSignature(paramTy)
        }
        if (withMarker) {
            signature = signature + "L" + JavaClassSignature.GetConstructorMarkerClass().GetJniClassName() + ";"
        }
        signature = signature + ")V"
        return JavaMemberSignature(className, "<init>", signature, JavaMemberKind.CONSTRUCTOR)
    }

    public static func FromProperty(utils: Utils, propDecl: PropDecl): JavaMemberSignature {
        CJC_ASSERT(propDecl.outerDecl.isSome())
        let outerDecl = (propDecl.outerDecl.getOrThrow() as ClassLikeDecl).getOrThrow()
        CJC_ASSERT(IsMirror(outerDecl) || IsImpl(outerDecl))
        let className = JavaClassSignature.FromDecl(outerDecl)
        let signature = utils.GetJavaTypeSignature(propDecl.GetTy().getOrThrow(), fullPackageName: propDecl.fullPackageName)
        return JavaMemberSignature(className, GetJavaMemberName(propDecl), signature, JavaMemberKind.FIELD,
            isStatic: propDecl.TestAttr(Attribute.STATIC))
    }
}

public func UnqualifiedJniTypeName(classTypeJniName: String): String {
    var text = classTypeJniName
    if (text.endsWith(";")) {
        text = text[0..text.size - 1]
    }
    if (text.startsWith("L") && text.contains("/")) {
        text = text[1..]
    }
    if (let Some(slash) <- text.lastIndexOf("/")) {
        text = text[slash + 1..]
    }
    return text
}
