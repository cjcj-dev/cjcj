package cangjie_compiler::chir

import std.collection.*

public class CHIRContext {
    private var curPackage: Option<Package> = None
    private var fileNameMap: HashMap<UInt32, String> = HashMap<UInt32, String>()
    private var threadsNum: UIntNative = 1
    private let typeCache: HashMap<String, Type> = HashMap<String, Type>()
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
        typeCache[ty.ToString()] = ty
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
        let key = "tuple:" + TypeVecToString("", fieldTys, "", delimiter: ",")
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as TupleType)) {
                return found
            }
        }
        let ty = TupleType(fieldTys)
        typeCache[key] = ty
        return ty
    }

    public func GetFuncTy(paramTys: ArrayList<Type>, retTy: Type, hasVarLenParam!: Bool = false,
        isCFunc!: Bool = false): FuncType {
        let key = "func:${hasVarLenParam}:${isCFunc}:" + TypeVecToString("", paramTys, "", delimiter: ",") + "->" + retTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as FuncType)) {
                return found
            }
        }
        let ty = FuncType(paramTys, retTy, hasVarLenParam: hasVarLenParam, isCFunc: isCFunc)
        typeCache[key] = ty
        return ty
    }

    public func GetRawArrayTy(elementTy: Type, dims!: UInt64 = 1u64): RawArrayType {
        let key = "rawarray:${dims}:" + elementTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as RawArrayType)) {
                return found
            }
        }
        let ty = RawArrayType(elementTy, dims: dims)
        typeCache[key] = ty
        return ty
    }

    public func GetCPointerTy(elementTy: Type): CPointerType {
        let key = "cpointer:" + elementTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as CPointerType)) {
                return found
            }
        }
        let ty = CPointerType(elementTy)
        typeCache[key] = ty
        return ty
    }

    public func GetVArrayTy(elementTy: Type, size: UInt64): VArrayType {
        let key = "varray:${size}:" + elementTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as VArrayType)) {
                return found
            }
        }
        let ty = VArrayType(elementTy, size)
        typeCache[key] = ty
        return ty
    }

    public func GetRefTy(baseTy: Type): RefType {
        let key = "ref:" + baseTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as RefType)) {
                return found
            }
        }
        let ty = RefType(baseTy)
        typeCache[key] = ty
        return ty
    }

    public func GetBoxTy(baseTy: Type): BoxType {
        let key = "box:" + baseTy.ToString()
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as BoxType)) {
                return found
            }
        }
        let ty = BoxType(baseTy)
        typeCache[key] = ty
        return ty
    }

    public func GetGenericTy(name: String): GenericType {
        return GetGenericTy(name, name)
    }

    public func GetGenericTy(name: String, srcCodeIdentifier: String): GenericType {
        let key = "generic:" + name
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as GenericType)) {
                return found
            }
        }
        let ty = GenericType(name, srcCodeIdentifier)
        typeCache[key] = ty
        return ty
    }

    public func GetStructTy(def: StructDef, args: ArrayList<Type>): StructType {
        let key = "struct:" + def.GetFullName() + "<" + TypeVecToString("", args, "", delimiter: ",") + ">"
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as StructType)) {
                return found
            }
        }
        let ty = StructType(def, args)
        def.SetType(ty)
        typeCache[key] = ty
        return ty
    }

    public func GetClassTy(def: ClassDef, args: ArrayList<Type>): ClassType {
        let key = "class:" + def.GetFullName() + "<" + TypeVecToString("", args, "", delimiter: ",") + ">"
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as ClassType)) {
                return found
            }
        }
        let ty = ClassType(def, args)
        def.SetType(ty)
        typeCache[key] = ty
        return ty
    }

    public func GetEnumTy(def: EnumDef, args: ArrayList<Type>): EnumType {
        let key = "enum:" + def.GetFullName() + "<" + TypeVecToString("", args, "", delimiter: ",") + ">"
        if (let Some(cached) <- typeCache.get(key)) {
            if (let Some(found) <- (cached as EnumType)) {
                return found
            }
        }
        let ty = EnumType(def, args)
        def.SetType(ty)
        typeCache[key] = ty
        return ty
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
        return typeCache.size
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
