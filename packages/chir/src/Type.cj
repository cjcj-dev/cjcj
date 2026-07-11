package cjcj::chir

import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK}
import std.collection.*
import std.sort.*
import std.sync.*

@OverflowWrapping
func HashCombine(seed: Int64, value: Int64): Int64 {
    return seed ^ (value + 0x9e3779b9 + (seed << 6) + (seed >> 2))
}

func HashValue(seed: Int64, value: Int64): Int64 {
    return HashCombine(seed, value)
}

func HashValue(seed: Int64, value: UInt64): Int64 {
    return HashCombine(seed, value.hashCode())
}

func HashValue(seed: Int64, value: Bool): Int64 {
    return HashCombine(seed, if (value) { 1 } else { 0 })
}

func HashValue(seed: Int64, value: String): Int64 {
    return HashCombine(seed, value.hashCode())
}

func HashValue(seed: Int64, value: TypeKind): Int64 {
    return HashCombine(seed, TypeKindIndex(value))
}

func HashArgTypes(argTys: ArrayList<Type>): Int64 {
    var hashVal: Int64 = 0
    for (argTy in argTys) {
        hashVal = HashCombine(hashVal, argTy.objectId)
    }
    return hashVal
}

func TypeArgsAreEqual(left: ArrayList<Type>, right: ArrayList<Type>): Bool {
    if (left.size != right.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.size) {
        if (!refEq(left[idx], right[idx])) {
            return false
        }
        idx++
    }
    return true
}

public open class Type <: Hashable & Equatable<Type> {
    private static let nextObjectId = AtomicInt64(1)

    public let objectId: Int64
    public let kind: TypeKind
    public let argTys: ArrayList<Type> = ArrayList<Type>()

    public init(kind: TypeKind) {
        objectId = nextObjectId.fetchAdd(1)
        this.kind = kind
    }

    public operator func ==(right: Type): Bool {
        return objectId == right.objectId
    }

    public operator func !=(right: Type): Bool {
        return objectId != right.objectId
    }

    public func hashCode(): Int64 {
        return objectId.hashCode()
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
        let ty = if (let Some(refTy) <- (this as RefType)) { refTy.GetBaseType() } else { this }
        if (let Some(structTy) <- (ty as StructType)) {
            let def = structTy.GetCustomTypeDef()
            return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Array"
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
            let def = structTy.GetCustomTypeDef()
            return def.packageName == "std.core" &&
                (def.identifier == "String" || def.GetSrcCodeIdentifier() == "String" ||
                    def.identifier == "_Cstd_core_String")
        }
        return false
    }

    public open func IsAny(): Bool {
        if (let Some(classTy) <- (this as ClassType)) {
            return CheckCustomTypeDefIsExpected(classTy.GetCustomTypeDef(), "std.core", "Any")
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
        return argTys.clone()
    }

    public func GetTypeArgsRef(): ArrayList<Type> {
        return argTys
    }

    public open func Hash(): Int64 {
        var hashVal = HashArgTypes(argTys)
        hashVal = HashValue(hashVal, kind)
        return hashVal
    }

    public open func IsEqual(other: Type): Bool {
        return kind == other.kind && TypeArgsAreEqual(argTys, other.argTys)
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

    public func VisitTypeRecursively(visitor: (Type) -> Bool): Unit {
        if (visitor(this)) {
            for (ty in argTys) {
                ty.VisitTypeRecursively(visitor)
            }
        }
    }

    // Type.cpp:66 IsAutoEnv = kind == CLASS && IsClosureConversionEnvClass(classDef);
    // Utils.cpp:1025 IsClosureConversionEnvClass(def) = def.Get<IsAutoEnvClass>().
    public func IsAutoEnv(): Bool {
        if (!IsClass()) {
            return false
        }
        let classTy = (this as ClassType).getOrThrow()
        return classTy.GetClassDef().Get<IsAutoEnvClass, Bool>()
    }

    // Type.cpp:71 IsAutoEnvBase = IsClosureConversionEnvClass(classDef) && classDef->TestAttr(ABSTRACT).
    public func IsAutoEnvBase(): Bool {
        if (!IsClass()) {
            return false
        }
        let classDef = (this as ClassType).getOrThrow().GetClassDef()
        return classDef.Get<IsAutoEnvClass, Bool>() && classDef.TestAttr(Attribute.ABSTRACT)
    }

    public func IsAutoEnvInstBase(): Bool {
        return IsAutoEnvBase() && argTys.isEmpty()
    }

    public func IsAutoEnvGenericBase(): Bool {
        return IsAutoEnvBase() && !argTys.isEmpty()
    }

    public func CalculateGenericTyMapping(targetTy: Type): (Bool, HashMap<Int64, Type>) {
        let replaceTable = HashMap<Int64, Type>()
        let res = CalculateGenericTyMappingImpl(targetTy, this, replaceTable)
        return (res, replaceTable)
    }

    public func IsEqualOrSubTypeOf(parentType: Type, builder: CHIRBuilder,
        visited!: Option<HashSet<String>> = None): Bool {
        let activeVisited = match (visited) {
            case Some(values) => values
            case None => HashSet<String>()
        }
        let pairKey = objectId.toString() + ":" + parentType.objectId.toString()
        if (activeVisited.contains(pairKey)) {
            return false
        }
        activeVisited.add(pairKey)

        if (IsRef() && parentType.IsRef()) {
            let subBaseType = (this as RefType).getOrThrow().GetBaseType()
            let parentBaseType = (parentType as RefType).getOrThrow().GetBaseType()
            return subBaseType.IsEqualOrSubTypeOf(parentBaseType, builder, visited: activeVisited)
        }

        let thisDeref = StripAllRefs()
        let parentDeref = parentType.StripAllRefs()
        if ((IsRef() || parentType.IsRef()) && thisDeref.IsEqual(parentDeref)) {
            return false
        }
        if (thisDeref.IsEqual(parentDeref) || thisDeref.IsNothing() || parentDeref.IsAny()) {
            return true
        }
        if (thisDeref.IsInvalid() || parentDeref.IsInvalid() || parentDeref.IsGeneric()) {
            return false
        }
        if (parentDeref.IsCType()) {
            return SatisfyCType()
        }
        if (thisDeref.IsGeneric()) {
            let genericTy = (thisDeref as GenericType).getOrThrow()
            for (upperBound in genericTy.GetUpperBounds()) {
                if (!upperBound.StripAllRefs().IsEqualOrSubTypeOf(parentDeref, builder, visited: activeVisited)) {
                    return false
                }
            }
            return true
        }
        if (thisDeref.IsTuple()) {
            if (!parentDeref.IsTuple()) {
                return false
            }
            return TupleTypeIsEqualOrSub((thisDeref as TupleType).getOrThrow(),
                (parentDeref as TupleType).getOrThrow(), builder)
        }
        if (thisDeref.IsFunc()) {
            if (!parentDeref.IsFunc()) {
                return false
            }
            return FuncTypeIsEqualOrSub((thisDeref as FuncType).getOrThrow(),
                (parentDeref as FuncType).getOrThrow(), builder)
        }
        if (thisDeref.IsAutoEnv()) {
            if (!parentDeref.IsAutoEnv()) {
                return false
            }
            return ClosureTypeIsEqualOrSub((thisDeref as ClassType).getOrThrow(),
                (parentDeref as ClassType).getOrThrow(), builder)
        }

        let allParents = ArrayList<ClassType>()
        if (let Some(builtinType) <- (thisDeref as BuiltinType)) {
            for (parent in builtinType.GetSuperTypesRecusively(builder, Some(activeVisited))) {
                allParents.add(parent)
            }
        } else if (let Some(customType) <- (thisDeref as CustomType)) {
            for (parent in customType.GetSuperTypesRecusively(builder, Some(activeVisited))) {
                allParents.add(parent)
            }
        }
        for (parent in allParents) {
            if (parent.IsEqual(parentDeref)) {
                return true
            }
            let mapping = parentDeref.CalculateGenericTyMapping(parent)
            if (mapping[0]) {
                return true
            }
        }
        return false
    }

    public func IsEqualOrInstantiatedTypeOf(genericRelatedType: Type, builder: CHIRBuilder,
        visited!: Option<HashSet<String>> = None): Bool {
        if (IsEqual(genericRelatedType)) {
            return true
        }
        let res = genericRelatedType.CalculateGenericTyMapping(this)
        if (!res[0]) {
            return false
        }
        for ((genericId, instTy) in res[1]) {
            let genericTys = ArrayList<GenericType>()
            genericRelatedType.VisitTypeRecursively({ ty: Type =>
                if (let Some(curGenericTy) <- (ty as GenericType)) {
                    if (curGenericTy.objectId == genericId) {
                        genericTys.add(curGenericTy)
                        return false
                    }
                }
                return true
            })
            if (genericTys.isEmpty()) {
                throw IllegalStateException("generic type from CalculateGenericTyMapping is missing")
            }
            let typeParam = genericTys[0]
            if (!instTy.SatisfyGenericConstraints(typeParam, builder, res[1], visited: visited)) {
                return false
            }
        }
        return true
    }

    public func SatisfyGenericConstraints(genericType: GenericType, builder: CHIRBuilder,
        instMap: HashMap<Int64, Type>, visited!: Option<HashSet<String>> = None): Bool {
        for (upperBound in genericType.GetUpperBounds()) {
            let visited2 = HashSet<String>()
            if (let Some(values) <- visited) {
                for (value in values) {
                    visited2.add(value)
                }
            }
            let instUpperBound = ReplaceRawGenericArgType(upperBound, instMap, builder)
            if (!IsEqualOrSubTypeOf(instUpperBound, builder, visited: visited2)) {
                return false
            }
        }
        return true
    }

    public open func GetExtends(): ArrayList<ExtendDef> {
        throw IllegalStateException("Type.GetExtends is unsupported for " + ToString())
    }

    public open func GetExtends(builder: CHIRBuilder): ArrayList<ExtendDef> {
        let _ = builder
        return GetExtends()
    }

    public open func GetSuperTypesRecusively(builder: CHIRBuilder,
        visited: Option<HashSet<String>>): ArrayList<ClassType> {
        let _ = builder
        let _ = visited
        throw IllegalStateException("Type.GetSuperTypesRecusively is unsupported for " + ToString())
    }

    public func GetSuperTypesRecusively(builder: CHIRBuilder): ArrayList<ClassType> {
        return GetSuperTypesRecusively(builder, None)
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

    public open override func GetExtends(): ArrayList<ExtendDef> {
        let out = ArrayList<ExtendDef>()
        for (extendDef in extends) {
            out.add(extendDef)
        }
        return out
    }

    public open override func GetExtends(builder: CHIRBuilder): ArrayList<ExtendDef> {
        let _ = builder
        return GetExtends()
    }

    public override func GetSuperTypesRecusively(builder: CHIRBuilder,
        visited: Option<HashSet<String>>): ArrayList<ClassType> {
        let inheritanceList = ArrayList<ClassType>()
        for (extendDef in GetExtends(builder)) {
            let visited2 = HashSet<String>()
            if (let Some(values) <- visited) {
                for (value in values) {
                    visited2.add(value)
                }
            }
            let extendedType = extendDef.GetExtendedType().getOrThrow()
            if (!IsEqualOrInstantiatedTypeOf(extendedType, builder, visited: visited2)) {
                continue
            }
            for (interfaceTy in extendDef.GetImplementedInterfaceTys()) {
                GetAllInstantiatedParentType(interfaceTy, builder, inheritanceList, visited: visited)
            }
        }
        return inheritanceList
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

    public func GetElementTypes(): ArrayList<Type> {
        return GetTypeArgs()
    }

    public func GetElementType(index: Int64): Type {
        return argTys[index]
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

    public override func Hash(): Int64 {
        var hashVal = HashArgTypes(argTys)
        hashVal = HashValue(hashVal, isCFunc)
        hashVal = HashValue(hashVal, hasVarArg)
        hashVal = HashValue(hashVal, kind)
        return hashVal
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(funcTy) <- (other as FuncType)) {
            return TypeArgsAreEqual(argTys, funcTy.argTys) && isCFunc == funcTy.IsCFunc() &&
                hasVarArg == funcTy.HasVarArg()
        }
        return false
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

    public override func Hash(): Int64 {
        var hashVal = HashArgTypes(argTys)
        hashVal = HashValue(hashVal, dims)
        hashVal = HashValue(hashVal, kind)
        return hashVal
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(rawArrayTy) <- (other as RawArrayType)) {
            return TypeArgsAreEqual(argTys, rawArrayTy.argTys) && dims == rawArrayTy.GetDims()
        }
        return false
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

    public func GetSize(): UInt64 {
        return size
    }

    public override func ToString(): String {
        return "VArray<" + GetElementType().ToString() + ", $" + "${size}" + ">"
    }

    public override func ToSrcCodeString(): String {
        return "VArray<" + GetElementType().ToSrcCodeString() + ", $" + "${size}" + ">"
    }

    public override func Hash(): Int64 {
        var hashVal = HashArgTypes(argTys)
        hashVal = HashValue(hashVal, size)
        hashVal = HashValue(hashVal, kind)
        return hashVal
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(varrayTy) <- (other as VArrayType)) {
            return TypeArgsAreEqual(argTys, varrayTy.argTys) && size == varrayTy.size
        }
        return false
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

    public override func GetExtends(): ArrayList<ExtendDef> {
        if (!GetElementType().IsUnit()) {
            throw IllegalStateException("CPointerType.GetExtends needs CHIRBuilder")
        }
        return super.GetExtends()
    }

    public override func GetExtends(builder: CHIRBuilder): ArrayList<ExtendDef> {
        if (!GetElementType().IsUnit()) {
            return builder.context.GetCPointerTy(builder.context.GetUnitTy()).GetExtends(builder)
        }
        return super.GetExtends(builder)
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
        return upperBounds.clone()
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

    public func GetInstMap(instMap: HashMap<Int64, (GenericType, Type)>, builder: CHIRBuilder): Unit {
        for (upperBound in upperBounds) {
            let upperBoundCustomType = (upperBound.StripAllRefs() as CustomType).getOrThrow()
            upperBoundCustomType.GetInstMap(instMap, builder)
        }
    }

    public func GetInstMemberTypeByPath(path: ArrayList<UInt64>, builder: CHIRBuilder): Type {
        return GetInstMemberTypeByPathCheckingReadOnly(path, builder)[0]
    }

    public func GetInstMemberTypeByPathCheckingReadOnly(path: ArrayList<UInt64>, builder: CHIRBuilder): (Type, Bool) {
        var concretType: Option<Type> = None
        for (upperBound in upperBounds) {
            let upperBoundCustomType = (upperBound.StripAllRefs() as CustomType).getOrThrow()
            if (upperBoundCustomType.GetCustomTypeDef().IsClassLike()) {
                if (concretType.isNone()) {
                    concretType = upperBound
                } else if (upperBoundCustomType.IsEqualOrSubTypeOf(
                    concretType.getOrThrow().StripAllRefs(), builder)) {
                    concretType = upperBound
                }
            }
        }
        CJC_NULLPTR_CHECK(concretType)
        return (concretType.getOrThrow().StripAllRefs() as CustomType).getOrThrow()
            .GetInstMemberTypeByPathCheckingReadOnly(path, builder)
    }

    public override func ToString(): String {
        return "Generic-" + name
    }

    public override func ToSrcCodeString(): String {
        return srcCodeIdentifier
    }

    public override func Hash(): Int64 {
        var hashVal: Int64 = 0
        hashVal = HashValue(hashVal, name)
        return hashVal
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(genericTy) <- (other as GenericType)) {
            return name == genericTy.name
        }
        return false
    }
}

public class ThisType <: Type {
    public init() {
        super(TypeKind.TYPE_THIS)
    }

    public override func ToString(): String {
        return "This"
    }

    public override func ToSrcCodeString(): String {
        return "This"
    }
}

public open class CustomType <: Type {
    public let def: CustomTypeDef
    private let implementedInterfaceTys: ArrayList<ClassType> = ArrayList<ClassType>()
    private var hasSetSuperInterface: Bool = false
    private let setSuperInterfaceMtx: Mutex = Mutex()

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
        return argTys.clone()
    }

    public open func ResetAllInstantiatedType(): Unit {
        implementedInterfaceTys.clear()
        hasSetSuperInterface = false
    }

    public override func GetExtends(): ArrayList<ExtendDef> {
        return GetCustomTypeDef().GetExtends()
    }

    public override func GetExtends(builder: CHIRBuilder): ArrayList<ExtendDef> {
        let _ = builder
        return GetExtends()
    }

    public override func GetSuperTypesRecusively(builder: CHIRBuilder,
        visited: Option<HashSet<String>>): ArrayList<ClassType> {
        let inheritanceList = ArrayList<ClassType>()
        for (interfaceTy in GetImplementedInterfaceTys(builder, visited: visited)) {
            GetAllInstantiatedParentType(interfaceTy, builder, inheritanceList, visited: visited)
        }
        if (let Some(classTy) <- (this as ClassType)) {
            if (let Some(superClass) <- classTy.GetSuperClassTy(builder: builder)) {
                GetAllInstantiatedParentType(superClass, builder, inheritanceList, visited: visited)
            }
        }
        return inheritanceList
    }

    public func CalculateExtendImplementedInterfaceTys(builder: CHIRBuilder,
        visited!: Option<HashSet<String>> = None): ArrayList<ClassType> {
        let allParents = ArrayList<ClassType>()
        for (extendDef in def.GetExtends()) {
            let visited2 = HashSet<String>()
            if (let Some(values) <- visited) {
                for (value in values) {
                    visited2.add(value)
                }
            }
            let extendedType = extendDef.GetExtendedType().getOrThrow()
            if (!IsEqualOrInstantiatedTypeOf(extendedType, builder, visited: visited2)) {
                continue
            }
            let res = extendedType.CalculateGenericTyMapping(this)
            CJC_ASSERT(res[0])
            for (parent in extendDef.GetImplementedInterfaceTys()) {
                allParents.add((ReplaceRawGenericArgType(parent, res[1], builder) as ClassType).getOrThrow())
            }
        }
        return allParents
    }

    public func CalculateImplementedInterfaceTys(builder: CHIRBuilder,
        visited!: Option<HashSet<String>> = None): ArrayList<ClassType> {
        let genericTypes = def.GetGenericTypeParams()
        if (!genericTypes.isEmpty()) {
            CJC_ASSERT(argTys.size == genericTypes.size)
        }
        let instSuperInterfaceTys = CalculateExtendImplementedInterfaceTys(builder, visited: visited)
        let replaceTable = HashMap<Int64, Type>()
        var typeIdx: Int64 = 0
        while (typeIdx < genericTypes.size) {
            replaceTable[genericTypes[typeIdx].objectId] = argTys[typeIdx]
            typeIdx++
        }
        for (ty in def.GetImplementedInterfaceTys()) {
            instSuperInterfaceTys.add((ReplaceRawGenericArgType(ty, replaceTable, builder) as ClassType).getOrThrow())
        }
        return instSuperInterfaceTys
    }

    public func GetImplementedInterfaceTys(builder: CHIRBuilder,
        visited!: Option<HashSet<String>> = None): ArrayList<ClassType> {
        var result = ArrayList<ClassType>()
        synchronized(setSuperInterfaceMtx) {
            if (hasSetSuperInterface) {
                result = implementedInterfaceTys.clone()
            } else {
                implementedInterfaceTys.clear()
                for (interfaceTy in CalculateImplementedInterfaceTys(builder, visited: visited)) {
                    implementedInterfaceTys.add(interfaceTy)
                }
                hasSetSuperInterface = true
                result = implementedInterfaceTys.clone()
            }
        }
        return result
    }

    public func GetInstMap(instMap: HashMap<Int64, (GenericType, Type)>, builder: CHIRBuilder): Unit {
        let customTypeDef = GetCustomTypeDef()
        let customTypeDefGenericParams = customTypeDef.GetGenericTypeParams()
        let customTypeGenericArgs = GetGenericArgs()
        if (!customTypeDefGenericParams.isEmpty()) {
            CJC_ASSERT(customTypeDefGenericParams.size == customTypeGenericArgs.size)
        }
        var paramIdx: Int64 = 0
        while (paramIdx < customTypeDefGenericParams.size) {
            let genericParam = customTypeDefGenericParams[paramIdx]
            if (!instMap.contains(genericParam.objectId)) {
                instMap[genericParam.objectId] = (genericParam, customTypeGenericArgs[paramIdx])
            }
            paramIdx++
        }

        for (parentInterfaceTy in customTypeDef.GetImplementedInterfaceTys()) {
            let parentInterfaceDef = parentInterfaceTy.GetCustomTypeDef()
            let parentInterfaceDefGenericParams = parentInterfaceDef.GetGenericTypeParams()
            let instParentInterfaceTy =
                (ReplaceRawGenericArgType(parentInterfaceTy, instMap, builder) as ClassType).getOrThrow()
            let parentInterfaceTypeGenericArgs = instParentInterfaceTy.GetGenericArgs()
            if (!customTypeDefGenericParams.isEmpty()) {
                CJC_ASSERT(parentInterfaceDefGenericParams.size == parentInterfaceTypeGenericArgs.size)
            }
            var interfaceIdx: Int64 = 0
            while (interfaceIdx < parentInterfaceDefGenericParams.size) {
                let interfaceGenericParam = parentInterfaceDefGenericParams[interfaceIdx]
                if (!instMap.contains(interfaceGenericParam.objectId)) {
                    instMap[interfaceGenericParam.objectId] =
                        (interfaceGenericParam, parentInterfaceTypeGenericArgs[interfaceIdx])
                }
                interfaceIdx++
            }
            parentInterfaceTy.GetInstMap(instMap, builder)
        }

        if (let Some(classTy) <- (this as ClassType)) {
            let classTypeDef = classTy.GetClassDef()
            if (let Some(parentClassTy) <- classTypeDef.GetSuperClassTy()) {
                let parentClassDef = parentClassTy.GetCustomTypeDef()
                let parentClassDefGenericParams = parentClassDef.GetGenericTypeParams()
                let instParentClassTy =
                    (ReplaceRawGenericArgType(parentClassTy, instMap, builder) as ClassType).getOrThrow()
                let parentClassTypeGenericArgs = instParentClassTy.GetGenericArgs()
                if (!parentClassDefGenericParams.isEmpty()) {
                    CJC_ASSERT(parentClassDefGenericParams.size == parentClassTypeGenericArgs.size)
                }
                var classIdx: Int64 = 0
                while (classIdx < parentClassDefGenericParams.size) {
                    let classGenericParam = parentClassDefGenericParams[classIdx]
                    if (!instMap.contains(classGenericParam.objectId)) {
                        instMap[classGenericParam.objectId] =
                            (classGenericParam, parentClassTypeGenericArgs[classIdx])
                    }
                    classIdx++
                }
                parentClassTy.GetInstMap(instMap, builder)
            }
        }
    }

    public func GetInstMemberTypeByPath(path: ArrayList<UInt64>, builder: CHIRBuilder): Type {
        return GetInstMemberTypeByPathCheckingReadOnly(path, builder)[0]
    }

    public func GetInstMemberTypeByPathCheckingReadOnly(path: ArrayList<UInt64>, builder: CHIRBuilder): (Type, Bool) {
        if (path.isEmpty()) {
            CJC_ABORT()
            return (this, false)
        }
        let customTypeDef = GetCustomTypeDef()
        let instMap = HashMap<Int64, (GenericType, Type)>()
        GetInstMap(instMap, builder)
        let currentIdx = path[0]
        let member = customTypeDef.GetAllInstanceVars()[Int64(currentIdx)]
        let isReadOnly = member.TestAttr(Attribute.READONLY)
        let memberTy = ReplaceRawGenericArgType(member.ty, instMap, builder)
        if (path.size > 1) {
            var pureMemberTy = memberTy
            while (pureMemberTy.IsRef()) {
                pureMemberTy = (pureMemberTy as RefType).getOrThrow().GetBaseType()
            }
            if (pureMemberTy.IsNominal()) {
                let subPath = path.clone()
                subPath.remove(at: 0)
                let (memberType, isMemberReadOnly) = (pureMemberTy as CustomType).getOrThrow()
                    .GetInstMemberTypeByPathCheckingReadOnly(subPath, builder)
                return (memberType, isReadOnly || isMemberReadOnly)
            } else if (pureMemberTy.IsGeneric()) {
                let subPath = path.clone()
                subPath.remove(at: 0)
                let (memberType, isMemberReadOnly) = (pureMemberTy as GenericType).getOrThrow()
                    .GetInstMemberTypeByPathCheckingReadOnly(subPath, builder)
                return (memberType, isReadOnly || isMemberReadOnly)
            } else {
                CJC_ABORT()
            }
        }
        return (memberTy, isReadOnly)
    }

    public func GetInstantiatedMemberTys(): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (let Some(classTy) <- (this as ClassType)) {
            if (let Some(superTy) <- classTy.GetSuperClassTy()) {
                for (fieldTy in superTy.GetInstantiatedMemberTys()) {
                    out.add(fieldTy)
                }
            }
        }

        let genericParams = def.GetGenericTypeParams()
        for (member in def.GetDirectInstanceVars()) {
            out.add(ReplaceRawGenericArgType(member.ty, genericParams, GetGenericArgs()))
        }
        return out
    }

    public override func ToString(): String {
        let args = TypeVecToString("", argTys, "", delimiter: ",")
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

    public override func Hash(): Int64 {
        var hashVal = HashArgTypes(argTys)
        hashVal = HashValue(hashVal, def.nodeId)
        return hashVal
    }

    public override func IsEqual(other: Type): Bool {
        if (let Some(customTy) <- (other as CustomType)) {
            return TypeArgsAreEqual(argTys, customTy.argTys) && refEq(def, customTy.def)
        }
        return false
    }
}

private func CalculateGenericTyMappingImpl(instType: Type, genericType: Type,
    replaceTable: HashMap<Int64, Type>): Bool {
    if (let Some(genericTy) <- (genericType as GenericType)) {
        if (let Some(storedType) <- replaceTable.get(genericTy.objectId)) {
            return storedType.IsEqual(instType)
        }
        replaceTable[genericTy.objectId] = instType
        return true
    }
    if (instType.IsEqual(genericType)) {
        return true
    }
    if (instType.GetTypeKind() != genericType.GetTypeKind()) {
        return false
    }
    if (let Some(instCustomType) <- (instType as CustomType)) {
        let genericCustomType = (genericType as CustomType).getOrThrow()
        if (instCustomType.GetCustomTypeDef().nodeId != genericCustomType.GetCustomTypeDef().nodeId) {
            return false
        }
    }
    let instTypeArgs = instType.GetTypeArgs()
    let genericTypeArgs = genericType.GetTypeArgs()
    if (instTypeArgs.size != genericTypeArgs.size) {
        return false
    }
    var argIdx: Int64 = 0
    while (argIdx < instTypeArgs.size) {
        if (!CalculateGenericTyMappingImpl(instTypeArgs[argIdx], genericTypeArgs[argIdx], replaceTable)) {
            return false
        }
        argIdx++
    }
    return true
}

private func TupleTypeIsEqualOrSub(subType: TupleType, parentType: TupleType, builder: CHIRBuilder): Bool {
    let thisTupleArgs = subType.GetTypeArgs()
    let parentTupleArgs = parentType.GetTypeArgs()
    if (thisTupleArgs.size != parentTupleArgs.size) {
        return false
    }
    var argIdx: Int64 = 0
    while (argIdx < thisTupleArgs.size) {
        if (!thisTupleArgs[argIdx].IsEqualOrSubTypeOf(parentTupleArgs[argIdx], builder)) {
            return false
        }
        argIdx++
    }
    return true
}

private func FuncTypeIsEqualOrSub(subType: FuncType, parentType: FuncType, builder: CHIRBuilder): Bool {
    if (subType.IsCFunc() != parentType.IsCFunc()) {
        return false
    }
    if (subType.HasVarArg() != parentType.HasVarArg()) {
        return false
    }
    let thisParamTypes = subType.GetParamTypes()
    let parentParamTypes = parentType.GetParamTypes()
    if (thisParamTypes.size != parentParamTypes.size) {
        return false
    }
    var paramIdx: Int64 = 0
    while (paramIdx < thisParamTypes.size) {
        if (!parentParamTypes[paramIdx].IsEqualOrSubTypeOf(thisParamTypes[paramIdx], builder)) {
            return false
        }
        paramIdx++
    }
    return subType.GetReturnType().IsEqualOrSubTypeOf(parentType.GetReturnType(), builder)
}

private func GetAutoEnvGenericBase(classTy: ClassType, builder: CHIRBuilder): ClassType {
    CJC_ASSERT(classTy.IsAutoEnv())
    if (classTy.IsAutoEnvGenericBase()) {
        return classTy
    }
    return GetAutoEnvGenericBase(classTy.GetSuperClassTy(builder: builder).getOrThrow(), builder)
}

private func ConvertClosureTypeToFuncType(closureType: ClassType, builder: CHIRBuilder): FuncType {
    let typeArgs = GetAutoEnvGenericBase(closureType, builder).GetGenericArgs()
    CJC_ASSERT(!typeArgs.isEmpty())
    let retType = typeArgs[typeArgs.size - 1]
    typeArgs.remove(at: typeArgs.size - 1)
    return builder.context.GetFuncTy(typeArgs, retType)
}

private func ClosureTypeIsEqualOrSub(subType: ClassType, parentType: ClassType, builder: CHIRBuilder): Bool {
    let subFuncType = ConvertClosureTypeToFuncType(subType, builder)
    let parentFuncType = ConvertClosureTypeToFuncType(parentType, builder)
    return FuncTypeIsEqualOrSub(subFuncType, parentFuncType, builder)
}

public func GetAllInstantiatedParentType(cur: ClassType, builder: CHIRBuilder, parents: ArrayList<ClassType>,
    visited!: Option<HashSet<String>> = None): Unit {
    for (parent in parents) {
        if (parent.IsEqual(cur)) {
            return
        }
    }
    for (extendDef in cur.GetCustomTypeDef().GetExtends()) {
        let extendedType = extendDef.GetExtendedType().getOrThrow()
        if (!cur.IsEqualOrInstantiatedTypeOf(extendedType, builder, visited: visited)) {
            continue
        }
        let res = extendedType.CalculateGenericTyMapping(cur)
        for (interfaceTy in extendDef.GetImplementedInterfaceTys()) {
            let extendParents = ArrayList<ClassType>()
            GetAllInstantiatedParentType(interfaceTy, builder, extendParents, visited: visited)
            var parentIdx: Int64 = 0
            while (parentIdx < extendParents.size) {
                let instParent =
                    (ReplaceRawGenericArgType(extendParents[parentIdx], res[1], builder) as ClassType).getOrThrow()
                var found = false
                for (parent in parents) {
                    if (parent.IsEqual(instParent)) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    parents.add(instParent)
                }
                parentIdx++
            }
        }
    }
    for (interfaceTy in cur.GetImplementedInterfaceTys(builder, visited: visited)) {
        GetAllInstantiatedParentType(interfaceTy, builder, parents, visited: visited)
    }
    if (let Some(superClassTy) <- cur.GetSuperClassTy(builder: builder)) {
        GetAllInstantiatedParentType(superClassTy, builder, parents, visited: visited)
    }
    parents.add(cur)
}

public func ReplaceRawGenericArgType(ty: Type, replaceTable: HashMap<Int64, Type>): Type {
    if (replaceTable.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        if (let Some(instTy) <- replaceTable.get(genericTy.objectId)) {
            return instTy
        }
        return ty
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return RefType(ReplaceRawGenericArgType(refTy.GetBaseType(), replaceTable))
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return RawArrayType(ReplaceRawGenericArgType(rawArrayTy.GetElementType(), replaceTable),
            dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return VArrayType(ReplaceRawGenericArgType(varrayTy.GetElementType(), replaceTable), varrayTy.size)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        return CPointerType(ReplaceRawGenericArgType(pointerTy.GetElementType(), replaceTable))
    }
    if (let Some(boxTy) <- (ty as BoxType)) {
        return BoxType(ReplaceRawGenericArgType(boxTy.GetBaseType(), replaceTable))
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        let args = ArrayList<Type>()
        for (arg in tupleTy.GetTypeArgs()) {
            args.add(ReplaceRawGenericArgType(arg, replaceTable))
        }
        return TupleType(args)
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        let params = ArrayList<Type>()
        for (param in funcTy.GetParamTypes()) {
            params.add(ReplaceRawGenericArgType(param, replaceTable))
        }
        let retTy = ReplaceRawGenericArgType(funcTy.GetReturnType(), replaceTable)
        return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }
    if (let Some(structTy) <- (ty as StructType)) {
        let args = ArrayList<Type>()
        for (arg in structTy.GetGenericArgs()) {
            args.add(ReplaceRawGenericArgType(arg, replaceTable))
        }
        return StructType(structTy.GetStructDef(), args)
    }
    if (let Some(classTy) <- (ty as ClassType)) {
        let args = ArrayList<Type>()
        for (arg in classTy.GetGenericArgs()) {
            args.add(ReplaceRawGenericArgType(arg, replaceTable))
        }
        return ClassType(classTy.GetClassDef(), args)
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        let args = ArrayList<Type>()
        for (arg in enumTy.GetGenericArgs()) {
            args.add(ReplaceRawGenericArgType(arg, replaceTable))
        }
        return EnumType(enumTy.GetEnumDef(), args)
    }
    return ty
}

public func CreateNewTypeWithArgs(oldType: Type, newArgs: ArrayList<Type>, builder: CHIRBuilder): Type {
    if (newArgs.isEmpty()) {
        return oldType
    }
    if (let Some(tupleTy) <- (oldType as TupleType)) {
        let _ = tupleTy
        return builder.context.GetTupleTy(newArgs)
    }
    if (let Some(structTy) <- (oldType as StructType)) {
        return builder.context.GetStructTy(structTy.GetStructDef(), newArgs)
    }
    if (let Some(enumTy) <- (oldType as EnumType)) {
        return builder.context.GetEnumTy(enumTy.GetEnumDef(), newArgs)
    }
    if (let Some(funcTy) <- (oldType as FuncType)) {
        let paramTys = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx < newArgs.size - 1) {
            paramTys.add(newArgs[idx])
            idx++
        }
        return builder.context.GetFuncTy(paramTys, newArgs[newArgs.size - 1], hasVarLenParam: funcTy.HasVarArg(),
            isCFunc: oldType.IsCFunc())
    }
    if (let Some(classTy) <- (oldType as ClassType)) {
        return builder.context.GetClassTy(classTy.GetClassDef(), newArgs)
    }
    if (let Some(refTy) <- (oldType as RefType)) {
        let _ = refTy
        CJC_ASSERT(newArgs.size == 1)
        return builder.context.GetRefTy(newArgs[0])
    }
    if (let Some(pointerTy) <- (oldType as CPointerType)) {
        let _ = pointerTy
        CJC_ASSERT(newArgs.size == 1)
        return builder.context.GetCPointerTy(newArgs[0])
    }
    if (let Some(rawArrayTy) <- (oldType as RawArrayType)) {
        CJC_ASSERT(newArgs.size == 1)
        return builder.context.GetRawArrayTy(newArgs[0], dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (oldType as VArrayType)) {
        CJC_ASSERT(newArgs.size == 1)
        return builder.context.GetVArrayTy(newArgs[0], varrayTy.size)
    }
    if (let Some(boxTy) <- (oldType as BoxType)) {
        let _ = boxTy
        CJC_ASSERT(newArgs.size == 1)
        return builder.context.GetBoxTy(newArgs[0])
    }
    throw IllegalStateException("CreateNewTypeWithArgs unsupported for " + oldType.ToString())
}

public func ReplaceRawGenericArgType(ty: Type, replaceTable: HashMap<Int64, Type>, builder: CHIRBuilder): Type {
    if (replaceTable.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        if (let Some(instTy) <- replaceTable.get(genericTy.objectId)) {
            return instTy
        }
        return ty
    }
    let newArgs = ArrayList<Type>()
    for (argTy in ty.GetTypeArgs()) {
        newArgs.add(ReplaceRawGenericArgType(argTy, replaceTable, builder))
    }
    return CreateNewTypeWithArgs(ty, newArgs, builder)
}

public func ReplaceRawGenericArgType(ty: Type, replaceTable: HashMap<Int64, (GenericType, Type)>,
    builder: CHIRBuilder): Type {
    if (replaceTable.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        if (let Some(instTy) <- replaceTable.get(genericTy.objectId)) {
            return instTy[1]
        }
        return ty
    }
    let newArgs = ArrayList<Type>()
    for (argTy in ty.GetTypeArgs()) {
        newArgs.add(ReplaceRawGenericArgType(argTy, replaceTable, builder))
    }
    return CreateNewTypeWithArgs(ty, newArgs, builder)
}

private func ReplaceRawGenericArgType(ty: Type, genericParams: ArrayList<GenericType>,
    genericArgs: ArrayList<Type>): Type {
    if (genericParams.isEmpty() || genericArgs.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < genericArgs.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return genericArgs[idx]
            }
            idx++
        }
        return ty
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return RefType(ReplaceRawGenericArgType(refTy.GetBaseType(), genericParams, genericArgs))
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return RawArrayType(ReplaceRawGenericArgType(rawArrayTy.GetElementType(), genericParams, genericArgs),
            dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return VArrayType(ReplaceRawGenericArgType(varrayTy.GetElementType(), genericParams, genericArgs),
            varrayTy.size)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        return CPointerType(ReplaceRawGenericArgType(pointerTy.GetElementType(), genericParams, genericArgs))
    }
    if (let Some(boxTy) <- (ty as BoxType)) {
        return BoxType(ReplaceRawGenericArgType(boxTy.GetBaseType(), genericParams, genericArgs))
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        return TupleType(ReplaceRawGenericArgTypes(tupleTy.GetTypeArgs(), genericParams, genericArgs))
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        let params = ReplaceRawGenericArgTypes(funcTy.GetParamTypes(), genericParams, genericArgs)
        let retTy = ReplaceRawGenericArgType(funcTy.GetReturnType(), genericParams, genericArgs)
        return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }
    if (let Some(structTy) <- (ty as StructType)) {
        return StructType(structTy.GetStructDef(),
            ReplaceRawGenericArgTypes(structTy.GetGenericArgs(), genericParams, genericArgs))
    }
    if (let Some(classTy) <- (ty as ClassType)) {
        return ClassType(classTy.GetClassDef(),
            ReplaceRawGenericArgTypes(classTy.GetGenericArgs(), genericParams, genericArgs))
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        return EnumType(enumTy.GetEnumDef(),
            ReplaceRawGenericArgTypes(enumTy.GetGenericArgs(), genericParams, genericArgs))
    }
    return ty
}

private func ReplaceRawGenericArgTypes(values: ArrayList<Type>, genericParams: ArrayList<GenericType>,
    genericArgs: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (value in values) {
        out.add(ReplaceRawGenericArgType(value, genericParams, genericArgs))
    }
    return out
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
    private var superClassTy: Option<ClassType> = None
    private var hasSetSuperClass: Bool = false
    private let setSuperClassMtx: Mutex = Mutex()

    public init(def: ClassDef, typeArgs: ArrayList<Type>) {
        super(TypeKind.TYPE_CLASS, def, typeArgs)
    }

    public func GetClassDef(): ClassDef {
        if (let Some(classDef) <- (def as ClassDef)) {
            return classDef
        }
        throw IllegalStateException("ClassType does not reference a ClassDef")
    }

    public override func ResetAllInstantiatedType(): Unit {
        super.ResetAllInstantiatedType()
        superClassTy = None
        hasSetSuperClass = false
    }

    public func CalculateSuperClassTy(builder: CHIRBuilder): Option<ClassType> {
        let genericTypes = def.GetGenericTypeParams()
        if (!genericTypes.isEmpty()) {
            CJC_ASSERT(argTys.size == genericTypes.size)
        }
        let replaceTable = HashMap<Int64, Type>()
        var typeIdx: Int64 = 0
        while (typeIdx < genericTypes.size) {
            replaceTable[genericTypes[typeIdx].objectId] = argTys[typeIdx]
            typeIdx++
        }
        if (let Some(superTy) <- GetClassDef().GetSuperClassTy()) {
            return (ReplaceRawGenericArgType(superTy, replaceTable, builder) as ClassType).getOrThrow()
        }
        return None
    }

    public func GetSuperClassTy(builder!: Option<CHIRBuilder> = None): Option<ClassType> {
        var result: Option<ClassType> = None
        synchronized(setSuperClassMtx) {
            if (hasSetSuperClass) {
                result = superClassTy
            } else if (let Some(chirBuilder) <- builder) {
                superClassTy = CalculateSuperClassTy(chirBuilder)
                hasSetSuperClass = true
                result = superClassTy
            } else {
                result = GetClassDef().GetSuperClassTy()
            }
        }
        return result
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

private func GetSelectorType(def: EnumDef): TypeKind {
    if (!def.IsExhaustive()) {
        return TypeKind.TYPE_UINT32
    }
    if (def.IsOptionLike()) {
        return TypeKind.TYPE_BOOLEAN
    }
    return TypeKind.TYPE_UINT32
}

public func GetFieldOfType(baseTy: Type, index: UInt64, builder: CHIRBuilder): Option<Type> {
    var ty: Option<Type> = None
    if (let Some(refTy) <- (baseTy as RefType)) {
        ty = GetFieldOfType(refTy.GetBaseType(), index, builder)
    } else if (let Some(tupleTy) <- (baseTy as TupleType)) {
        if (index < UInt64(tupleTy.GetElementTypes().size)) {
            ty = tupleTy.GetElementType(Int64(index))
        }
    } else if (let Some(structTy) <- (baseTy as StructType)) {
        let memberTys = structTy.GetInstantiatedMemberTys()
        if (index < UInt64(memberTys.size)) {
            ty = memberTys[Int64(index)]
        }
    } else if (let Some(classTy) <- (baseTy as ClassType)) {
        let memberTys = classTy.GetInstantiatedMemberTys()
        if (index < UInt64(memberTys.size)) {
            ty = memberTys[Int64(index)]
        }
    } else if (let Some(enumTy) <- (baseTy as EnumType)) {
        if (index == 0u64) {
            if (GetSelectorType(enumTy.GetEnumDef()) == TypeKind.TYPE_BOOLEAN) {
                ty = builder.context.GetBoolTy()
            } else {
                ty = builder.context.GetUInt32Ty()
            }
        }
    } else if (let Some(rawArrayTy) <- (baseTy as RawArrayType)) {
        ty = rawArrayTy.GetElementType()
    }
    return ty
}
