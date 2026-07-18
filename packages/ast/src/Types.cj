package cjcj::ast

import std.collection.*
import std.sort.*
import std.sync.AtomicInt64
import cjcj::utils.Identifiable

private let CORE_PACKAGE_NAME: String = "std.core"
private let STD_LIB_OPTION: String = "Option"
private let CTYPE_NAME: String = "CType"

private func anyInvalid(values: ArrayList<Ty>): Bool {
    for (value in values) {
        if (value.HasInvalidTy()) {
            return true
        }
    }
    return false
}

private func anyGeneric(values: ArrayList<Ty>): Bool {
    for (value in values) {
        if (value.HasGeneric()) {
            return true
        }
    }
    return false
}

private func IsJavaGeneric(gpd: GenericParamDecl): Bool {
    if (let Some(outerDeclValue) <- gpd.outerDecl) {
        if (let Some(_) <- HasJavaAttr(outerDeclValue)) {
            return true
        }
        if (let Some(funcDeclValue) <- (outerDeclValue as FuncDecl)) {
            if (let Some(funcBodyValue) <- funcDeclValue.funcBody) {
                if (let Some(parentClassLikeValue) <- funcBodyValue.parentClassLike) {
                    if (let Some(_) <- HasJavaAttr(parentClassLikeValue)) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

private func typeArgsString(values: ArrayList<Ty>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.String())
    }
    return JoinStrings(parts, delimiter)
}

private func CompTyByNames(left: Ty, right: Ty): Bool {
    let leftStr = left.String()
    let rightStr = right.String()
    if (leftStr < rightStr) {
        return true
    }
    if (leftStr != rightStr) {
        return false
    }
    let leftDecl = Ty.GetDeclPtrOfTy(Some(left))
    let rightDecl = Ty.GetDeclPtrOfTy(Some(right))
    if (let Some(leftDeclValue) <- leftDecl) {
        if (let Some(rightDeclValue) <- rightDecl) {
            return CompNodeByPos(leftDeclValue, rightDeclValue)
        }
    }
    return Ptr<Ty>(left) < Ptr<Ty>(right)
}

private func stableTypeArgsString(values: ArrayList<Ty>, delimiter: String): String {
    let sorted = ArrayList<Ty>()
    for (value in values) {
        var idx: Int64 = 0
        var inserted = false
        while (idx < sorted.size) {
            if (!CompTyByNames(sorted[idx], value) && !CompTyByNames(value, sorted[idx])) {
                inserted = true
                break
            }
            if (CompTyByNames(value, sorted[idx])) {
                sorted.add(value, at: idx)
                inserted = true
                break
            }
            idx++
        }
        if (!inserted) {
            sorted.add(value)
        }
    }
    return typeArgsString(sorted, delimiter)
}

@OverflowWrapping
private func hashCombine(seed: Int64, value: Int64): Int64 {
    return seed * 1315423911 + value + 0x9e3779b9
}

private func boolHash(value: Bool): Int64 {
    return if (value) { 1 } else { 0 }
}

private func genericLowerBound(ty: Ty): Option<Ty> {
    if (let Some(gen) <- (ty as GenericsTy)) {
        return gen.lowerBound
    }
    return None
}

private func hasCoreDecl(decl: Decl, name: String): Bool {
    return decl.fullPackageName == CORE_PACKAGE_NAME && decl.identifier == name
}

private func hasCoreClassDecl(decl: Option<ClassDecl>, name: String): Bool {
    if (let Some(value) <- decl) {
        return hasCoreDecl(value, name)
    }
    return false
}

private func hasCoreInterfaceDecl(decl: Option<InterfaceDecl>, name: String): Bool {
    if (let Some(value) <- decl) {
        return hasCoreDecl(value, name)
    }
    return false
}

private func hasCoreStructDecl(decl: Option<StructDecl>, name: String): Bool {
    if (let Some(value) <- decl) {
        return hasCoreDecl(value, name)
    }
    return false
}

private func hasCoreEnumDecl(decl: Option<EnumDecl>, name: String): Bool {
    if (let Some(value) <- decl) {
        return hasCoreDecl(value, name)
    }
    return false
}

private func anyChildTypeMatches(ty: Ty, pred: (Ty) -> Bool): Bool {
    if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
        for (child in intersectionTy.tys) {
            if (pred(child)) {
                return true
            }
        }
        return false
    }
    if (let Some(unionTy) <- (ty as UnionTy)) {
        for (child in unionTy.tys) {
            if (pred(child)) {
                return true
            }
        }
        return false
    }
    for (child in ty.typeArgs) {
        if (pred(child)) {
            return true
        }
    }
    return false
}

private func sameGenericArg(left: Ty, right: Ty): Bool {
    return Ptr<Ty>(left) == Ptr<Ty>(right)
}

private func containsGenericArg(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (sameGenericArg(value, ty)) {
            return true
        }
    }
    return false
}

private func containsGenericCandidate(values: ArrayList<GenericsTy>, ty: GenericsTy): Bool {
    for (value in values) {
        if (sameGenericArg(value, ty)) {
            return true
        }
    }
    return false
}

private func collectGenericTyArgs(ty: Ty, out: ArrayList<Ty>): Unit {
    if (ty.IsGeneric()) {
        if (!containsGenericArg(out, ty)) {
            out.add(ty)
        }
        return
    }
    for (arg in ty.typeArgs) {
        if (arg.HasGeneric()) {
            collectGenericTyArgs(arg, out)
        }
    }
}

private func collectCandidateGenericTyArgs(
    ty: Ty,
    candidates: ArrayList<GenericsTy>,
    out: ArrayList<GenericsTy>
): Unit {
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        if (containsGenericCandidate(candidates, genericTy) && !containsGenericCandidate(out, genericTy)) {
            out.add(genericTy)
        }
        return
    }
    for (arg in ty.typeArgs) {
        if (arg.HasGeneric()) {
            collectCandidateGenericTyArgs(arg, candidates, out)
        }
    }
}

private func HashNominalTy(name: String, typeArgs: ArrayList<Ty>, declHash: Int64): Int64 {
    var out: Int64 = 0
    out = hashCombine(out, name.hashCode())
    for (typeArg in typeArgs) {
        out = hashCombine(out, Ptr<Ty>(typeArg).hashCode())
    }
    out = hashCombine(out, declHash)
    return out
}

public open class Ty <: Identifiable & Hashable & Equatable<Ty> {
    private static let nextObjectId = AtomicInt64(1)
    private static let initialTy: Ty = InitialTy()

    private let objectIdValue: Int64
    public prop objectId: Int64 {
        get() { objectIdValue }
    }
    public let kind: TypeKind
    public var name: String = ""
    public let typeArgs: ArrayList<Ty> = ArrayList<Ty>()
    public var mangleAdapterId: Int64 = -1
    protected var invalid: Bool = false
    protected var generic: Bool = false

    public init(kind: TypeKind) {
        objectIdValue = nextObjectId.fetchAdd(1)
        this.kind = kind
    }

    public open func IsCFunc(): Bool {
        return false
    }

    public func IsInteger(): Bool {
        return IsSignedInteger() || IsUnsignedInteger() || kind == TypeKind.TYPE_IDEAL_INT
    }

    public func IsIntegerSubType(): Bool {
        if (IsInteger()) {
            return true
        }
        if (let Some(lowerBound) <- genericLowerBound(this)) {
            return lowerBound.IsInteger()
        }
        return false
    }

    public func IsSignedInteger(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_INT8, TypeKind.TYPE_INT_NATIVE)
    }

    public func IsUnsignedInteger(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_UINT8, TypeKind.TYPE_UINT_NATIVE)
    }

    public func IsFloating(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_FLOAT16, TypeKind.TYPE_FLOAT64) ||
            kind == TypeKind.TYPE_IDEAL_FLOAT
    }

    public func IsFloatingSubType(): Bool {
        if (IsFloating()) {
            return true
        }
        if (let Some(lowerBound) <- genericLowerBound(this)) {
            return lowerBound.IsFloating()
        }
        return false
    }

    public func IsBoolean(): Bool {
        return kind == TypeKind.TYPE_BOOLEAN
    }

    public func IsBooleanSubType(): Bool {
        if (IsBoolean()) {
            return true
        }
        if (let Some(lowerBound) <- genericLowerBound(this)) {
            return lowerBound.IsBoolean()
        }
        return false
    }

    public func IsRune(): Bool {
        return kind == TypeKind.TYPE_RUNE
    }

    public func IsIdeal(): Bool {
        return kind == TypeKind.TYPE_IDEAL_INT || kind == TypeKind.TYPE_IDEAL_FLOAT
    }

    public func IsInvalid(): Bool {
        return kind == TypeKind.TYPE_INVALID || kind == TypeKind.TYPE_INITIAL
    }

    public func IsUnit(): Bool {
        return kind == TypeKind.TYPE_UNIT
    }

    public func IsUnitOrNothing(): Bool {
        return kind == TypeKind.TYPE_UNIT || kind == TypeKind.TYPE_NOTHING
    }

    public func IsQuest(): Bool {
        return kind == TypeKind.TYPE_QUEST
    }

    public func IsPrimitive(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_UNIT, TypeKind.TYPE_BOOLEAN)
    }

    public func IsPrimitiveSubType(): Bool {
        if (IsPrimitive()) {
            return true
        }
        if (let Some(lowerBound) <- genericLowerBound(this)) {
            return lowerBound.IsPrimitive()
        }
        return false
    }

    public func IsExtendable(): Bool {
        if (let Some(aliasTy) <- (this as TypeAliasTy)) {
            if (let Some(aliasDecl) <- aliasTy.declPtr) {
                if (aliasDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    return false
                }
                if (let Some(typeNode) <- aliasDecl.typeNode) {
                    if (let Some(aliasTargetTy) <- typeNode.GetTy()) {
                        return aliasTargetTy.IsExtendable()
                    }
                }
            }
            return false
        }
        return kind == TypeKind.TYPE_CLASS || kind == TypeKind.TYPE_ENUM || kind == TypeKind.TYPE_STRUCT ||
            IsArray() || IsPointer() || IsPrimitive() || IsCString()
    }

    public func IsNumeric(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_INT8, TypeKind.TYPE_IDEAL_FLOAT)
    }

    public func IsNative(): Bool {
        return kind == TypeKind.TYPE_INT_NATIVE || kind == TypeKind.TYPE_UINT_NATIVE
    }

    public func IsBuiltin(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_UNIT, TypeKind.TYPE_BOOLEAN) || kind == TypeKind.TYPE_ARRAY ||
            kind == TypeKind.TYPE_POINTER || kind == TypeKind.TYPE_CSTRING || kind == TypeKind.TYPE_VARRAY
    }

    public func IsImmutableType(): Bool {
        return TypeKindInRange(kind, TypeKind.TYPE_UNIT, TypeKind.TYPE_FUNC) || IsString() || IsRange()
    }

    public func IsGeneric(): Bool {
        return kind == TypeKind.TYPE_GENERICS
    }

    public func IsPlaceholder(): Bool {
        if (let Some(gen) <- (this as GenericsTy)) {
            return gen.isPlaceholder
        }
        return false
    }

    public func IsStruct(): Bool {
        return kind == TypeKind.TYPE_STRUCT
    }

    public func IsEnum(): Bool {
        return kind == TypeKind.TYPE_ENUM
    }

    public func IsCoreOptionType(): Bool {
        if (let Some(enumTy) <- (this as EnumTy)) {
            if (hasCoreEnumDecl(enumTy.declPtr, STD_LIB_OPTION) && enumTy.typeArgs.size == 1) {
                return true
            }
        }
        return false
    }

    public func IsClass(): Bool {
        return kind == TypeKind.TYPE_CLASS
    }

    public func IsInterface(): Bool {
        return kind == TypeKind.TYPE_INTERFACE
    }

    public func IsIntersection(): Bool {
        return kind == TypeKind.TYPE_INTERSECTION
    }

    public func IsUnion(): Bool {
        return kind == TypeKind.TYPE_UNION
    }

    public func IsNominal(): Bool {
        return kind == TypeKind.TYPE_CLASS || kind == TypeKind.TYPE_INTERFACE || kind == TypeKind.TYPE_STRUCT ||
            kind == TypeKind.TYPE_ENUM
    }

    public func IsArray(): Bool {
        return kind == TypeKind.TYPE_ARRAY
    }

    public func IsStructArray(): Bool {
        if (let Some(structTy) <- (this as StructTy)) {
            if (hasCoreStructDecl(structTy.declPtr, "Array")) {
                return true
            }
        }
        return kind == TypeKind.TYPE_STRUCT && name == "Array"
    }

    public func IsPointer(): Bool {
        return kind == TypeKind.TYPE_POINTER
    }

    public func IsCString(): Bool {
        return kind == TypeKind.TYPE_CSTRING
    }

    public func IsEraseGeneric(): Bool {
        if (let Some(gen) <- (this as GenericsTy)) {
            return gen.isEraseMode
        }
        return false
    }

    public func IsClassLike(): Bool {
        return kind == TypeKind.TYPE_CLASS || kind == TypeKind.TYPE_INTERFACE
    }

    public func IsFunc(): Bool {
        return kind == TypeKind.TYPE_FUNC
    }

    public func IsTuple(): Bool {
        return kind == TypeKind.TYPE_TUPLE
    }

    public func IsClosureType(): Bool {
        if (let Some(tupleTy) <- (this as TupleTy)) {
            return tupleTy.isClosureTy
        }
        return false
    }

    public func IsObject(): Bool {
        if (let Some(classTy) <- (this as ClassTy)) {
            if (hasCoreClassDecl(classTy.declPtr, "Object")) {
                return true
            }
        }
        return kind == TypeKind.TYPE_CLASS && name == "Object"
    }

    public func IsAny(): Bool {
        if (let Some(interfaceTy) <- (this as InterfaceTy)) {
            if (hasCoreInterfaceDecl(interfaceTy.declPtr, "Any")) {
                return true
            }
        }
        return kind == TypeKind.TYPE_ANY || (kind == TypeKind.TYPE_INTERFACE && name == "Any")
    }

    public func IsCType(): Bool {
        if (let Some(interfaceTy) <- (this as InterfaceTy)) {
            if (hasCoreInterfaceDecl(interfaceTy.declPtr, CTYPE_NAME)) {
                return true
            }
        }
        return kind == TypeKind.TYPE_INTERFACE && name == CTYPE_NAME
    }

    public func IsNothing(): Bool {
        return kind == TypeKind.TYPE_NOTHING
    }

    public func IsString(): Bool {
        if (let Some(structTy) <- (this as StructTy)) {
            if (hasCoreStructDecl(structTy.declPtr, "String")) {
                return true
            }
        }
        return kind == TypeKind.TYPE_STRUCT && name == "String"
    }

    public func IsRange(): Bool {
        if (let Some(structTy) <- (this as StructTy)) {
            if (hasCoreStructDecl(structTy.declPtr, "Range") && typeArgs.size == 1) {
                return true
            }
        }
        return kind == TypeKind.TYPE_STRUCT && name == "Range" && typeArgs.size == 1
    }

    public func Contains(ty: Ty): Bool {
        if (refEq(this, ty)) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.Contains(ty) })
    }

    public func HasInvalidTy(): Bool {
        return invalid
    }

    public func HasIdealTy(): Bool {
        if (IsIdeal()) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.HasIdealTy() })
    }

    public func HasQuestTy(): Bool {
        if (IsQuest()) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.HasQuestTy() })
    }

    public func HasGeneric(): Bool {
        return generic
    }

    public func HasIntersectionTy(): Bool {
        if (IsIntersection()) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.HasIntersectionTy() })
    }

    public func HasPlaceholder(): Bool {
        if (IsPlaceholder()) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.HasPlaceholder() })
    }

    public func HasAliasTy(): Bool {
        if (kind == TypeKind.TYPE) {
            return true
        }
        return anyChildTypeMatches(this, { child: Ty => child.HasAliasTy() })
    }

    public func IsTyArgsSingleton(): Bool {
        return typeArgs.size == 1
    }

    public func GetGenericTyArgs(): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        collectGenericTyArgs(this, out)
        return out
    }

    public func GetGenericTyArgs(candidates: ArrayList<GenericsTy>): ArrayList<GenericsTy> {
        let out = ArrayList<GenericsTy>()
        collectCandidateGenericTyArgs(this, candidates, out)
        return out
    }

    public open func String(): String {
        return TypeKindName(kind)
    }

    public func PrintTypeArgs(): String {
        if (typeArgs.isEmpty()) {
            return ""
        }
        return "<" + typeArgsString(typeArgs, ", ") + ">"
    }

    public open func Hash(): Int64 {
        return Ptr<Ty>(this).hashCode()
    }

    public open operator func ==(right: Ty): Bool {
        return refEq(this, right)
    }

    @OverflowWrapping
    public func hashCode(): Int64 {
        var value = TypeKindIndex(kind) * 131 + name.hashCode()
        for (arg in typeArgs) {
            value = value * 131 + arg.name.hashCode()
        }
        return value
    }

    public static func KindName(kind: TypeKind): String {
        return TypeKindName(kind)
    }

    public static func ToString(ty: Option<Ty>): String {
        if (let Some(value) <- ty) {
            return value.String()
        }
        return "Invalid"
    }

    public static func GetTypesToStr(tys: ArrayList<Ty>, delimiter: String): String {
        return typeArgsString(tys, delimiter)
    }

    public static func GetTypesToStableStr(tys: ArrayList<Ty>, delimiter: String): String {
        return stableTypeArgsString(tys, delimiter)
    }

    public static func IsTyCorrect(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return !value.HasInvalidTy()
        }
        return false
    }

    public static func IsTyCorrect(ty: Ty): Bool {
        return !ty.HasInvalidTy()
    }

    public static func GetPrimitiveUpperBound(ty: Ty): Ty {
        if (let Some(genTy) <- (ty as GenericsTy)) {
            if (!genTy.isPlaceholder) {
                if (let Some(lower) <- genTy.lowerBound) {
                    return lower
                }
            }
        }
        return ty
    }

    public static func GetPrimitiveUpperBound(ty: Option<Ty>): Option<Ty> {
        if (let Some(value) <- ty) {
            return Ty.GetPrimitiveUpperBound(value)
        }
        return None
    }

    public static func IsPrimitiveCType(ty: Ty): Bool {
        return ty.kind == TypeKind.TYPE_UNIT || ty.kind == TypeKind.TYPE_BOOLEAN ||
            ty.kind == TypeKind.TYPE_INT8 || ty.kind == TypeKind.TYPE_UINT8 ||
            ty.kind == TypeKind.TYPE_INT16 || ty.kind == TypeKind.TYPE_UINT16 ||
            ty.kind == TypeKind.TYPE_INT32 || ty.kind == TypeKind.TYPE_UINT32 ||
            ty.kind == TypeKind.TYPE_INT64 || ty.kind == TypeKind.TYPE_UINT64 ||
            ty.kind == TypeKind.TYPE_INT_NATIVE || ty.kind == TypeKind.TYPE_UINT_NATIVE ||
            ty.kind == TypeKind.TYPE_FLOAT32 || ty.kind == TypeKind.TYPE_FLOAT64
    }

    public static func IsCStructType(ty: Ty): Bool {
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return decl.TestAttr(Attribute.C)
            }
        }
        return false
    }

    public static func IsMetCType(ty: Ty): Bool {
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            if (!varrayTy.typeArgs.isEmpty() && Ty.IsTyCorrect(varrayTy.typeArgs[0])) {
                return Ty.IsMetCType(varrayTy.typeArgs[0])
            }
            return false
        }
        let isCType = Ty.IsPrimitiveCType(ty) || ty.IsPointer() || ty.IsCString() ||
            ty.IsCFunc() || Ty.IsCStructType(ty)
        return isCType || ty.kind == TypeKind.TYPE_QUEST
    }

    public static func IsCTypeBasePointer(ty: Ty): Bool {
        return ty.IsPointer() || ty.IsCString() || ty.IsCFunc()
    }

    public static func IsCTypeConstraint(ty: Ty): Bool {
        if (Ty.IsMetCType(ty) && !Ty.IsPrimitiveCType(ty)) {
            if (let Some(structTy) <- (ty as StructTy)) {
                return structTy.name != "String"
            }
        }
        return false
    }

    public static func IsTyArgsSizeEqual(ty1: Ty, ty2: Ty): Bool {
        return ty1.typeArgs.size == ty2.typeArgs.size
    }

    public static func GetDeclOfTy(ty: Option<Ty>): Option<Decl> {
        if (let Some(value) <- ty) {
            if (let Some(classTy) <- (value as ClassTy)) {
                if (let Some(decl) <- classTy.decl) {
                    return decl
                }
                return None
            }
            if (let Some(interfaceTy) <- (value as InterfaceTy)) {
                if (let Some(decl) <- interfaceTy.decl) {
                    return decl
                }
                return None
            }
            if (let Some(structTy) <- (value as StructTy)) {
                if (let Some(decl) <- structTy.decl) {
                    return decl
                }
                return None
            }
            if (let Some(enumTy) <- (value as EnumTy)) {
                if (let Some(decl) <- enumTy.decl) {
                    return decl
                }
                return None
            }
            if (let Some(aliasTy) <- (value as TypeAliasTy)) {
                if (let Some(decl) <- aliasTy.declPtr) {
                    return decl
                }
                return None
            }
        }
        return None
    }

    public static func GetDeclPtrOfTy(ty: Option<Ty>): Option<Decl> {
        var decl: Option<Decl> = None
        if (let Some(value) <- ty) {
            if (let Some(classTy) <- (value as ClassTy)) {
                decl = classTy.declPtr
            } else if (let Some(interfaceTy) <- (value as InterfaceTy)) {
                decl = interfaceTy.declPtr
            } else if (let Some(structTy) <- (value as StructTy)) {
                decl = structTy.declPtr
            } else if (let Some(enumTy) <- (value as EnumTy)) {
                decl = enumTy.declPtr
            } else if (let Some(aliasTy) <- (value as TypeAliasTy)) {
                decl = aliasTy.declPtr
            }
        }
        if (let Some(genericDecl) <- decl) {
            if (let Some(specificDecl) <- genericDecl.specificImplementation) {
                decl = Some(specificDecl)
            }
        }
        return decl
    }

    public static func GetInheritableDeclPtrOfTy(ty: Option<Ty>): Option<InheritableDecl> {
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(ty)) {
            return decl as InheritableDecl
        }
        return None
    }

    public static func GetGenericTyOfInsTy(ty: Ty): Option<Ty> {
        if (!Ty.IsTyCorrect(ty)) {
            return None
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(genericTy) <- classTy.GetGenericTy()) {
                return genericTy
            }
            return None
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(genericTy) <- interfaceTy.GetGenericTy()) {
                return genericTy
            }
            return None
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(genericTy) <- structTy.GetGenericTy()) {
                return genericTy
            }
            return None
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(genericTy) <- enumTy.GetGenericTy()) {
                return genericTy
            }
            return None
        }
        return None
    }

    public static func IsInitialTy(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return value.kind == TypeKind.TYPE_INITIAL
        }
        return true
    }

    public static func AreTysCorrect(tys: ArrayList<Ty>): Bool {
        for (ty in tys) {
            if (ty.HasInvalidTy()) {
                return false
            }
        }
        return true
    }

    public static func ExistGeneric(tys: ArrayList<Ty>): Bool {
        return anyGeneric(tys)
    }

    public static func GetInitialTy(): Ty {
        return initialTy
    }
}

public class InitialTy <: Ty {
    public init() {
        super(TypeKind.TYPE_INITIAL)
        invalid = true
    }
}

public class InvalidTy <: Ty {
    public init() {
        super(TypeKind.TYPE_INVALID)
        invalid = true
    }
}

public class QuestTy <: Ty {
    public init() {
        super(TypeKind.TYPE_QUEST)
    }
}

public open class PrimitiveTy <: Ty {
    public var bitness: UInt64 = 64

    public init(kind: TypeKind) {
        super(kind)
        name = TypeKindName(kind)
    }
}

public class NothingTy <: PrimitiveTy {
    public init() {
        super(TypeKind.TYPE_NOTHING)
    }
}

public class AnyTy <: Ty {
    public init() {
        super(TypeKind.TYPE_ANY)
        name = "Any"
    }

    public override func String(): String {
        return "Any"
    }
}

public class ArrayTy <: Ty {
    public var dims: UInt64 = 0

    public init(elemTy: Ty, dims: UInt64) {
        super(TypeKind.TYPE_ARRAY)
        name = "RawArray"
        this.dims = dims
        typeArgs.add(elemTy)
        invalid = elemTy.HasInvalidTy()
        generic = elemTy.HasGeneric()
    }

    public override func String(): String {
        var out = typeArgs[0].String()
        for (_ in 0..dims) {
            out = "Array<" + out + ">"
        }
        return out
    }

    public override func Hash(): Int64 {
        var out: Int64 = 0
        if (!typeArgs.isEmpty()) {
            out = hashCombine(out, Ptr<Ty>(typeArgs[0]).hashCode())
        }
        out = hashCombine(out, Int64(dims))
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_ARRAY))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightArray) <- (right as ArrayTy)) {
            if (dims != rightArray.dims || typeArgs.size != rightArray.typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightArray.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }
}

public class VArrayTy <: Ty {
    public var size: Int64 = 0

    public init(elemTy: Ty, size: Int64) {
        super(TypeKind.TYPE_VARRAY)
        name = "VArray"
        this.size = size
        typeArgs.add(elemTy)
        invalid = elemTy.HasInvalidTy()
        generic = elemTy.HasGeneric()
    }

    public override func String(): String {
        return "VArray<${typeArgs[0].String()}, $${size}>"
    }

    public override func Hash(): Int64 {
        var out: Int64 = 0
        if (!typeArgs.isEmpty()) {
            out = hashCombine(out, Ptr<Ty>(typeArgs[0]).hashCode())
        }
        out = hashCombine(out, size)
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_VARRAY))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightVArray) <- (right as VArrayTy)) {
            if (size != rightVArray.size || typeArgs.size != rightVArray.typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightVArray.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }
}

public class PointerTy <: Ty {
    public init(elemTy: Ty) {
        super(TypeKind.TYPE_POINTER)
        name = "CPointer"
        typeArgs.add(elemTy)
        invalid = elemTy.HasInvalidTy()
        generic = elemTy.HasGeneric()
    }

    public override func String(): String {
        return "CPointer<${typeArgs[0].String()}>"
    }

    public override func Hash(): Int64 {
        var out: Int64 = 0
        if (!typeArgs.isEmpty()) {
            out = hashCombine(out, Ptr<Ty>(typeArgs[0]).hashCode())
        }
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_POINTER))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightPointer) <- (right as PointerTy)) {
            if (typeArgs.size != rightPointer.typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightPointer.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }
}

public class CStringTy <: Ty {
    public init() {
        super(TypeKind.TYPE_CSTRING)
        name = "CString"
    }

    public override func String(): String {
        return "CString"
    }
}

public class TupleTy <: Ty {
    public var isClosureTy: Bool = false

    public init(elemTys: Array<Ty>, isClosureTy!: Bool = false) {
        super(TypeKind.TYPE_TUPLE)
        name = "Tuple"
        this.isClosureTy = isClosureTy
        for (elem in elemTys) {
            typeArgs.add(elem)
        }
        invalid = anyInvalid(typeArgs)
        generic = anyGeneric(typeArgs)
    }

    public override func String(): String {
        let prefix = if (isClosureTy) { "Closure<" } else { "Tuple<" }
        return prefix + typeArgsString(typeArgs, ", ") + ">"
    }

    public override func Hash(): Int64 {
        var out = hashCombine(0, boolHash(isClosureTy))
        for (typeArg in typeArgs) {
            out = hashCombine(out, Ptr<Ty>(typeArg).hashCode())
        }
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_TUPLE))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightTuple) <- (right as TupleTy)) {
            if (isClosureTy != rightTuple.isClosureTy || typeArgs.size != rightTuple.typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightTuple.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }
}

public class FuncTyConfig {
    public var isC: Bool = false
    public var isClosureTy: Bool = false
    public var hasVariableLenArg: Bool = false
    public var noCast: Bool = false

    public init() {}
}

public class FuncTy <: Ty {
    public let paramTys: ArrayList<Ty> = ArrayList<Ty>()
    public var retTy: Ty
    public var isC: Bool = false
    public var isClosureTy: Bool = false
    public var hasVariableLenArg: Bool = false
    public var noCast: Bool = false

    public init(paramVector: Array<Ty>, retType: Ty, cfg!: FuncTyConfig = FuncTyConfig()) {
        super(TypeKind.TYPE_FUNC)
        retTy = retType
        name = "Function"
        isC = cfg.isC
        isClosureTy = cfg.isClosureTy
        hasVariableLenArg = cfg.hasVariableLenArg
        noCast = cfg.noCast
        for (param in paramVector) {
            paramTys.add(param)
            typeArgs.add(param)
        }
        typeArgs.add(retType)
        invalid = anyInvalid(paramTys) || retType.HasInvalidTy() || (!isC && hasVariableLenArg)
        generic = anyGeneric(paramTys) || retType.HasGeneric()
    }

    public override func IsCFunc(): Bool {
        return isC
    }

    public override func String(): String {
        let params = typeArgsString(paramTys, ", ")
        let out = "(${params}) -> ${retTy.String()}"
        return if (isC) { "CFunc<" + out + ">" } else { out }
    }

    public override func Hash(): Int64 {
        var out = hashCombine(0, Ptr<Ty>(retTy).hashCode())
        for (paramTy in paramTys) {
            out = hashCombine(out, Ptr<Ty>(paramTy).hashCode())
        }
        out = hashCombine(out, boolHash(isClosureTy))
        out = hashCombine(out, boolHash(isC))
        out = hashCombine(out, boolHash(hasVariableLenArg))
        out = hashCombine(out, boolHash(noCast))
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_FUNC))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightFunc) <- (right as FuncTy)) {
            if (isC != rightFunc.isC || noCast != rightFunc.noCast ||
                hasVariableLenArg != rightFunc.hasVariableLenArg || isClosureTy != rightFunc.isClosureTy ||
                !refEq(retTy, rightFunc.retTy) || paramTys.size != rightFunc.paramTys.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < paramTys.size) {
                if (!refEq(paramTys[idx], rightFunc.paramTys[idx])) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }
}

public class UnionTy <: Ty {
    public let tys: ArrayList<Ty> = ArrayList<Ty>()

    public init(values: Array<Ty>) {
        super(TypeKind.TYPE_UNION)
        for (value in values) {
            tys.add(value)
        }
    }

    public override func String(): String {
        return stableTypeArgsString(tys, " | ")
    }

    public override func Hash(): Int64 {
        let orderedTys = ArrayList<Ptr<Ty>>()
        for (ty in tys) {
            orderedTys.add(Ptr<Ty>(ty))
        }
        sort(orderedTys, by: { left: Ptr<Ty>, right: Ptr<Ty> => left.compare(right) }, stable: true)
        var out: Int64 = 0
        for (ty in orderedTys) {
            out = hashCombine(out, ty.hashCode())
        }
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_UNION))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightUnion) <- (right as UnionTy)) {
            if (tys.size != rightUnion.tys.size) {
                return false
            }
            for (leftValue in tys) {
                var found = false
                for (rightValue in rightUnion.tys) {
                    if (refEq(leftValue, rightValue)) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    return false
                }
            }
            return true
        }
        return false
    }
}

public class IntersectionTy <: Ty {
    public let tys: ArrayList<Ty> = ArrayList<Ty>()

    public init(values: Array<Ty>) {
        super(TypeKind.TYPE_INTERSECTION)
        for (value in values) {
            tys.add(value)
        }
    }

    public override func String(): String {
        return stableTypeArgsString(tys, " & ")
    }

    public override func Hash(): Int64 {
        let orderedTys = ArrayList<Ptr<Ty>>()
        for (ty in tys) {
            orderedTys.add(Ptr<Ty>(ty))
        }
        sort(orderedTys, by: { left: Ptr<Ty>, right: Ptr<Ty> => left.compare(right) }, stable: true)
        var out: Int64 = 0
        for (ty in orderedTys) {
            out = hashCombine(out, ty.hashCode())
        }
        return hashCombine(out, TypeKindIndex(TypeKind.TYPE_INTERSECTION))
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightIntersection) <- (right as IntersectionTy)) {
            if (tys.size != rightIntersection.tys.size) {
                return false
            }
            for (leftValue in tys) {
                var found = false
                for (rightValue in rightIntersection.tys) {
                    if (refEq(leftValue, rightValue)) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    return false
                }
            }
            return true
        }
        return false
    }
}

public open class ClassLikeTy <: Ty {
    public var commonDecl: Option<ClassLikeDecl> = None
    public let directSubtypes: ArrayList<Ty> = ArrayList<Ty>()

    public init(kind: TypeKind, decl: ClassLikeDecl) {
        super(kind)
        commonDecl = decl
    }

    public open func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        return ArrayList<InterfaceTy>()
    }
}

public class InterfaceTy <: ClassLikeTy {
    public var declPtr: Option<InterfaceDecl> = None
    public var decl: Option<InterfaceDecl> = None

    public init(name: String, decl: InterfaceDecl, typeArgs: Array<Ty>) {
        super(TypeKind.TYPE_INTERFACE, decl)
        this.name = name
        this.declPtr = decl
        this.decl = decl
        for (arg in typeArgs) {
            this.typeArgs.add(arg)
        }
        invalid = anyInvalid(this.typeArgs)
        generic = anyGeneric(this.typeArgs)
    }

    public override func String(): String {
        return "Interface-" + name + PrintTypeArgs()
    }

    public override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        return HashNominalTy(name, typeArgs, declHash)
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightInterface) <- (right as InterfaceTy)) {
            if (typeArgs.size != rightInterface.typeArgs.size || name != rightInterface.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightInterface.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightInterface.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightInterface.declPtr.isNone()
        }
        return false
    }

    public func GetGenericTy(): Option<InterfaceTy> {
        if (let Some(interfaceDecl) <- declPtr) {
            if (let Some(_) <- interfaceDecl.generic) {
                if (let Some(ty) <- interfaceDecl.GetTy()) {
                    return ty as InterfaceTy
                }
            }
        }
        return None
    }

    public override func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        if (let Some(interfaceDecl) <- decl) {
            return interfaceDecl.GetSuperInterfaceTys()
        }
        return ArrayList<InterfaceTy>()
    }
}

public open class ClassTy <: ClassLikeTy {
    public var declPtr: Option<ClassDecl> = None
    public var decl: Option<ClassDecl> = None

    public init(name: String, decl: ClassDecl, typeArgs: Array<Ty>) {
        super(TypeKind.TYPE_CLASS, decl)
        this.name = name
        this.declPtr = decl
        this.decl = decl
        for (arg in typeArgs) {
            this.typeArgs.add(arg)
        }
        invalid = anyInvalid(this.typeArgs)
        generic = anyGeneric(this.typeArgs)
    }

    public func GetSuperClassTy(): Option<ClassTy> {
        if (let Some(classDecl) <- decl) {
            for (typeNode in classDecl.inheritedTypes) {
                if (let Some(ty) <- typeNode.GetTy()) {
                    if (let Some(classTy) <- (ty as ClassTy)) {
                        return classTy
                    }
                }
            }
        }
        return None
    }

    public func GetGenericTy(): Option<ClassTy> {
        if (let Some(classDecl) <- declPtr) {
            if (let Some(_) <- classDecl.generic) {
                if (let Some(ty) <- classDecl.GetTy()) {
                    return ty as ClassTy
                }
            }
        }
        return None
    }

    public override func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        if (let Some(classDecl) <- decl) {
            return classDecl.GetSuperInterfaceTys()
        }
        return ArrayList<InterfaceTy>()
    }

    public open override func String(): String {
        return "Class-" + name + PrintTypeArgs()
    }

    public open override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        let base = HashNominalTy(name, typeArgs, declHash)
        return hashCombine(base, 0)
    }

    public open override operator func ==(right: Ty): Bool {
        if ((right as ClassThisTy).isSome()) {
            return false
        }
        if (let Some(rightClass) <- (right as ClassTy)) {
            if (typeArgs.size != rightClass.typeArgs.size || name != rightClass.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightClass.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightClass.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightClass.declPtr.isNone()
        }
        return false
    }
}

public class ClassThisTy <: ClassTy {
    public init(name: String, decl: ClassDecl, typeArgs: Array<Ty>) {
        super(name, decl, typeArgs)
    }

    public override func String(): String {
        return "This"
    }

    public override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        let base = HashNominalTy(name, typeArgs, declHash)
        return hashCombine(base, 1)
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightThis) <- (right as ClassThisTy)) {
            if (typeArgs.size != rightThis.typeArgs.size || name != rightThis.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightThis.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightThis.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightThis.declPtr.isNone()
        }
        return false
    }
}

public class TypeAliasTy <: Ty {
    public var declPtr: Option<TypeAliasDecl> = None

    public init(name: String, decl: TypeAliasDecl, typeArgs: Array<Ty>) {
        super(TypeKind.TYPE)
        this.name = name
        declPtr = decl
        for (arg in typeArgs) {
            this.typeArgs.add(arg)
        }
        invalid = anyInvalid(this.typeArgs)
        generic = anyGeneric(this.typeArgs)
    }

    public override func String(): String {
        return "TypeAlias-" + name + PrintTypeArgs()
    }

    public override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        return HashNominalTy(name, typeArgs, declHash)
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightAlias) <- (right as TypeAliasTy)) {
            if (typeArgs.size != rightAlias.typeArgs.size || name != rightAlias.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightAlias.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightAlias.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightAlias.declPtr.isNone()
        }
        return false
    }
}

public class GenericsTy <: Ty {
    public var decl: Option<GenericParamDecl> = None
    public var isEraseMode: Bool = false
    public let upperBounds: ArrayList<Ty> = ArrayList<Ty>()
    public var isUpperBoundLegal: Bool = true
    public var lowerBound: Option<Ty> = None
    public var isAliasParam: Bool = false
    public var isPlaceholder: Bool = false

    public init(name: String, decl: GenericParamDecl) {
        super(TypeKind.TYPE_GENERICS)
        this.name = name
        this.decl = decl
        isEraseMode = IsJavaGeneric(decl)
        generic = true
    }

    public override func String(): String {
        return "Generics-" + name
    }

    public override func Hash(): Int64 {
        var out = 0
        if (let Some(genericDecl) <- decl) {
            out = hashCombine(out, genericDecl.hashCode())
        }
        return out
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightGeneric) <- (right as GenericsTy)) {
            if (let Some(leftDecl) <- decl) {
                if (let Some(rightDecl) <- rightGeneric.decl) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightGeneric.decl.isNone()
        }
        return false
    }
}

public open class EnumTy <: Ty {
    public var declPtr: Option<EnumDecl> = None
    public var decl: Option<EnumDecl> = None
    public let fieldMap: HashMap<String, Int64> = HashMap<String, Int64>()
    public var hasCorrespondRefEnumTy: Bool = false

    public init(name: String, decl: EnumDecl, typeArgs: Array<Ty>) {
        super(TypeKind.TYPE_ENUM)
        this.name = name
        declPtr = decl
        this.decl = decl
        for (arg in typeArgs) {
            this.typeArgs.add(arg)
        }
        invalid = anyInvalid(this.typeArgs)
        generic = anyGeneric(this.typeArgs)
    }

    public func IsNonExhaustive(): Bool {
        if (let Some(enumDecl) <- decl) {
            return enumDecl.hasEllipsis
        }
        return false
    }

    public func GetGenericTy(): Option<EnumTy> {
        if (let Some(enumDecl) <- declPtr) {
            if (let Some(_) <- enumDecl.generic) {
                if (let Some(ty) <- enumDecl.GetTy()) {
                    return ty as EnumTy
                }
            }
        }
        return None
    }

    public func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        if (let Some(enumDecl) <- decl) {
            return enumDecl.GetSuperInterfaceTys()
        }
        return ArrayList<InterfaceTy>()
    }

    public open override func String(): String {
        return "Enum-" + name + PrintTypeArgs()
    }

    public open override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        let base = HashNominalTy(name, typeArgs, declHash)
        return hashCombine(base, 0)
    }

    public open override operator func ==(right: Ty): Bool {
        if ((right as RefEnumTy).isSome()) {
            return false
        }
        if (let Some(rightEnum) <- (right as EnumTy)) {
            if (typeArgs.size != rightEnum.typeArgs.size || name != rightEnum.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightEnum.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightEnum.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightEnum.declPtr.isNone()
        }
        return false
    }
}

public class RefEnumTy <: EnumTy {
    public init(name: String, decl: EnumDecl, typeArgs: Array<Ty>) {
        super(name, decl, typeArgs)
        hasCorrespondRefEnumTy = true
    }

    public override func String(): String {
        return "Enum-" + name + PrintTypeArgs() + "(asRef)"
    }

    public override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        let base = HashNominalTy(name, typeArgs, declHash)
        return hashCombine(base, 1)
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightRefEnum) <- (right as RefEnumTy)) {
            if (typeArgs.size != rightRefEnum.typeArgs.size || name != rightRefEnum.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightRefEnum.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightRefEnum.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightRefEnum.declPtr.isNone()
        }
        return false
    }
}

public class StructTy <: Ty & Equatable<StructTy> {
    public var declPtr: Option<StructDecl> = None
    public var decl: Option<StructDecl> = None

    public init(name: String, decl: StructDecl, typeArgs: Array<Ty>) {
        super(TypeKind.TYPE_STRUCT)
        this.name = name
        declPtr = decl
        this.decl = decl
        for (arg in typeArgs) {
            this.typeArgs.add(arg)
        }
        invalid = anyInvalid(this.typeArgs)
        generic = anyGeneric(this.typeArgs)
    }

    public override func String(): String {
        return "Struct-" + name + PrintTypeArgs()
    }

    public override func Hash(): Int64 {
        var declHash: Int64 = 0
        if (let Some(value) <- declPtr) {
            declHash = value.hashCode()
        }
        return HashNominalTy(name, typeArgs, declHash)
    }

    public override operator func ==(right: Ty): Bool {
        if (let Some(rightStruct) <- (right as StructTy)) {
            if (typeArgs.size != rightStruct.typeArgs.size || name != rightStruct.name) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!refEq(typeArgs[idx], rightStruct.typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let Some(leftDecl) <- declPtr) {
                if (let Some(rightDecl) <- rightStruct.declPtr) {
                    return refEq(leftDecl, rightDecl)
                }
                return false
            }
            return rightStruct.declPtr.isNone()
        }
        return false
    }

    public operator func ==(right: StructTy): Bool {
        return (this as Ty) == (right as Ty)
    }

    public func GetGenericTy(): Option<StructTy> {
        if (let Some(structDecl) <- declPtr) {
            if (let Some(_) <- structDecl.generic) {
                if (let Some(ty) <- structDecl.GetTy()) {
                    return ty as StructTy
                }
            }
        }
        return None
    }

    public func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        if (let Some(structDecl) <- decl) {
            return structDecl.GetSuperInterfaceTys()
        }
        return ArrayList<InterfaceTy>()
    }
}

public func CompTyByNames(ty1: Option<Ty>, ty2: Option<Ty>): Bool {
    if (let Some(left) <- ty1) {
        if (let Some(right) <- ty2) {
            let leftStr = left.String()
            let rightStr = right.String()
            return leftStr < rightStr || (leftStr == rightStr && left.Hash() < right.Hash())
        }
        return false
    }
    if (let Some(_) <- ty2) {
        return true
    }
    return false
}
