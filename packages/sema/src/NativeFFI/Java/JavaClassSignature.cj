package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.SplitString
import cjcj::sema.NativeFFI.{GetJavaPackage, GetJavaUnqualifiedTypeName, JoinVector}
import cjcj::utils.CJC_ASSERT

private func ToList(parts: Array<String>): ArrayList<String> {
    let result = ArrayList<String>()
    for (part in parts) {
        result.add(part)
    }
    return result
}

private func WithoutTail(types: Array<String>): ArrayList<String> {
    let result = ArrayList<String>()
    if (types.size < 2) {
        return result
    }
    for (i in 0..(types.size - 1)) {
        result.add(types[i])
    }
    return result
}

// Upstream JavaClassSignature.cpp:34-126. Source identity and the JNI spelling are separate.
// The stored leaf is named typeName because `type` is a Cangjie keyword; upstream field is `type`.
public class JavaClassSignature <: Hashable & Equatable<JavaClassSignature> {
    private let packageParts: ArrayList<String>
    private let outerTypes: ArrayList<String>
    private let typeName: String

    private init(packageName: String, typeName: String) {
        this.packageParts = ToList(SplitString(packageName, "."))
        let types = SplitString(typeName, ".")
        this.outerTypes = WithoutTail(types)
        CJC_ASSERT(!types.isEmpty())
        this.typeName = types[types.size - 1]
        CJC_ASSERT(!this.typeName.isEmpty())
    }

    public static func FromDecl(decl: ClassLikeDecl): JavaClassSignature {
        return JavaClassSignature(GetJavaPackage(decl), GetJavaUnqualifiedTypeName(decl, "."))
    }

    public static func GetConstructorMarkerClass(): JavaClassSignature {
        return JavaClassSignature("cangjie.lang.internal", "$$NativeConstructorMarker")
    }

    public func IsNested(): Bool {
        return !outerTypes.isEmpty()
    }

    public func ToString(): String {
        return GetFQName()
    }

    public func GetJniClassName(): String {
        var name = JoinVector(packageParts, "/") + "/"
        if (IsNested()) {
            name += JoinVector(outerTypes, "$") + "$"
        }
        return name + typeName
    }

    public func GetFQName(): String {
        var name = JoinVector(packageParts, ".") + "."
        if (IsNested()) {
            name += JoinVector(outerTypes, ".") + "."
        }
        return name + typeName
    }

    public func GetUnqualifiedTypeName(nestedDelimiter!: String = "."): String {
        if (!IsNested()) {
            return typeName
        }
        return JoinVector(outerTypes, nestedDelimiter) + nestedDelimiter + typeName
    }

    public operator func ==(other: JavaClassSignature): Bool {
        return ToString() == other.ToString()
    }

    public operator func !=(other: JavaClassSignature): Bool {
        return !(this == other)
    }

    public func hashCode(): Int64 {
        return ToString().hashCode()
    }
}
