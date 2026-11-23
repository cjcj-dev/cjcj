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
    public let constAllocatedTys: HashMap<Int64, ArrayList<Type>> = HashMap<Int64, ArrayList<Type>>()
    public let dynamicAllocatedTys: HashMap<Int64, ArrayList<Type>> = HashMap<Int64, ArrayList<Type>>()
    private let allocatedValues: ArrayList<Value> = ArrayList<Value>()
    private let allocatedExpressions: ArrayList<Expression> = ArrayList<Expression>()
    private let allocatedStructs: ArrayList<StructDef> = ArrayList<StructDef>()
    private let allocatedClasses: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let allocatedEnums: ArrayList<EnumDef> = ArrayList<EnumDef>()
    private let allocatedExtends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()
    private let allocatedPtrInFuncOrLambda: HashMap<Int64, ArrayList<Base>> = HashMap<Int64, ArrayList<Base>>()

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
        Init()
    }

    public func Init(): Unit {
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
        // C++ CHIRContext.cpp:249-252 merges dynamic types into the stable set. The parallel range-propagation
        // call site is ported at CodeGenBridge.cj:307-332; serial constant propagation is performance-equivalent.
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

    public func SearchObjectTyInPackage(): Option<ClassType> {
        let pkg = curPackage.getOrThrow()
        for (classDef in pkg.GetImportedClasses()) {
            if (IsCoreObject(classDef)) {
                return classDef.GetType().getOrThrow() as ClassType
            }
        }
        for (classDef in pkg.GetClasses()) {
            if (IsCoreObject(classDef)) {
                return classDef.GetType().getOrThrow() as ClassType
            }
        }
        return None
    }

    public func SearchAnyTyInPackage(): Option<ClassType> {
        let pkg = curPackage.getOrThrow()
        for (classDef in pkg.GetImportedClasses()) {
            if (IsCoreAny(classDef)) {
                return classDef.GetType().getOrThrow() as ClassType
            }
        }
        for (classDef in pkg.GetClasses()) {
            if (IsCoreAny(classDef)) {
                return classDef.GetType().getOrThrow() as ClassType
            }
        }
        return None
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
        return GetStructType("std.core", "String")
    }

    public func GetStructType(packageName: String, name: String,
        genericType!: ArrayList<String> = ArrayList<String>()): Option<StructType> {
        let pkg = curPackage.getOrThrow()
        for (def in pkg.GetAllStructDef()) {
            if (def.GetPackageName() != packageName || def.GetSrcCodeIdentifier() != name) {
                continue
            }
            if (def.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            let structType = (def.GetType().getOrThrow() as StructType).getOrThrow()
            let argTypes = structType.GetGenericArgs()
            var idx: Int64 = 0
            var equal = true
            while (idx < genericType.size) {
                if (genericType[idx] != argTypes[idx].ToString()) {
                    equal = false
                    break
                }
                idx++
            }
            if (equal) {
                return structType
            }
        }
        return None
    }

    public func SetObjectTy(ty: Option<ClassType>): Unit {
        objectTy = ty
    }

    public func GetObjectTy(): Option<ClassType> {
        return objectTy
    }

    public func SetAnyTy(ty: Option<ClassType>): Unit {
        anyTy = ty
    }

    public func GetAnyTy(): Option<ClassType> {
        return anyTy
    }

    public func GetTupleTy(fieldTys: ArrayList<Type>, modal!: ModalInfo = ModalInfo()): TupleType {
        var hashValue = HashArgTypes(fieldTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_TUPLE)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(tupleTy) <- (allocatedTy as TupleType)) {
                return TypeArgsAreEqual(tupleTy.argTys, fieldTys) && tupleTy.modal == modal
            }
            return false
        }, { => TupleType(fieldTys, modal: modal) })
        return (ty as TupleType).getOrThrow()
    }

    public func GetFuncTy(paramTys: ArrayList<Type>, retTy: Type, hasVarLenParam!: Bool = false,
        isCFunc!: Bool = false, modal!: ModalInfo = ModalInfo()): FuncType {
        let argTys = paramTys.clone()
        argTys.add(retTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, isCFunc)
        hashValue = HashValue(hashValue, hasVarLenParam)
        hashValue = HashValue(hashValue, TypeKind.TYPE_FUNC)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(funcTy) <- (allocatedTy as FuncType)) {
                return TypeArgsAreEqual(funcTy.argTys, argTys) && funcTy.IsCFunc() == isCFunc &&
                    funcTy.HasVarArg() == hasVarLenParam && funcTy.modal == modal
            }
            return false
        }, { => FuncType(paramTys, retTy, hasVarLenParam: hasVarLenParam, isCFunc: isCFunc, modal: modal) })
        return (ty as FuncType).getOrThrow()
    }

    public func GetRawArrayTy(elementTy: Type, dims!: UInt64 = 1u64, modal!: ModalInfo = ModalInfo()): RawArrayType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, dims)
        hashValue = HashValue(hashValue, TypeKind.TYPE_RAWARRAY)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(rawArrayTy) <- (allocatedTy as RawArrayType)) {
                return TypeArgsAreEqual(rawArrayTy.argTys, argTys) && rawArrayTy.GetDims() == dims &&
                    rawArrayTy.modal == modal
            }
            return false
        }, { => RawArrayType(elementTy, dims: dims, modal: modal) })
        return (ty as RawArrayType).getOrThrow()
    }

    public func GetCPointerTy(elementTy: Type, modal!: ModalInfo = ModalInfo()): CPointerType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, TypeKind.TYPE_CPOINTER)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(pointerTy) <- (allocatedTy as CPointerType)) {
                return TypeArgsAreEqual(pointerTy.argTys, argTys) && pointerTy.modal == modal
            }
            return false
        }, { => CPointerType(elementTy, modal: modal) })
        return (ty as CPointerType).getOrThrow()
    }

    public func GetVArrayTy(elementTy: Type, size: UInt64, modal!: ModalInfo = ModalInfo()): VArrayType {
        let argTys = ArrayList<Type>()
        argTys.add(elementTy)
        var hashValue = HashArgTypes(argTys)
        hashValue = HashValue(hashValue, size)
        hashValue = HashValue(hashValue, TypeKind.TYPE_VARRAY)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(varrayTy) <- (allocatedTy as VArrayType)) {
                return TypeArgsAreEqual(varrayTy.argTys, argTys) && varrayTy.size == size && varrayTy.modal == modal
            }
            return false
        }, { => VArrayType(elementTy, size, modal: modal) })
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

    public func GetThisTy(modal!: ModalInfo = ModalInfo()): ThisType {
        let hashValue = HashModal(HashValue(HashArgTypes(ArrayList<Type>()), TypeKind.TYPE_THIS), modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            return allocatedTy.IsThis() && allocatedTy.modal == modal
        }, { => ThisType(modal: modal) })
        return (ty as ThisType).getOrThrow()
    }

    public func GetGenericTy(name: String): GenericType {
        return GetGenericTy(name, name)
    }

    public func GetGenericTy(name: String, srcCodeIdentifier: String, modal!: ModalInfo = ModalInfo()): GenericType {
        var hashValue: Int64 = 0
        hashValue = HashModal(HashValue(hashValue, name), modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(genericTy) <- (allocatedTy as GenericType)) {
                return genericTy.GetIdentifier() == name && genericTy.modal == modal
            }
            return false
        }, { => GenericType(name, srcCodeIdentifier, modal: modal) })
        return (ty as GenericType).getOrThrow()
    }

    public func GetStructTy(def: StructDef, args: ArrayList<Type>, modal!: ModalInfo = ModalInfo()): StructType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(structTy) <- (allocatedTy as StructType)) {
                return TypeArgsAreEqual(structTy.argTys, args) && refEq(structTy.GetStructDef(), def) &&
                    structTy.modal == modal
            }
            return false
        }, { => StructType(def, args, modal: modal) })
        return (ty as StructType).getOrThrow()
    }

    public func GetClassTy(def: ClassDef, args: ArrayList<Type>, modal!: ModalInfo = ModalInfo()): ClassType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(classTy) <- (allocatedTy as ClassType)) {
                return TypeArgsAreEqual(classTy.argTys, args) && refEq(classTy.GetClassDef(), def) &&
                    classTy.modal == modal
            }
            return false
        }, { => ClassType(def, args, modal: modal) })
        return (ty as ClassType).getOrThrow()
    }

    public func GetEnumTy(def: EnumDef, args: ArrayList<Type>, modal!: ModalInfo = ModalInfo()): EnumType {
        var hashValue = HashArgTypes(args)
        hashValue = HashValue(hashValue, def.nodeId)
        hashValue = HashModal(hashValue, modal)
        let ty = GetType(hashValue, { allocatedTy: Type =>
            if (let Some(enumTy) <- (allocatedTy as EnumType)) {
                return TypeArgsAreEqual(enumTy.argTys, args) && refEq(enumTy.GetEnumDef(), def) &&
                    enumTy.modal == modal
            }
            return false
        }, { => EnumType(def, args, modal: modal) })
        return (ty as EnumType).getOrThrow()
    }

    // Interns a modal variant of a builtin scalar; NONE keeps the context singletons.
    private func GetBuiltinTy(kind: TypeKind, modal: ModalInfo): Type {
        if (modal.local == CHIRMode.NONE) {
            return match (kind) {
                case TypeKind.TYPE_INT8 => int8Ty
                case TypeKind.TYPE_INT16 => int16Ty
                case TypeKind.TYPE_INT32 => int32Ty
                case TypeKind.TYPE_INT64 => int64Ty
                case TypeKind.TYPE_INT_NATIVE => intNativeTy
                case TypeKind.TYPE_UINT8 => uint8Ty
                case TypeKind.TYPE_UINT16 => uint16Ty
                case TypeKind.TYPE_UINT32 => uint32Ty
                case TypeKind.TYPE_UINT64 => uint64Ty
                case TypeKind.TYPE_UINT_NATIVE => uintNativeTy
                case TypeKind.TYPE_FLOAT16 => float16Ty
                case TypeKind.TYPE_FLOAT32 => float32Ty
                case TypeKind.TYPE_FLOAT64 => float64Ty
                case TypeKind.TYPE_RUNE => runeTy
                case TypeKind.TYPE_BOOLEAN => boolTy
                case TypeKind.TYPE_UNIT => unitTy
                case TypeKind.TYPE_NOTHING => nothingTy
                case TypeKind.TYPE_VOID => voidTy
                case TypeKind.TYPE_CSTRING => cstringTy
                case _ => throw IllegalStateException("CHIRContext.GetBuiltinTy: not a builtin scalar kind")
            }
        }
        var hashValue = HashArgTypes(ArrayList<Type>())
        hashValue = HashValue(hashValue, kind)
        hashValue = HashModal(hashValue, modal)
        return GetType(hashValue, { allocatedTy: Type =>
            return allocatedTy.kind == kind && allocatedTy.argTys.isEmpty() && allocatedTy.modal == modal
        }, { =>
            let created: Type = match (kind) {
                case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                    TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                    TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE => IntType(kind, modal: modal)
                case TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 => FloatType(kind, modal: modal)
                case TypeKind.TYPE_RUNE => RuneType(modal: modal)
                case TypeKind.TYPE_BOOLEAN => BooleanType(modal: modal)
                case TypeKind.TYPE_UNIT => UnitType(modal: modal)
                case TypeKind.TYPE_NOTHING => NothingType(modal: modal)
                case TypeKind.TYPE_VOID => VoidType(modal: modal)
                case TypeKind.TYPE_CSTRING => CStringType(modal: modal)
                case _ => throw IllegalStateException("CHIRContext.GetBuiltinTy: not a builtin scalar kind")
            }
            return created
        })
    }

    // Official CHIRContext::WithModal / WithModalImpl (CHIRContext.cpp @63bf237b): re-interns `ty` with
    // `modal` on its outermost data type; Ref and Box wrappers are looked through and preserved.
    public func WithModal(ty: Type, modal: ModalInfo): Type {
        if (!ty.IsRef() && !ty.IsBox() && ty.modal == modal) { return ty }
        return WithModalImpl(ty, modal, HashMap<Int64, GenericType>())
    }

    private func WithModalImpl(ty: Type, modal: ModalInfo, memo: HashMap<Int64, GenericType>): Type {
        if (let Some(refTy) <- (ty as RefType)) {
            return GetRefTy(WithModalImpl(refTy.GetBaseType(), modal, memo))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return GetBoxTy(WithModalImpl(boxTy.GetBaseType(), modal, memo))
        }
        if (modal == ty.modal) {
            return ty
        }
        return match (ty.kind) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 |
                TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_RUNE | TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_UNIT |
                TypeKind.TYPE_NOTHING | TypeKind.TYPE_VOID | TypeKind.TYPE_CSTRING => GetBuiltinTy(ty.kind, modal)
            case TypeKind.TYPE_TUPLE => GetTupleTy((ty as TupleType).getOrThrow().GetElementTypes(), modal: modal)
            case TypeKind.TYPE_FUNC =>
                let funcTy = (ty as FuncType).getOrThrow()
                GetFuncTy(funcTy.GetParamTypes(), funcTy.GetReturnType(), hasVarLenParam: funcTy.HasVarArg(),
                    isCFunc: funcTy.IsCFunc(), modal: modal)
            case TypeKind.TYPE_STRUCT =>
                let structTy = (ty as StructType).getOrThrow()
                GetStructTy(structTy.GetStructDef(), structTy.GetTypeArgs(), modal: modal)
            case TypeKind.TYPE_ENUM =>
                let enumTy = (ty as EnumType).getOrThrow()
                GetEnumTy(enumTy.GetEnumDef(), enumTy.GetTypeArgs(), modal: modal)
            case TypeKind.TYPE_CLASS =>
                let classTy = (ty as ClassType).getOrThrow()
                GetClassTy(classTy.GetClassDef(), classTy.GetTypeArgs(), modal: modal)
            case TypeKind.TYPE_RAWARRAY =>
                let rawArrayTy = (ty as RawArrayType).getOrThrow()
                GetRawArrayTy(rawArrayTy.GetElementType(), dims: rawArrayTy.GetDims(), modal: modal)
            case TypeKind.TYPE_VARRAY =>
                let varrayTy = (ty as VArrayType).getOrThrow()
                GetVArrayTy(varrayTy.GetElementType(), varrayTy.GetSize(), modal: modal)
            case TypeKind.TYPE_CPOINTER =>
                GetCPointerTy((ty as CPointerType).getOrThrow().GetElementType(), modal: modal)
            case TypeKind.TYPE_THIS => GetThisTy(modal: modal)
            case TypeKind.TYPE_GENERIC =>
                let src = (ty as GenericType).getOrThrow()
                if (let Some(visited) <- memo.get(src.objectId)) { return visited }
                let dst = GetGenericTy(src.GetIdentifier(), src.GetSrcCodeIdentifier(), modal: modal)
                memo[src.objectId] = dst
                let bounds = ArrayList<Type>()
                for (bound in src.GetUpperBounds()) { bounds.add(WithModalImpl(bound, modal, memo)) }
                dst.SetUpperBounds(bounds)
                dst
            case _ => throw IllegalStateException("CHIRContext.WithModal: no modal CHIR identity for ${ty.ToString()}")
        }
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

    public func GetAllocatedStructs(): ArrayList<StructDef> {
        return allocatedStructs
    }

    public func GetAllocatedClasses(): ArrayList<ClassDef> {
        return allocatedClasses
    }

    public func GetAllocatedEnums(): ArrayList<EnumDef> {
        return allocatedEnums
    }

    public func GetAllocatedExtends(): ArrayList<ExtendDef> {
        return allocatedExtends
    }

    public func GetTypesNum(): Int64 {
        var count: Int64 = 0
        for ((_, bucket) in dynamicAllocatedTys) {
            count += bucket.size
        }
        return count
    }

    public func GetAllNodesNum(): Int64 {
        var count = allocatedValues.size + allocatedExpressions.size + allocatedStructs.size + allocatedClasses.size +
            allocatedEnums.size + allocatedExtends.size
        for ((_, ptrs) in allocatedPtrInFuncOrLambda) {
            count += ptrs.size + 1
        }
        return count
    }

    public func MergeAllocatedPtrInFuncOrLambda(input: HashMap<Int64, ArrayList<Base>>): Unit {
        for ((blockGroupId, ptrs) in input) {
            if (let Some(allocatedPtrs) <- allocatedPtrInFuncOrLambda.get(blockGroupId)) {
                allocatedPtrs.add(all: ptrs)
            } else {
                allocatedPtrInFuncOrLambda[blockGroupId] = ptrs.clone()
            }
        }
    }

    public func FreeMemoryInFunc(funcBody: BlockGroup): Unit {
        if (let Some(ptrs) <- allocatedPtrInFuncOrLambda.get(funcBody.nodeId)) {
            for (ptr in ptrs) {
                if (let Some(expr) <- (ptr as Expression)) {
                    expr.RemoveSelfFromBlock()
                }
            }
            ptrs.clear()
        }
    }

    public func FreeWholePackage(): Unit {
        curPackage = None
        allocatedValues.clear()
        allocatedExpressions.clear()
        allocatedStructs.clear()
        allocatedClasses.clear()
        allocatedEnums.clear()
        allocatedExtends.clear()
        allocatedPtrInFuncOrLambda.clear()
    }
}
