package cangjie_compiler::ast

import std.collection.*

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

private func typeArgsString(values: ArrayList<Ty>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.String())
    }
    return JoinStrings(parts, delimiter)
}

public open class Ty {
    public let kind: TypeKind
    public var name: String = ""
    public let typeArgs: ArrayList<Ty> = ArrayList<Ty>()
    protected var invalid: Bool = false
    protected var generic: Bool = false

    public init(kind: TypeKind) {
        this.kind = kind
    }

    public open func IsCFunc(): Bool {
        return false
    }

    public func IsInteger(): Bool {
        return IsSignedInteger() || IsUnsignedInteger() || kind == TypeKind.TYPE_IDEAL_INT
    }

    public func IsIntegerSubType(): Bool {
        return IsInteger()
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
        return IsFloating()
    }

    public func IsBoolean(): Bool {
        return kind == TypeKind.TYPE_BOOLEAN
    }

    public func IsBooleanSubType(): Bool {
        return IsBoolean()
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
        return IsPrimitive()
    }

    public func IsExtendable(): Bool {
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
            return enumTy.name == "Option" && enumTy.typeArgs.size == 1
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
        return kind == TypeKind.TYPE_CLASS && name == "Object"
    }

    public func IsAny(): Bool {
        return kind == TypeKind.TYPE_ANY || (kind == TypeKind.TYPE_INTERFACE && name == "Any")
    }

    public func IsCType(): Bool {
        return kind == TypeKind.TYPE_INTERFACE && name == "CType"
    }

    public func IsNothing(): Bool {
        return kind == TypeKind.TYPE_NOTHING
    }

    public func IsString(): Bool {
        return kind == TypeKind.TYPE_STRUCT && name == "String"
    }

    public func IsRange(): Bool {
        return kind == TypeKind.TYPE_STRUCT && name == "Range" && typeArgs.size == 1
    }

    public func Contains(ty: Ty): Bool {
        if (this.hashCode() == ty.hashCode()) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.Contains(ty)) {
                return true
            }
        }
        return false
    }

    public func HasInvalidTy(): Bool {
        return invalid
    }

    public func HasIdealTy(): Bool {
        if (IsIdeal()) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.HasIdealTy()) {
                return true
            }
        }
        return false
    }

    public func HasQuestTy(): Bool {
        if (IsQuest()) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.HasQuestTy()) {
                return true
            }
        }
        return false
    }

    public func HasGeneric(): Bool {
        return generic
    }

    public func HasIntersectionTy(): Bool {
        if (IsIntersection()) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.HasIntersectionTy()) {
                return true
            }
        }
        return false
    }

    public func HasPlaceholder(): Bool {
        if (IsPlaceholder()) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.HasPlaceholder()) {
                return true
            }
        }
        return false
    }

    public func HasAliasTy(): Bool {
        if (kind == TypeKind.TYPE) {
            return true
        }
        for (arg in typeArgs) {
            if (arg.HasAliasTy()) {
                return true
            }
        }
        return false
    }

    public func IsTyArgsSingleton(): Bool {
        return typeArgs.size == 1
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
        return hashCode()
    }

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

    public static func IsTyCorrect(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return !value.HasInvalidTy()
        }
        return false
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
        return InitialTy()
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
    public var retTy: Ty = InvalidTy()
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
        return typeArgsString(tys, " | ")
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
        return typeArgsString(tys, " & ")
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

    public open override func String(): String {
        return "Class-" + name + PrintTypeArgs()
    }
}

public class ClassThisTy <: ClassTy {
    public init(name: String, decl: ClassDecl, typeArgs: Array<Ty>) {
        super(name, decl, typeArgs)
    }

    public override func String(): String {
        return "This"
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
        generic = true
    }

    public override func String(): String {
        return "Generics-" + name
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

    public open override func String(): String {
        return "Enum-" + name + PrintTypeArgs()
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
}

public class StructTy <: Ty {
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
}

public func CompTyByNames(ty1: Option<Ty>, ty2: Option<Ty>): Bool {
    if (let Some(left) <- ty1) {
        if (let Some(right) <- ty2) {
            let leftStr = left.String()
            let rightStr = right.String()
            return leftStr < rightStr || (leftStr == rightStr && left.hashCode() < right.hashCode())
        }
        return false
    }
    if (let Some(_) <- ty2) {
        return true
    }
    return false
}
