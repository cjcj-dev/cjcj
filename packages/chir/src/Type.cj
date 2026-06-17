package cangjie_compiler::chir

import std.collection.*
import std.sort.*

public open class Type {
    public let kind: TypeKind
    public let argTys: ArrayList<Type> = ArrayList<Type>()

    public init(kind: TypeKind) {
        this.kind = kind
    }

    public open func ToString(): String {
        return TypeKindName(kind)
    }

    public open func ToSrcCodeString(): String {
        return ToString()
    }

    public func Dump(): Unit {
        println(ToString())
    }

    public func GetTypeKind(): TypeKind {
        return kind
    }

    public func IsSameTypeKind(other: Type): Bool {
        return kind == other.kind
    }

    public func IsInteger(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)
    }

    public func IsSignedInteger(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)
    }

    public func IsUnsignedInteger(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_UINT8) && idx <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)
    }

    public func IsFloat(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_FLOAT16) && idx <= TypeKindIndex(TypeKind.TYPE_FLOAT64)
    }

    public func IsNumeric(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_FLOAT64)
    }

    public func IsInvalid(): Bool { return kind == TypeKind.TYPE_INVALID }
    public func IsRune(): Bool { return kind == TypeKind.TYPE_RUNE }
    public func IsBoolean(): Bool { return kind == TypeKind.TYPE_BOOLEAN }
    public func IsUnit(): Bool { return kind == TypeKind.TYPE_UNIT }
    public func IsNothing(): Bool { return kind == TypeKind.TYPE_NOTHING }
    public func IsTuple(): Bool { return kind == TypeKind.TYPE_TUPLE }
    public func IsFunc(): Bool { return kind == TypeKind.TYPE_FUNC }
    public func IsStruct(): Bool { return kind == TypeKind.TYPE_STRUCT }
    public func IsClass(): Bool { return kind == TypeKind.TYPE_CLASS }
    public func IsRawArray(): Bool { return kind == TypeKind.TYPE_RAWARRAY }
    public func IsVArray(): Bool { return kind == TypeKind.TYPE_VARRAY }
    public func IsEnum(): Bool { return kind == TypeKind.TYPE_ENUM }
    public func IsCPointer(): Bool { return kind == TypeKind.TYPE_CPOINTER }
    public func IsCString(): Bool { return kind == TypeKind.TYPE_CSTRING }
    public func IsGeneric(): Bool { return kind == TypeKind.TYPE_GENERIC }
    public func IsVoid(): Bool { return kind == TypeKind.TYPE_VOID }
    public func IsRef(): Bool { return kind == TypeKind.TYPE_REFTYPE }
    public func IsBox(): Bool { return kind == TypeKind.TYPE_BOXTYPE }
    public func IsThis(): Bool { return kind == TypeKind.TYPE_THIS }

    public func IsPrimitive(): Bool {
        let idx = TypeKindIndex(kind)
        return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_NOTHING)
    }

    public func IsNominal(): Bool {
        return IsClass() || IsStruct() || IsEnum()
    }

    public func IsCustomType(): Bool {
        return IsNominal()
    }

    public func IsClassOrStruct(): Bool {
        return IsClass() || IsStruct()
    }

    public func IsClassOrArray(): Bool {
        return IsClass() || IsRawArray()
    }

    public func IsClassRef(nullable!: Bool = false): Bool {
        let _ = nullable
        if (!IsRef()) {
            return false
        }
        if (let Some(refTy) <- (this as RefType)) {
            return refTy.GetBaseType().IsClass()
        }
        return false
    }

    public func IsBuiltinType(): Bool {
        let idx = TypeKindIndex(kind)
        return (idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_VOID)) ||
            (idx >= TypeKindIndex(TypeKind.TYPE_RAWARRAY) && idx <= TypeKindIndex(TypeKind.TYPE_CSTRING))
    }

    public func IsStructArray(): Bool {
        if (let Some(structTy) <- (this as StructType)) {
            let def = structTy.GetCustomTypeDef()
            return def.GetPackageName() == "std.core" && def.GetIdentifier() == "Array"
        }
        return false
    }

    public func IsValueType(): Bool {
        return IsPrimitive() || IsEnum() || IsTuple() || IsStruct() || IsVArray() || IsCPointer() ||
            IsCString() || IsFunc()
    }

    public func IsValueOrGenericType(): Bool {
        return IsValueType() || IsGeneric()
    }

    public func IsReferenceType(): Bool {
        return IsClassOrArray() || IsBox() || IsThis()
    }

    public open func IsConstant(): Bool {
        if (!IsTuple()) {
            return IsInteger() || IsFloat() || IsRune() || IsBoolean() || IsUnit() || IsString()
        }
        for (ty in argTys) {
            if (!ty.IsConstant()) {
                return false
            }
        }
        return true
    }

    public open func IsString(): Bool {
        if (let Some(structTy) <- (this as StructType)) {
            return structTy.GetCustomTypeDef().packageName == "std.core" &&
                structTy.GetCustomTypeDef().identifier == "String"
        }
        return false
    }

    public open func IsAny(): Bool {
        if (let Some(classTy) <- (this as ClassType)) {
            return classTy.GetCustomTypeDef().packageName == "std.core" &&
                classTy.GetCustomTypeDef().identifier == "Any"
        }
        return false
    }

    public open func IsCJFunc(): Bool {
        if (let Some(funcTy) <- (this as FuncType)) {
            return funcTy.IsCJFunc()
        }
        return false
    }

    public open func IsCFunc(): Bool {
        if (let Some(funcTy) <- (this as FuncType)) {
            return funcTy.IsCFunc()
        }
        return false
    }

    public func IsCType(): Bool {
        if (let Some(classTy) <- (this as ClassType)) {
            let def = classTy.GetCustomTypeDef()
            return def.GetPackageName() == "std.core" && def.GetIdentifier() == "CType"
        }
        return false
    }

    public func SatisfyCType(): Bool {
        let builtinCType = (TypeKindIndex(kind) >= TypeKindIndex(TypeKind.TYPE_INT8) &&
            TypeKindIndex(kind) <= TypeKindIndex(TypeKind.TYPE_UNIT)) || IsCPointer() || IsCString()
        if (builtinCType || IsCFunc()) {
            return true
        }
        if (let Some(structTy) <- (this as StructType)) {
            if (structTy.GetStructDef().IsCStruct()) {
                return true
            }
        }
        if (let Some(varrayTy) <- (this as VArrayType)) {
            return varrayTy.GetElementType().SatisfyCType()
        }
        return false
    }

    public func StripAllRefs(): Type {
        var current: Type = this
        while (current.IsRef()) {
            if (let Some(refTy) <- (current as RefType)) {
                current = refTy.GetBaseType()
            } else {
                return current
            }
        }
        return current
    }

    public func IsReferenceTypeWithRefDims(dims: Int64): Bool {
        return GetRefDims() == dims && StripAllRefs().IsReferenceType()
    }

    public func IsValueOrGenericTypeWithRefDims(dims: Int64): Bool {
        let strippedTy = StripAllRefs()
        return GetRefDims() == dims && (strippedTy.IsValueType() || strippedTy.IsGeneric())
    }

    public func GetRefDims(): Int64 {
        var dims: Int64 = 0
        var current: Type = this
        while (current.IsRef()) {
            dims++
            if (let Some(refTy) <- (current as RefType)) {
                current = refTy.GetBaseType()
            } else {
                return dims
            }
        }
        return dims
    }

    public func GetTypeArgs(): ArrayList<Type> {
        return CopyTypeList(argTys)
    }

    public func GetTypeArgsRef(): ArrayList<Type> {
        return argTys
    }

    public open func Hash(): Int64 {
        return ToString().hashCode()
    }

    public open func IsEqual(other: Type): Bool {
        return ToString() == other.ToString()
    }

    public func IsGenericRelated(): Bool {
        if (IsGeneric()) {
            return true
        }
        for (argTy in argTys) {
            if (argTy.IsGenericRelated()) {
                return true
            }
        }
        return false
    }
}

public open class BuiltinType <: Type {
    private let extends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()

    public init(kind: TypeKind) {
        super(kind)
    }

    public func AddExtend(extendDef: ExtendDef): Unit {
        extends.add(extendDef)
    }

    public func GetExtends(): ArrayList<ExtendDef> {
        let out = ArrayList<ExtendDef>()
        for (extendDef in extends) {
            out.add(extendDef)
        }
        return out
    }
}

public open class NumericType <: BuiltinType {
    public init(kind: TypeKind) {
        super(kind)
    }

    public func GetBitness(): UInt64 {
        return match (kind) {
            case TypeKind.TYPE_INT8 => 8u64
            case TypeKind.TYPE_UINT8 => 8u64
            case TypeKind.TYPE_INT16 => 16u64
            case TypeKind.TYPE_UINT16 => 16u64
            case TypeKind.TYPE_FLOAT16 => 16u64
            case TypeKind.TYPE_INT32 => 32u64
            case TypeKind.TYPE_UINT32 => 32u64
            case TypeKind.TYPE_FLOAT32 => 32u64
            case TypeKind.TYPE_INT64 => 64u64
            case TypeKind.TYPE_UINT64 => 64u64
            case TypeKind.TYPE_INT_NATIVE => 64u64
            case TypeKind.TYPE_UINT_NATIVE => 64u64
            case TypeKind.TYPE_FLOAT64 => 64u64
            case _ => 0u64
        }
    }
}

public class IntType <: NumericType {
    public init(kind: TypeKind) {
        super(kind)
    }

    public func IsSigned(): Bool {
        return IsSignedInteger()
    }

    public func IsIntNative(): Bool {
        return kind == TypeKind.TYPE_INT_NATIVE
    }

    public func IsUIntNative(): Bool {
        return kind == TypeKind.TYPE_UINT_NATIVE
    }
}

public class FloatType <: NumericType {
    public init(kind: TypeKind) {
        super(kind)
    }
}

public class UnitType <: BuiltinType {
    public init() { super(TypeKind.TYPE_UNIT) }
}

public class BooleanType <: BuiltinType {
    public init() { super(TypeKind.TYPE_BOOLEAN) }
}

public class RuneType <: BuiltinType {
    public init() { super(TypeKind.TYPE_RUNE) }
}

public class NothingType <: BuiltinType {
    public init() { super(TypeKind.TYPE_NOTHING) }
}

public class VoidType <: BuiltinType {
    public init() { super(TypeKind.TYPE_VOID) }
}

public class CStringType <: BuiltinType {
    public init() { super(TypeKind.TYPE_CSTRING) }
}

public class TupleType <: Type {
    public init(fieldTys: ArrayList<Type>) {
        super(TypeKind.TYPE_TUPLE)
        for (ty in fieldTys) {
            argTys.add(ty)
        }
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (ty in argTys) {
            parts.add(ty.ToString())
        }
        return "(" + JoinStrings(parts, ", ") + ")"
    }
}

public class FuncType <: Type {
    private var hasVarArg: Bool = false
    private var isCFunc: Bool = false

    public init(paramTys: ArrayList<Type>, retTy: Type, hasVarLenParam!: Bool = false, isCFunc!: Bool = false) {
        super(TypeKind.TYPE_FUNC)
        for (ty in paramTys) {
            argTys.add(ty)
        }
        argTys.add(retTy)
        this.hasVarArg = hasVarLenParam
        this.isCFunc = isCFunc
    }

    public func HasVarArg(): Bool {
        return hasVarArg
    }

    public override func IsCFunc(): Bool {
        return isCFunc
    }

    public override func IsCJFunc(): Bool {
        return !isCFunc
    }

    public func GetReturnType(): Type {
        return argTys[argTys.size - 1]
    }

    public func GetParamTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx + 1 < argTys.size) {
            out.add(argTys[idx])
            idx++
        }
        return out
    }

    public func GetNumOfParams(): Int64 {
        return argTys.size - 1
    }

    public func GetParamType(index: Int64): Type {
        return argTys[index]
    }

    public override func ToString(): String {
        let params = ArrayList<String>()
        var idx: Int64 = 0
        while (idx + 1 < argTys.size) {
            params.add(argTys[idx].ToString())
            idx++
        }
        if (isCFunc && hasVarArg) {
            params.add("...")
        }
        let funcText = "(" + JoinStrings(params, ", ") + ") -> " + GetReturnType().ToString()
        return if (isCFunc) { "CFunc<" + funcText + ">" } else { funcText }
    }

    public override func ToSrcCodeString(): String {
        let params = ArrayList<String>()
        var idx: Int64 = 0
        while (idx + 1 < argTys.size) {
            params.add(argTys[idx].ToSrcCodeString())
            idx++
        }
        if (isCFunc && hasVarArg) {
            params.add("...")
        }
        let funcText = "(" + JoinStrings(params, ", ") + ") -> " + GetReturnType().ToSrcCodeString()
        return if (isCFunc) { "CFunc<" + funcText + ">" } else { funcText }
    }
}

public class RawArrayType <: BuiltinType {
    private let dims: UInt64

    public init(elementTy: Type, dims!: UInt64 = 1u64) {
        super(TypeKind.TYPE_RAWARRAY)
        argTys.add(elementTy)
        this.dims = dims
    }

    public func GetElementType(): Type {
        return argTys[0]
    }

    public func GetDims(): UInt64 {
        return dims
    }

    public override func ToString(): String {
        var prefix = ""
        var suffix = ""
        var idx: UInt64 = 0u64
        while (idx < dims) {
            prefix += "RawArray<"
            suffix += ">"
            idx++
        }
        return prefix + GetElementType().ToString() + suffix
    }

    public override func ToSrcCodeString(): String {
        var prefix = ""
        var suffix = ""
        var idx: UInt64 = 0u64
        while (idx < dims) {
            prefix += "RawArray<"
            suffix += ">"
            idx++
        }
        return prefix + GetElementType().ToSrcCodeString() + suffix
    }
}

public class VArrayType <: BuiltinType {
    public let size: UInt64

    public init(elementTy: Type, size: UInt64) {
        super(TypeKind.TYPE_VARRAY)
        argTys.add(elementTy)
        this.size = size
    }

    public func GetElementType(): Type {
        return argTys[0]
    }

    public override func ToString(): String {
        return "VArray<" + GetElementType().ToString() + ", $" + "${size}" + ">"
    }

    public override func ToSrcCodeString(): String {
        return "VArray<" + GetElementType().ToSrcCodeString() + ", $" + "${size}" + ">"
    }
}

public class CPointerType <: BuiltinType {
    public init(elementTy: Type) {
        super(TypeKind.TYPE_CPOINTER)
        argTys.add(elementTy)
    }

    public func GetElementType(): Type {
        return argTys[0]
    }

    public override func ToString(): String {
        return "CPointer<${GetElementType().ToString()}>"
    }

    public override func ToSrcCodeString(): String {
        return "CPointer<${GetElementType().ToSrcCodeString()}>"
    }
}

public class RefType <: Type {
    public init(baseTy: Type) {
        super(TypeKind.TYPE_REFTYPE)
        argTys.add(baseTy)
    }

    public func GetBaseType(): Type {
        return argTys[0]
    }

    public func GetRootBaseType(): Type {
        var root = GetBaseType()
        while (root.IsRef()) {
            if (let Some(refTy) <- (root as RefType)) {
                root = refTy.GetBaseType()
            } else {
                return root
            }
        }
        return root
    }

    public override func ToString(): String {
        return GetBaseType().ToString() + "&"
    }

    public override func ToSrcCodeString(): String {
        return GetBaseType().ToSrcCodeString()
    }
}

public class BoxType <: Type {
    public init(baseTy: Type) {
        super(TypeKind.TYPE_BOXTYPE)
        argTys.add(baseTy)
    }

    public func GetBaseType(): Type {
        return argTys[0]
    }

    public override func ToString(): String {
        return "Box<${GetBaseType().ToString()}>"
    }

    public override func ToSrcCodeString(): String {
        return "Box<${GetBaseType().ToSrcCodeString()}>"
    }
}

public class GenericType <: Type {
    public let name: String
    private var srcCodeIdentifier: String
    private let upperBounds: ArrayList<Type> = ArrayList<Type>()

    public init(name: String) {
        this(name, name)
    }

    public init(name: String, srcCodeIdentifier: String) {
        super(TypeKind.TYPE_GENERIC)
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
    }

    public func GetIdentifier(): String {
        return name
    }

    public func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetSrcCodeIdentifier(srcName: String): Unit {
        srcCodeIdentifier = srcName
    }

    public func GetUpperBounds(): ArrayList<Type> {
        return CopyTypeList(upperBounds)
    }

    public func SetUpperBounds(bounds: ArrayList<Type>): Unit {
        upperBounds.clear()
        for (bound in bounds) {
            if (bound.StripAllRefs().IsValueType()) {
                throw IllegalArgumentException("Generic type upper bound should not be a value type")
            }
            upperBounds.add(bound)
        }
        sort(upperBounds, by: { left: Type, right: Type =>
            if (left.ToString() < right.ToString()) {
                Ordering.LT
            } else if (left.ToString() > right.ToString()) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
    }

    public override func ToString(): String {
        return "Generic-" + name
    }

    public override func ToSrcCodeString(): String {
        return srcCodeIdentifier
    }

    public override func Hash(): Int64 {
        return name.hashCode()
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(genericTy) <- (other as GenericType)) {
            return name == genericTy.name
        }
        return false
    }
}

public class ThisType <: Type {
    public let name: String

    public init(name!: String = "This") {
        super(TypeKind.TYPE_THIS)
        this.name = name
    }

    public override func ToString(): String {
        return name
    }

    public override func ToSrcCodeString(): String {
        return name
    }
}

public open class CustomType <: Type {
    public let def: CustomTypeDef

    public init(kind: TypeKind, def: CustomTypeDef, typeArgs: ArrayList<Type>) {
        super(kind)
        this.def = def
        for (ty in typeArgs) {
            argTys.add(ty)
        }
    }

    public func GetCustomTypeDef(): CustomTypeDef {
        return def
    }

    public func GetGenericArgs(): ArrayList<Type> {
        return CopyTypeList(argTys)
    }

    public override func ToString(): String {
        let args = TypeListKey(argTys)
        if (args.isEmpty()) {
            return def.GetFullName()
        }
        return def.GetFullName() + "<" + args + ">"
    }

    public override func ToSrcCodeString(): String {
        let args = ArrayList<String>()
        for (ty in argTys) {
            args.add(ty.ToSrcCodeString())
        }
        if (args.isEmpty()) {
            return def.GetIdentifier()
        }
        return def.GetIdentifier() + "<" + JoinStrings(args, ",") + ">"
    }
}

public class StructType <: CustomType {
    public init(def: StructDef, typeArgs: ArrayList<Type>) {
        super(TypeKind.TYPE_STRUCT, def, typeArgs)
    }

    public func GetStructDef(): StructDef {
        if (let Some(structDef) <- (def as StructDef)) {
            return structDef
        }
        throw IllegalStateException("StructType does not reference a StructDef")
    }
}

public class ClassType <: CustomType {
    public init(def: ClassDef, typeArgs: ArrayList<Type>) {
        super(TypeKind.TYPE_CLASS, def, typeArgs)
    }

    public func GetClassDef(): ClassDef {
        if (let Some(classDef) <- (def as ClassDef)) {
            return classDef
        }
        throw IllegalStateException("ClassType does not reference a ClassDef")
    }

    public func GetSuperClassTy(builder!: Option<CHIRBuilder> = None): Option<ClassType> {
        let _ = builder
        return GetClassDef().GetSuperClassTy()
    }
}

public class EnumType <: CustomType {
    public init(def: EnumDef, typeArgs: ArrayList<Type>) {
        super(TypeKind.TYPE_ENUM, def, typeArgs)
    }

    public func GetEnumDef(): EnumDef {
        if (let Some(enumDef) <- (def as EnumDef)) {
            return enumDef
        }
        throw IllegalStateException("EnumType does not reference an EnumDef")
    }

    public func IsOption(): Bool {
        return GetEnumDef().GetPackageName() == "std.core" && GetEnumDef().GetIdentifier() == "Option"
    }
}
