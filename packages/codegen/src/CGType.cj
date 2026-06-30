package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.Value
import cangjie_compiler::mangle.GetCustomTypeIdentifier
import cangjie_compiler::utils.CJC_ASSERT

public enum CGTypeKind {
    | OTHERS
    | CG_PRIMITIVE
    | CG_FUNCTION
    | CG_ENUM
    | CG_CLASS
    | CG_REF
    | CG_TI
}

public func CGTypeKindIndex(kind: CGTypeKind): Int64 {
    return match (kind) {
        case CGTypeKind.OTHERS => 0
        case CGTypeKind.CG_PRIMITIVE => 1
        case CGTypeKind.CG_FUNCTION => 2
        case CGTypeKind.CG_ENUM => 3
        case CGTypeKind.CG_CLASS => 4
        case CGTypeKind.CG_REF => 5
        case CGTypeKind.CG_TI => 6
    }
}

extend CGTypeKind <: Equatable<CGTypeKind> {
    public operator func ==(right: CGTypeKind): Bool { return CGTypeKindIndex(this) == CGTypeKindIndex(right) }
    public operator func !=(right: CGTypeKind): Bool { return !(this == right) }
}

public enum CGGenericKind {
    | UNKNOWN
    | STATIC_GI
    | DYNAMIC_GI
    | CONCRETE
}

private func CGGenericKindIndex(kind: CGGenericKind): Int64 {
    return match (kind) {
        case CGGenericKind.UNKNOWN => 0
        case CGGenericKind.STATIC_GI => 1
        case CGGenericKind.DYNAMIC_GI => 2
        case CGGenericKind.CONCRETE => 3
    }
}

extend CGGenericKind <: Equatable<CGGenericKind> {
    public operator func ==(right: CGGenericKind): Bool {
        return CGGenericKindIndex(this) == CGGenericKindIndex(right)
    }

    public operator func !=(right: CGGenericKind): Bool {
        return !(this == right)
    }
}

public func ContainsGenericType(ty: Type): Bool {
    if (ty.IsGeneric()) {
        return true
    }
    for (argTy in ty.GetTypeArgs()) {
        if (ContainsGenericType(argTy)) {
            return true
        }
    }
    return false
}

private func HasGenericTypeArg(ty: Type): Bool {
    if (ty.IsGeneric() || ty.IsThis()) {
        return true
    }
    for (argTy in ty.GetTypeArgs()) {
        if (HasGenericTypeArg(argTy)) {
            return true
        }
    }
    return false
}

public class TypeExtraInfo {
    public var addrspace: UInt32 = 0u32
    public var isMethod: Bool = false
    public var isStaticMethod: Bool = false
    public var allowBasePtr: Bool = true
    public var forWrapper: Bool = false
    public let instantiatedParamTypes: ArrayList<Type> = ArrayList<Type>()

    public init() {}

    public init(addrspace: UInt32) {
        this.addrspace = addrspace
    }

    public init(addrspace: UInt32, isMethod: Bool, isStaticMethod: Bool, allowBasePtr: Bool,
        instantiatedParamTypes: ArrayList<Type>) {
        this.addrspace = addrspace
        this.isMethod = isMethod
        this.isStaticMethod = isStaticMethod
        this.allowBasePtr = allowBasePtr
        for (ty in instantiatedParamTypes) {
            this.instantiatedParamTypes.add(ty)
        }
    }

    public operator func ==(rhs: TypeExtraInfo): Bool {
        if (instantiatedParamTypes.size != rhs.instantiatedParamTypes.size || addrspace != rhs.addrspace ||
            isMethod != rhs.isMethod || isStaticMethod != rhs.isStaticMethod || allowBasePtr != rhs.allowBasePtr ||
            forWrapper != rhs.forWrapper) {
            return false
        }
        var idx: Int64 = 0
        while (idx < instantiatedParamTypes.size) {
            if (!refEq(instantiatedParamTypes[idx], rhs.instantiatedParamTypes[idx])) {
                return false
            }
            idx++
        }
        return true
    }
}

public open class CGType {
    protected let cgMod: CGModule
    protected let cgCtx: CGContext
    protected let chirType: Type
    protected var llvmType: Option<LLVMTypeRef> = None
    protected var layoutType: Option<LLVMTypeRef> = None
    protected let containedCGTypes: ArrayList<CGType> = ArrayList<CGType>()
    protected var cgTypeKind: CGTypeKind
    protected var addrspace: UInt32 = 0u32
    protected var size: Option<Int64> = None
    protected var align: Option<Int64> = None
    private var typeInfo: Option<LLVMValueRef> = None
    private var typeTemplate: Option<LLVMValueRef> = None
    private var containedGenerated: Bool = false
    private var cgGenericKind: CGGenericKind

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, cgTypeKind!: CGTypeKind = CGTypeKind.OTHERS) {
        this.cgMod = cgMod
        this.cgCtx = cgCtx
        this.chirType = chirType
        this.cgTypeKind = cgTypeKind
        cgGenericKind = CGType.GetCGGenericKind(chirType)
    }

    public func Complete(): Unit {
        if (llvmType.isNone()) {
            llvmType = GenLLVMType()
            CalculateSizeAndAlign()
        }
    }

    public func GetLLVMType(): LLVMTypeRef {
        Complete()
        if (let Some(rawType) <- llvmType) {
            return rawType
        }
        return LLVMNullType()
    }

    public func GetLayoutType(): LLVMTypeRef {
        Complete()
        if (let Some(rawLayout) <- layoutType) {
            return rawLayout
        }
        return GetLLVMType()
    }

    public func GetOriginal(): Type { return chirType }
    public func IsFloatType(): Bool { return chirType.IsFloat() }
    public func IsBooleanType(): Bool { return chirType.IsBoolean() }

    public func IsPointerType(addrSpace!: UInt32 = 0u32): Bool {
        if (chirType.IsRef() || chirType.IsRawArray() || chirType.IsBox() || chirType.IsCPointer() ||
            chirType.IsCString()) {
            return addrspace == addrSpace || addrSpace == 0u32
        }
        return false
    }

    public func IsStructType(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 10
    }
    public func IsVArrayType(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 11
    }
    public func IsStructPtrType(): Bool { return IsPointerType() && !GetContainedTypes().isEmpty() && GetContainedTypes()[0].IsStructType() }
    public func IsRefType(): Bool { return cgTypeKind == CGTypeKind.CG_REF }
    public func IsReference(): Bool { return chirType.IsReferenceType() || chirType.IsRef() }
    public open func IsOptionLikeRef(): Bool {
        if (let Some(enumCGType) <- (this as CGEnumType)) {
            return enumCGType.IsOptionLikeRef()
        }
        return false
    }
    public func IsFuncPtrType(): Bool { return chirType.IsFunc() }
    public func IsCGEnum(): Bool { return cgTypeKind == CGTypeKind.CG_ENUM }
    public func IsCGRef(): Bool { return cgTypeKind == CGTypeKind.CG_REF }
    public func IsCGFunction(): Bool { return cgTypeKind == CGTypeKind.CG_FUNCTION }
    public func IsCGTI(): Bool { return cgTypeKind == CGTypeKind.CG_TI }
    public func IsLoadablePtrType(): Bool {
        if (!IsPointerType()) {
            return false
        }
        if (chirType.IsCPointer() || chirType.IsCString()) {
            return IsLoadableCPointer()
        }
        if (IsFuncPtrType()) {
            return false
        }
        if (IsStructPtrType() || IsRefType() || IsVArrayPtrType()) {
            return false
        }
        return true
    }
    public func IsLoadableCPointer(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && IsPointerType() && GetPointerElementType().getOrThrow().IsPointerType()
    }
    public func IsVArrayPtrType(): Bool {
        return IsPointerType() &&
            unsafe { LLVMGetTypeKind(GetPointerElementType().getOrThrow().GetLLVMType()) } == 11
    }
    public func GetAddrspace(): UInt32 { return addrspace }
    public func GetSize(): Option<Int64> { Complete(); return size }
    public func GetAlign(): Option<Int64> { Complete(); return align }
    public func IsConcrete(): Bool { return cgGenericKind == CGGenericKind.CONCRETE }
    public func IsStaticGI(): Bool { return cgGenericKind == CGGenericKind.STATIC_GI }
    public func IsDynamicGI(): Bool { return cgGenericKind == CGGenericKind.DYNAMIC_GI }

    public func GetContainedTypes(): ArrayList<CGType> {
        if (!containedGenerated) {
            GenContainedCGTypes()
            containedGenerated = true
        }
        let out = ArrayList<CGType>()
        for (value in containedCGTypes) { out.add(value) }
        return out
    }

    public func GetPointerElementType(): Option<CGType> {
        if (chirType.IsGeneric()) {
            return Some(this)
        }
        let contained = GetContainedTypes()
        if (contained.isEmpty()) {
            return None
        }
        return contained[0]
    }

    public func GetContainedTypeAt(idx: UInt64): CGType {
        let contained = GetContainedTypes()
        let index = Int64(idx)
        CJC_ASSERT(index >= 0 && index < contained.size)
        return contained[index]
    }

    public func GetOrCreateTypeInfo(): LLVMValueRef {
        if (chirType.IsThis() || chirType.IsRef()) {
            throw IllegalArgumentException("typeinfo is not valid for " + chirType.ToString())
        }
        if (let Some(existingInfo) <- typeInfo) {
            return existingInfo
        }
        if (chirType.IsGeneric()) {
            let genericInfo = GetOrCreateGenericTypeInfoGlobal(cgMod, chirType)
            typeInfo = genericInfo
            return genericInfo
        }
        if ((chirType as CustomType).isSome() && chirType.IsGenericRelated()) {
            let genericCustomInfo = GetOrCreateGenericCustomTypeInfoGlobal(cgMod, chirType)
            typeInfo = genericCustomInfo
            return genericCustomInfo
        }
        let declaredInfo = DeclareTypeInfoGlobal(cgMod, chirType, cgGenericKind)
        typeInfo = declaredInfo
        DefineTypeInfoGlobalIfNeeded(cgMod, chirType, declaredInfo)
        return declaredInfo
    }

    public func GetOrCreateTypeTemplate(): LLVMValueRef {
        if (let Some(existingTemplate) <- typeTemplate) {
            return existingTemplate
        }
        let createdTemplate = GetOrCreateTypeTemplateGlobal(cgMod, chirType)
        typeTemplate = createdTemplate
        return createdTemplate
    }

    protected open func GenLLVMType(): LLVMTypeRef { return LLVMNullType() }
    protected open func GenContainedCGTypes(): Unit {}
    protected open func CalculateSizeAndAlign(): Unit { size = None; align = None }

    public static func GetCGGenericKind(chirType: Type): CGGenericKind {
        let hasGenericTypeArg = HasGenericTypeArg(chirType)
        if (hasGenericTypeArg) {
            return CGGenericKind.DYNAMIC_GI
        } else if (chirType.GetTypeArgs().isEmpty()) {
            if (let Some(customTy) <- (chirType as CustomType)) {
                if (!customTy.GetGenericArgs().isEmpty()) {
                    CJC_ASSERT(customTy.GetCustomTypeDef().TestAttr(Attribute.GENERIC_INSTANTIATED))
                    return CGGenericKind.STATIC_GI
                }
            }
            return CGGenericKind.CONCRETE
        } else {
            return CGGenericKind.STATIC_GI
        }
    }

    public static func GetOrCreate(cgModule: CGModule, chirTy: Type, extraInfo!: TypeExtraInfo = TypeExtraInfo()): CGType {
        return cgModule.GetCGContext().GetOrCreateCGType(cgModule, chirTy, extraInfo)
    }

    public static func GetOrCreateWithNode(cgModule: CGModule, chirNode: Value, allowBasePtr!: Bool = true,
        forWrapper!: Bool = false): CGType {
        let functionNode = chirNode as Function
        let chirTy = if (let Some(fn) <- functionNode) {
            if (let Some(overrideTy) <- fn.GetOverrideSrcFuncType()) {
                overrideTy
            } else {
                fn.GetType().getOrThrow()
            }
        } else if (let Some(valueTy) <- chirNode.GetType()) {
            valueTy
        } else {
            throw IllegalArgumentException("CHIR value has no type: " + chirNode.GetIdentifierWithoutPrefix())
        }
        var cgType: CGType
        if ((chirNode as LocalVar).isSome()) {
            cgType = CGTypeMgr.GetConcreteCGTypeFor(cgModule, chirTy,
                extraInfo: TypeExtraInfo(0u32, true, false, false, ArrayList<Type>()))
        } else if (let Some(fn) <- functionNode) {
            let typeExtra = TypeExtraInfo(0u32, false, false, allowBasePtr, ArrayList<Type>())
            typeExtra.forWrapper = forWrapper
            for (genericTy in fn.GetGenericTypeParams()) {
                typeExtra.instantiatedParamTypes.add(genericTy)
            }
            cgType = CGTypeMgr.GetConcreteCGTypeFor(cgModule, chirTy, extraInfo: typeExtra, chirFunc: fn)
        } else {
            return CGType.GetOrCreate(cgModule, chirTy)
        }
        cgType.llvmType = cgType.GenLLVMType()
        let _ = cgType.GetContainedTypes()
        return cgType
    }

    public static func GetUnitType(context: LLVMContextHandle): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(context, UNIT_TYPE_STR)
        let fields = ArrayList<LLVMTypeRef>()
        SetStructTypeBody(result, fields)
        return result
    }

    public static func GetRefType(context: LLVMContextHandle): LLVMTypeRef {
        return unsafe { LLVMPointerType(LLVMInt8TypeInContext(context.raw), 1u32) }
    }

    public static func GetLandingPadType(context: LLVMContextHandle): LLVMTypeRef {
        return unsafe { LLVMTokenTypeInContext(context.raw) }
    }

    public static func GetArrayBaseType(cgCtx: CGContext): LLVMTypeRef {
        let context = cgCtx.GetLLVMContext()
        let result = GetOrCreateNamedStructType(context, "ArrayBase")
        if (!cgCtx.IsGeneratedStructType("ArrayBase")) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(unsafe { LLVMInt64TypeInContext(context.raw) })
            SetStructTypeBody(result, body)
            cgCtx.AddGeneratedStructType("ArrayBase")
        }
        return result
    }

    public static func GetBitMapType(context: LLVMContextHandle): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(context, "BitMap")
        let body = ArrayList<LLVMTypeRef>()
        body.add(unsafe { LLVMInt32TypeInContext(context.raw) })
        body.add(unsafe { LLVMArrayType(LLVMInt8TypeInContext(context.raw), 0u32) })
        SetStructTypeBody(result, body)
        return result
    }

    public static func GetCodeGenFunctionType(_: LLVMContextHandle, retType: LLVMTypeRef): LLVMTypeRef {
        return unsafe { LLVMFunctionType(retType, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }

    public static func GetOrCreateTypeInfoType(context: LLVMContextHandle): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(context, "TypeInfo")
        let i8Ty = unsafe { LLVMInt8TypeInContext(context.raw) }
        let i16Ty = unsafe { LLVMInt16TypeInContext(context.raw) }
        let i32Ty = unsafe { LLVMInt32TypeInContext(context.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let i32PtrTy = unsafe { LLVMPointerType(i32Ty, 0u32) }
        let typeInfoPtrTy = unsafe { LLVMPointerType(result, 0u32) }
        let extensionDefPtrPtrTy = unsafe { LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(context), 0u32) }
        let bitMapPtrTy = unsafe { LLVMPointerType(CGType.GetBitMapType(context), 0u32) }
        let body = ArrayList<LLVMTypeRef>()
        body.add(i8PtrTy)
        body.add(i8Ty)
        body.add(i8Ty)
        body.add(i16Ty)
        body.add(i32Ty)
        body.add(bitMapPtrTy)
        body.add(i32Ty)
        body.add(i8Ty)
        body.add(i8Ty)
        body.add(i16Ty)
        body.add(i32PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(typeInfoPtrTy)
        body.add(extensionDefPtrPtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        SetStructTypeBody(result, body)
        return result
    }

    public static func GetOrCreateTypeInfoPtrType(context: LLVMContextHandle): LLVMTypeRef {
        return unsafe { LLVMPointerType(CGType.GetOrCreateTypeInfoType(context), 0u32) }
    }

    public static func GetClassTTExtTypeVer1(context: LLVMContextHandle): LLVMTypeRef {
        let name = "ext_class_type_ver_1"
        var result = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMGetTypeByName2(context.raw, nameCString.value) }
        }
        if (!result.isNull()) {
            return result
        }
        result = GetOrCreateNamedStructType(context, name)
        let i8Ty = unsafe { LLVMInt8TypeInContext(context.raw) }
        let body = ArrayList<LLVMTypeRef>()
        body.add(unsafe { LLVMPointerType(i8Ty, 0u32) })
        body.add(unsafe { LLVMInt16TypeInContext(context.raw) })
        body.add(unsafe { LLVMInt32TypeInContext(context.raw) })
        body.add(i8Ty)
        SetStructTypeBody(result, body)
        return result
    }

    public static func GetOrCreateTypeTemplateType(context: LLVMContextHandle): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(context, "TypeTemplate")
        let i8Ty = unsafe { LLVMInt8TypeInContext(context.raw) }
        let i16Ty = unsafe { LLVMInt16TypeInContext(context.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let extensionDefPtrPtrTy = unsafe { LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(context), 0u32) }
        let body = ArrayList<LLVMTypeRef>()
        body.add(i8PtrTy)
        body.add(i8Ty)
        body.add(i8Ty)
        body.add(i16Ty)
        body.add(i16Ty)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(extensionDefPtrPtrTy)
        body.add(i16Ty)
        SetStructTypeBody(result, body)
        return result
    }

    public static func GetOrCreateExtensionDefType(context: LLVMContextHandle): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(context, "ExtensionDef")
        let i8Ty = unsafe { LLVMInt8TypeInContext(context.raw) }
        let i16Ty = unsafe { LLVMInt16TypeInContext(context.raw) }
        let i32Ty = unsafe { LLVMInt32TypeInContext(context.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let body = ArrayList<LLVMTypeRef>()
        body.add(i32Ty)
        body.add(i8Ty)
        body.add(i8Ty)
        body.add(i16Ty)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        body.add(i8PtrTy)
        SetStructTypeBody(result, body)
        return result
    }

    public static func GetOrCreateExtensionDefPtrType(context: LLVMContextHandle): LLVMTypeRef {
        return unsafe { LLVMPointerType(CGType.GetOrCreateExtensionDefType(context), 0u32) }
    }

    public static func GetNameOfTypeInfoGV(chirType: Type): String {
        return CGType.GetRuntimeTypeName(chirType) + ".ti"
    }

    public static func GetRuntimeTypeName(chirType: Type): String {
        if (let Some(customTy) <- (chirType as CustomType)) {
            let def = customTy.GetCustomTypeDef()
            var name = if (def.GetPackageName().isEmpty()) {
                def.GetSrcCodeIdentifier()
            } else {
                def.GetPackageName() + ":" + def.GetSrcCodeIdentifier()
            }
            let typeArgs = chirType.GetTypeArgs()
            if (!typeArgs.isEmpty()) {
                var argsText = ""
                var idx: Int64 = 0
                for (argTy in typeArgs) {
                    if (idx > 0) {
                        argsText += ","
                    }
                    argsText += CGType.GetRuntimeTypeName(argTy)
                    idx++
                }
                name += "<" + argsText + ">"
            }
            return name
        }
        return chirType.ToString()
    }

    public static func GetNameOfTypeTemplateGV(chirType: Type): String {
        if (chirType.IsTuple()) {
            return "Tuple.tt"
        }
        if (chirType.IsRawArray()) {
            return "RawArray.tt"
        }
        if (chirType.IsVArray()) {
            return "VArray.tt"
        }
        if (chirType.IsCPointer()) {
            return "CPointer.tt"
        }
        if (chirType.IsFunc() || chirType.IsCFunc()) {
            return "CFunc.tt"
        }
        if (chirType.IsBox()) {
            return "Box.tt"
        }
        if (let Some(customTy) <- (chirType as CustomType)) {
            if (IsAutoEnvBaseType(customTy)) {
                return "Closure.tt"
            }
            let def = customTy.GetCustomTypeDef()
            let packageName = if (let Some(genericDecl) <- def.GetGenericDecl()) {
                genericDecl.GetPackageName()
            } else {
                def.GetPackageName()
            }
            return packageName + ":" + GetCustomTypeIdentifier(customTy) + ".tt"
        }
        return chirType.ToString() + ".tt"
    }
}

public class CGTIType <: CGType {
    public init(cgMod: CGModule) {
        super(cgMod, cgMod.GetCGContext(), Type(TypeKind.TYPE_INVALID), cgTypeKind: CGTypeKind.CG_TI)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        return CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext())
    }
}

public class CGTypeMgr {
    public static func GetConcreteCGTypeFor(cgMod: CGModule, chirType: Type, extraInfo!: TypeExtraInfo = TypeExtraInfo(),
        chirFunc!: Option<Function> = None): CGType {
        return match (chirType.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 |
                TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT16 |
                TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_RUNE | TypeKind.TYPE_BOOLEAN |
                TypeKind.TYPE_UNIT | TypeKind.TYPE_NOTHING | TypeKind.TYPE_VOID =>
                    CGPrimitiveType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_CSTRING => CGCStringType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_TUPLE => CGTupleType(cgMod, cgMod.GetCGContext(), chirType, extraInfo)
            case TypeKind.TYPE_STRUCT => CGStructType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_ENUM => CGEnumType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_FUNC =>
                if (let Some(fn) <- chirFunc) {
                    CGFunctionType(cgMod, cgMod.GetCGContext(), fn, extraInfo)
                } else if (let Some(funcTy) <- (chirType as FuncType)) {
                    CGFunctionType(cgMod, cgMod.GetCGContext(), funcTy, extraInfo)
                } else {
                    CGFunctionType(cgMod, cgMod.GetCGContext(), FuncType(ArrayList<Type>(), chirType), extraInfo)
                }
            case TypeKind.TYPE_CLASS => CGClassType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_VARRAY => CGVArrayType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_RAWARRAY => CGArrayType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_REFTYPE => CGRefType(cgMod, cgMod.GetCGContext(), chirType, extraInfo.addrspace)
            case TypeKind.TYPE_BOXTYPE => CGBoxType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_CPOINTER => CGCPointerType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_GENERIC => CGGenericType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_THIS => CGThisType(cgMod, cgMod.GetCGContext(), chirType)
            case TypeKind.TYPE_INVALID => CGType(cgMod, cgMod.GetCGContext(), chirType)
        }
    }
}
