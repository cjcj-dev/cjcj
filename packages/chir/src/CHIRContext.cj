package cjcj::chir

import std.collection.*
import std.sync.*

private func TypePtrHash(ptr: Option<Type>): Int64 {
    if (let Some(ty) <- ptr) {
        return ty.Hash()
    }
    return 0
}

private func TypePtrEqual(ptr1: Option<Type>, ptr2: Option<Type>): Bool {
    if (let None <- ptr1) {
        if (let None <- ptr2) {
            return true
        }
        return false
    }
    if (let Some(ty1) <- ptr1) {
        if (let Some(ty2) <- ptr2) {
            return ty1.IsEqual(ty2)
        }
    }
    return false
}

public class CHIRContext {
    private var curPackage: Option<Package> = None
    private var fileNameMap: HashMap<UInt32, String> = HashMap<UInt32, String>()
    private var threadsNum: UIntNative = 1
    private static let dynamicAllocatedTysMtx: Mutex = Mutex()
    private let constAllocatedTys: HashMap<Int64, ArrayList<Type>> = HashMap<Int64, ArrayList<Type>>()
    private let dynamicAllocatedTys: HashMap<Int64, ArrayList<Type>> = HashMap<Int64, ArrayList<Type>>()
    private let allocatedValues: ArrayList<Value> = ArrayList<Value>()
    private let allocatedExpressions: ArrayList<Expression> = ArrayList<Expression>()
    private let allocatedStructs: ArrayList<StructDef> = ArrayList<StructDef>()
    private let allocatedClasses: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let allocatedEnums: ArrayList<EnumDef> = ArrayList<EnumDef>()
    private let allocatedExtends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()

    private let invalidTy: BuiltinType = BuiltinType(TypeKind.TYPE_INVALID)
    private let unitTy: UnitType = UnitType()
    private let boolTy: BooleanType = BooleanType()
    private let runeTy: RuneType = RuneType()
    private let nothingTy: NothingType = NothingType()
    private let voidTy: VoidType = VoidType()
    private let cstringTy: CStringType = CStringType()
    private let int8Ty: IntType = IntType(TypeKind.TYPE_INT8)
    private let int16Ty: IntType = IntType(TypeKind.TYPE_INT16)
    private let int32Ty: IntType = IntType(TypeKind.TYPE_INT32)
    private let int64Ty: IntType = IntType(TypeKind.TYPE_INT64)
    private let intNativeTy: IntType = IntType(TypeKind.TYPE_INT_NATIVE)
    private let uint8Ty: IntType = IntType(TypeKind.TYPE_UINT8)
    private let uint16Ty: IntType = IntType(TypeKind.TYPE_UINT16)
    private let uint32Ty: IntType = IntType(TypeKind.TYPE_UINT32)
    private let uint64Ty: IntType = IntType(TypeKind.TYPE_UINT64)
    private let uintNativeTy: IntType = IntType(TypeKind.TYPE_UINT_NATIVE)
    private let float16Ty: FloatType = FloatType(TypeKind.TYPE_FLOAT16)
    private let float32Ty: FloatType = FloatType(TypeKind.TYPE_FLOAT32)
    private let float64Ty: FloatType = FloatType(TypeKind.TYPE_FLOAT64)
    private var objectTy: Option<ClassType> = None
    private var anyTy: Option<ClassType> = None

    public init() {
        RegisterBuiltin(invalidTy)
        RegisterBuiltin(unitTy)
        RegisterBuiltin(boolTy)
        RegisterBuiltin(runeTy)
        RegisterBuiltin(nothingTy)
        RegisterBuiltin(voidTy)
        RegisterBuiltin(cstringTy)
        RegisterBuiltin(int8Ty)
        RegisterBuiltin(int16Ty)
        RegisterBuiltin(int32Ty)
        RegisterBuiltin(int64Ty)
        RegisterBuiltin(intNativeTy)
        RegisterBuiltin(uint8Ty)
        RegisterBuiltin(uint16Ty)
        RegisterBuiltin(uint32Ty)
        RegisterBuiltin(uint64Ty)
        RegisterBuiltin(uintNativeTy)
        RegisterBuiltin(float16Ty)
        RegisterBuiltin(float32Ty)
        RegisterBuiltin(float64Ty)
    }

    private func RegisterBuiltin(ty: Type): Unit {
        let _ = GetType(TypePtrHash(Some(ty)), { allocatedTy: Type =>
            TypePtrEqual(Some(allocatedTy), Some(ty))
        }, { => ty })
    }

    private func GetType(hashValue: Int64, typeEqual: (Type) -> Bool, createType: () -> Type): Type {
        if (let Some(bucket) <- constAllocatedTys.get(hashValue)) {
            for (allocatedTy in bucket) {
                if (typeEqual(allocatedTy)) {
                    return allocatedTy
                }
            }
        }
        synchronized(CHIRContext.dynamicAllocatedTysMtx) {
            if (let Some(bucket) <- dynamicAllocatedTys.get(hashValue)) {
                for (allocatedTy in bucket) {
                    if (typeEqual(allocatedTy)) {
                        return allocatedTy
                    }
                }
            }
            let ty = createType()
            let tyHash = TypePtrHash(Some(ty))
            if (let Some(bucket) <- dynamicAllocatedTys.get(tyHash)) {
                bucket.add(ty)
            } else {
                let bucket = ArrayList<Type>()
                bucket.add(ty)
                dynamicAllocatedTys[tyHash] = bucket
            }
            return ty
        }
        throw IllegalStateException("unreachable CHIRContext.GetType")
    }

    public func MergeTypes(): Unit {
        // GAP_TODO: C++ CHIR.cpp:520/:564 and include/cangjie/Utils/ParallelUtil.h:71
        // merge per-thread CHIRBuilder contexts after parallel translation/optimization.
        // Selfhost currently has a single CHIRContext and no corresponding sub-builder merge points.
        synchronized(CHIRContext.dynamicAllocatedTysMtx) {
            for ((_, bucket) in dynamicAllocatedTys) {
                for (ty in bucket) {
                    let tyHash = TypePtrHash(Some(ty))
                    if (let Some(constBucket) <- constAllocatedTys.get(tyHash)) {
                        var found = false
                        for (allocatedTy in constBucket) {
                            if (TypePtrEqual(Some(allocatedTy), Some(ty))) {
                                found = true
                                break
                            }
                        }
                        if (!found) {
                            constBucket.add(ty)
                        }
                    } else {
                        let constBucket = ArrayList<Type>()
                        constBucket.add(ty)
                        constAllocatedTys[tyHash] = constBucket
                    }
                }
            }
            dynamicAllocatedTys.clear()
        }
    }

    public func GetCurPackage(): Option<Package> {
        return curPackage
    }

    public func SetCurPackage(pkg: Package): Unit {
        curPackage = pkg
    }

    public func RegisterSourceFileName(fileId: UInt32, fileName: String): Unit {
        fileNameMap[fileId] = fileName
    }

    public func GetSourceFileName(fileId: UInt32): String {
        return fileNameMap.get(fileId) ?? INVALID_NAME
    }

    public func GetFileNameMap(): HashMap<UInt32, String> {
        return fileNameMap
    }

    public func SetFileNameMap(fnMap: HashMap<UInt32, String>): Unit {
        fileNameMap = fnMap
    }

    public func SetThreadNum(num: UIntNative): Unit {
        threadsNum = num
    }

    public func GetInvalidTy(): Type { return invalidTy }
    public func GetNothingType(): NothingType { return nothingTy }
    public func GetUnitTy(): UnitType { return unitTy }
    public func GetBoolTy(): BooleanType { return boolTy }
    public func GetRuneTy(): RuneType { return runeTy }
    public func GetInt8Ty(): IntType { return int8Ty }
    public func GetInt16Ty(): IntType { return int16Ty }
    public func GetInt32Ty(): IntType { return int32Ty }
    public func GetInt64Ty(): IntType { return int64Ty }
    public func GetIntNativeTy(): IntType { return intNativeTy }
    public func GetUInt8Ty(): IntType { return uint8Ty }
    public func GetUInt16Ty(): IntType { return uint16Ty }
    public func GetUInt32Ty(): IntType { return uint32Ty }
    public func GetUInt64Ty(): IntType { return uint64Ty }
    public func GetUIntNativeTy(): IntType { return uintNativeTy }
    public func GetFloat16Ty(): FloatType { return float16Ty }
    public func GetFloat32Ty(): FloatType { return float32Ty }
    public func GetFloat64Ty(): FloatType { return float64Ty }
    public func GetCStringTy(): CStringType { return cstringTy }
    public func GetVoidTy(): VoidType { return voidTy }

    public func GetStringTy(): Option<StructType> {
        if (let Some(pkg) <- curPackage) {
            if (let Some(def) <- pkg.TryGetStructDef("String")) {
                if (def.GetPackageName() == "std.core") {
                    return GetStructTy(def, ArrayList<Type>())
                }
            }
            for (def in pkg.GetAllStructDef()) {
                if (def.GetPackageName() == "std.core" && def.GetIdentifier() == "String") {
                    return GetStructTy(def, ArrayList<Type>())
                }
            }
        }
        return None
    }

    public func SetObjectTy(ty: ClassType): Unit {
        objectTy = ty
    }

    public func GetObjectTy(): Option<ClassType> {
        return objectTy
    }

    public func SetAnyTy(ty: ClassType): Unit {
        anyTy = ty
    }

    public func GetAnyTy(): Option<ClassType> {
        return anyTy
    }

    public func GetTupleTy(fieldTys: ArrayList<Type>): TupleType {
        var hashValue = HashArgTypes(fieldTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_TUPLE)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(tupleTy) <- (allocatedTy as TupleType)) {
                return TypeArgsAreEqual(tupleTy.argTys, fieldTys)
            }
            return false
        }, { => TupleType(fieldTys) })
        return (ty as TupleType).getOrThrow()
    }

    public func GetFuncTy(paramTys: ArrayList<Type>, retTy: Type, hasVarLenParam!: Bool = false,
        isCFunc!: Bool = false): FuncType {
        let argTys = paramTys.clone()
        argTys.add(retTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, isCFunc)
        hashValue = HashValue(hashValue, hasVarLenParam)
        hashValue = HashValue(hashValue, TypeKind.TYPE_FUNC)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(funcTy) <- (allocatedTy as FuncType)) {
                return TypeArgsAreEqual(funcTy.argTys, argTys) && funcTy.IsCFunc() == isCFunc &&
                    funcTy.HasVarArg() == hasVarLenParam
            }
            return false
        }, { => FuncType(paramTys, retTy, hasVarLenParam: hasVarLenParam, isCFunc: isCFunc) })
        return (ty as FuncType).getOrThrow()
    }

    public func GetRawArrayTy(elementTy: Type, dims!: UInt64 = 1u64): RawArrayType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, dims)
        hashValue = HashValue(hashValue, TypeKind.TYPE_RAWARRAY)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(rawArrayTy) <- (allocatedTy as RawArrayType)) {
                return TypeArgsAreEqual(rawArrayTy.argTys, argTys) && rawArrayTy.GetDims() == dims
            }
            return false
        }, { => RawArrayType(elementTy, dims: dims) })
        return (ty as RawArrayType).getOrThrow()
    }

    public func GetCPointerTy(elementTy: Type): CPointerType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_CPOINTER)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(pointerTy) <- (allocatedTy as CPointerType)) {
                return TypeArgsAreEqual(pointerTy.argTys, argTys)
            }
            return false
        }, { => CPointerType(elementTy) })
        return (ty as CPointerType).getOrThrow()
    }

    public func GetVArrayTy(elementTy: Type, size: UInt64): VArrayType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, size)
        hashValue = HashValue(hashValue, TypeKind.TYPE_VARRAY)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(varrayTy) <- (allocatedTy as VArrayType)) {
                return TypeArgsAreEqual(varrayTy.argTys, argTys) && varrayTy.size == size
            }
            return false
        }, { => VArrayType(elementTy, size) })
        return (ty as VArrayType).getOrThrow()
    }

    public func GetRefTy(baseTy: Type): RefType {
        let argTys = ArrayList<Type>()
        argTys.add(baseTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_REFTYPE)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(refTy) <- (allocatedTy as RefType)) {
                return TypeArgsAreEqual(refTy.argTys, argTys)
            }
            return false
        }, { => RefType(baseTy) })
        return (ty as RefType).getOrThrow()
    }

    public func GetBoxTy(baseTy: Type): BoxType {
        let argTys = ArrayList<Type>()
        argTys.add(baseTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_BOXTYPE)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(boxTy) <- (allocatedTy as BoxType)) {
                return TypeArgsAreEqual(boxTy.argTys, argTys)
            }
            return false
        }, { => BoxType(baseTy) })
        return (ty as BoxType).getOrThrow()
    }

    public func GetThisTy(): ThisType {
        let hashValue = HashValue(HashArgTypes(ArrayList<Type>()), TypeKind.TYPE_THIS)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            return allocatedTy.IsThis()
        }, { => ThisType() })
        return (ty as ThisType).getOrThrow()
    }

    public func GetGenericTy(name: String): GenericType {
        return GetGenericTy(name, name)
    }

    public func GetGenericTy(name: String, srcCodeIdentifier: String): GenericType {
        var hashValue: Int64 = 0
        hashValue = HashValue(hashValue, name)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(genericTy) <- (allocatedTy as GenericType)) {
                return genericTy.GetIdentifier() == name
            }
            return false
        }, { => GenericType(name, srcCodeIdentifier) })
        return (ty as GenericType).getOrThrow()
    }

    public func GetStructTy(def: StructDef, args: ArrayList<Type>): StructType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(structTy) <- (allocatedTy as StructType)) {
                return TypeArgsAreEqual(structTy.argTys, args) && refEq(structTy.GetStructDef(), def)
            }
            return false
        }, { => StructType(def, args) })
        return (ty as StructType).getOrThrow()
    }

    public func GetClassTy(def: ClassDef, args: ArrayList<Type>): ClassType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(classTy) <- (allocatedTy as ClassType)) {
                return TypeArgsAreEqual(classTy.argTys, args) && refEq(classTy.GetClassDef(), def)
            }
            return false
        }, { => ClassType(def, args) })
        return (ty as ClassType).getOrThrow()
    }

    public func GetEnumTy(def: EnumDef, args: ArrayList<Type>): EnumType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(enumTy) <- (allocatedTy as EnumType)) {
                return TypeArgsAreEqual(enumTy.argTys, args) && refEq(enumTy.GetEnumDef(), def)
            }
            return false
        }, { => EnumType(def, args) })
        return (ty as EnumType).getOrThrow()
    }

    public func ToSelectorType(kind: TypeKind): Type {
        return match (kind) {
            case TypeKind.TYPE_UINT32 => uint32Ty
            case _ => boolTy
        }
    }

    public func RegisterValue(value: Value): Unit {
        allocatedValues.add(value)
    }

    public func RegisterExpression(expr: Expression): Unit {
        expr.ConnectOperandsAndGroups()
        allocatedExpressions.add(expr)
    }

    public func RegisterStruct(def: StructDef): Unit {
        allocatedStructs.add(def)
    }

    public func RegisterClass(def: ClassDef): Unit {
        allocatedClasses.add(def)
    }

    public func RegisterEnum(def: EnumDef): Unit {
        allocatedEnums.add(def)
    }

    public func RegisterExtend(def: ExtendDef): Unit {
        allocatedExtends.add(def)
    }

    public func GetAllocatedValues(): ArrayList<Value> {
        return allocatedValues
    }

    public func GetAllocatedExpressions(): ArrayList<Expression> {
        return allocatedExpressions
    }

    public func GetTypesNum(): Int64 {
        var count: Int64 = 0
        for ((_, bucket) in dynamicAllocatedTys) {
            count += bucket.size
        }
        return count
    }

    public func GetAllNodesNum(): Int64 {
        return allocatedValues.size + allocatedExpressions.size + allocatedStructs.size + allocatedClasses.size +
            allocatedEnums.size + allocatedExtends.size
    }

    public func FreeWholePackage(): Unit {
        curPackage = None
        allocatedValues.clear()
        allocatedExpressions.clear()
        allocatedStructs.clear()
        allocatedClasses.clear()
        allocatedEnums.clear()
        allocatedExtends.clear()
    }
}
