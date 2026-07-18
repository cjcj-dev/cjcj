package cjcj::codegen

import std.collection.*
import cjcj::basic.Linkage
import cjcj::chir.Attribute
import cjcj::chir.CHIRBuilder
import cjcj::chir.CustomType
import cjcj::chir.EnumType
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.GenericType
import cjcj::chir.LocalVar
import cjcj::chir.LinkTypeInfo
import cjcj::chir.RefType
import cjcj::chir.Type
import cjcj::chir.TypeKind
import cjcj::chir.Value
import cjcj::chir.GetCustomTypeIdentifier
import cjcj::chir.GetCustomTypeDefIdentifier
import cjcj::chir.GetTypeArgsQualifiedName
import cjcj::chir.GetTypeQualifiedName
import cjcj::option.ArchType
import cjcj::utils.CJC_ASSERT

private let LLVM_FUNCTION_TYPE_KIND: Int32 = 9
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let LLVM_ARRAY_TYPE_KIND: Int32 = 11
private let LLVM_POINTER_TYPE_KIND: Int32 = 12

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
    protected var typeInfo: Option<LLVMValueRef> = None
    protected var typeTemplate: Option<LLVMValueRef> = None
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
        if (let Some(rawType) <- llvmType) {
            return rawType
        }
        return LLVMNullType()
    }

    public func GetLayoutType(): LLVMTypeRef {
        if (let Some(rawLayout) <- layoutType) {
            return rawLayout
        }
        return GetLLVMType()
    }

    public func GetOriginal(): Type { return chirType }
    public func IsFloatType(): Bool { return chirType.IsFloat() }
    public func IsBooleanType(): Bool { return chirType.IsBoolean() }

    public func IsPointerType(addrSpace!: UInt32 = 0u32): Bool {
        if (chirType.IsRef()) {
            return true
        }
        let rawTy = GetLLVMType()
        return !chirType.IsFunc() && !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == LLVM_POINTER_TYPE_KIND &&
            unsafe { LLVMGetPointerAddressSpace(rawTy) } == addrSpace
    }

    public func IsStructType(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 10
    }
    public func IsVArrayType(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 11
    }
    public func IsStructPtrType(): Bool {
        if (!IsPointerType()) {
            return false
        }
        let elementType = GetPointerElementType().getOrThrow().GetLLVMType()
        CJC_ASSERT(!elementType.isNull())
        return unsafe { LLVMGetTypeKind(elementType) } == LLVM_STRUCT_TYPE_KIND
    }
    public func IsRefType(): Bool {
        let rawTy = GetLLVMType()
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == LLVM_POINTER_TYPE_KIND &&
            unsafe { LLVMGetPointerAddressSpace(rawTy) } == 1u32
    }
    public func IsReference(): Bool {
        if (chirType.IsRef()) {
            let baseType = chirType.GetTypeArgs()[0]
            if (baseType.IsClass() || baseType.IsRawArray() || baseType.IsBox()) {
                return true
            }
        }
        if (chirType.IsBox() || chirType.IsClass() || chirType.IsRawArray()) {
            return true
        }
        if (chirType.IsEnum()) {
            return if (let Some(enumCGType) <- (this as CGEnumType)) { enumCGType.IsCommonEnum() } else { false }
        }
        if (let Some(genericTy) <- (chirType as GenericType)) {
            for (upperBound in genericTy.GetUpperBounds()) {
                if (CGType.GetOrCreate(cgMod, upperBound).IsReference()) {
                    return true
                }
            }
        }
        return false
    }
    public open func IsOptionLikeRef(): Bool {
        if (let Some(enumCGType) <- (this as CGEnumType)) {
            return enumCGType.IsOptionLikeRef()
        }
        return false
    }
    public func IsFuncPtrType(): Bool {
        if (!IsPointerType()) {
            return false
        }
        let elementType = GetPointerElementType().getOrThrow().GetLLVMType()
        CJC_ASSERT(!elementType.isNull())
        return unsafe { LLVMGetTypeKind(elementType) } == LLVM_FUNCTION_TYPE_KIND
    }
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
        if (!IsPointerType()) {
            return false
        }
        let elementType = GetPointerElementType().getOrThrow().GetLLVMType()
        CJC_ASSERT(!elementType.isNull())
        return unsafe { LLVMGetTypeKind(elementType) } == LLVM_ARRAY_TYPE_KIND
    }
    public func GetAddrspace(): UInt32 { return addrspace }
    public func GetSize(): Option<Int64> { return size }
    public func GetAlign(): Option<Int64> { return align }
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
        if (cgGenericKind == CGGenericKind.DYNAMIC_GI) {
            let genericCustomInfo = GetOrCreateGenericCustomTypeInfoGlobal(cgMod, chirType)
            typeInfo = genericCustomInfo
            return genericCustomInfo
        }
        let declaredInfo = DeclareTypeInfoGlobal(cgMod, chirType, cgGenericKind)
        typeInfo = declaredInfo
        // Faithful to C++ CGType::GetOrCreateTypeInfo (CGType.cpp:254-256): queue the concrete
        // definition instead of defining it inline. Inline definition recurses through
        // BuildConcreteTypeInfoInitializer -> fields/type-args -> GetOrCreateTypeInfo, and because the
        // initializer (hence the LLVMIsDeclaration guard) is only set AFTER that recursion, a recursive
        // type never terminates. Deferring to CGModule.GenTypeInfo()'s drain defines each type to
        // completion before the next, so cyclic references hit the already-defined guard.
        if (unsafe { LLVMIsDeclaration(declaredInfo) } != 0) {
            cgMod.DelayGenTypeInfo(this)
        }
        return declaredInfo
    }

    // Mirror C++ CGType::GenTypeInfo (CGType.cpp:616): define this type's concrete TypeInfo global.
    // Invoked from CGModule.GenTypeInfo()'s drain loop.
    public func GenTypeInfo(): Unit {
        CJC_ASSERT(!IsDynamicGI())
        if (let Some(ti) <- typeInfo) {
            PreActionOfGenTypeInfo()
            if (let Some(rawLayout) <- layoutType) {
                let structName = LLVMCStringToString(unsafe { LLVMGetStructName(rawLayout) }) ?? ""
                if (!structName.isEmpty()) {
                    if (LLVMGetInstructionMetadata(cgMod.GetLLVMContext(), ti, GC_TYPE_META_NAME).isNone()) {
                        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), ti, GC_TYPE_META_NAME, structName)
                    }
                    cgCtx.AddGeneratedStructType(structName)
                }
            }
            if (unsafe { LLVMIsDeclaration(ti) } == 0) {
                return
            }
            if (chirType.IsPrimitive() || chirType.IsVoid() || chirType.IsCString()) {
                return
            }
            if (IsConcrete() && cgMod.GetCGContext().IsCustomTypeOfOtherLLVMModule(chirType)) {
                if (let Some(customType) <- (chirType as CustomType)) {
                    if (customType.GetCustomTypeDef().Get<LinkTypeInfo, Linkage>() == Linkage.EXTERNAL_WEAK) {
                        unsafe { LLVMSetLinkage(ti, LLVMLinkageValue(LLVMLinkage.ExternalWeak)) }
                    }
                }
                return
            }
            DefineTypeInfoGlobalIfNeeded(cgMod, chirType, ti)
            PostActionOfGenTypeInfo()
        }
    }

    public func GetOrCreateTypeTemplate(): LLVMValueRef {
        if (let Some(existingTemplate) <- typeTemplate) {
            return existingTemplate
        }
        let createdTemplate = GetOrCreateTypeTemplateGlobal(cgMod, chirType)
        CJC_ASSERT(!createdTemplate.isNull())
        typeTemplate = createdTemplate
        cgMod.DelayGenTypeTemplate(this)
        return createdTemplate
    }

    public open func GenTypeTemplate(): Unit {}

    protected open func GenLLVMType(): LLVMTypeRef { return LLVMNullType() }
    protected open func GenContainedCGTypes(): Unit {}
    protected open func CalculateSizeAndAlign(): Unit { size = None; align = None }
    protected open func PreActionOfGenTypeInfo(): Unit {}
    protected open func PostActionOfGenTypeInfo(): Unit {}

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

    public static func GetOrCreateEnumCtorLayoutType(cgModule: CGModule, enumTy: EnumType,
        ctorIndex: Int64, paramTypes: ArrayList<Type>): LLVMTypeRef {
        var className = enumTy.GetEnumDef().GetPackageName() + ":" +
            GetCustomTypeDefIdentifier(enumTy.GetEnumDef()) + ":" + ctorIndex.toString()
        if (!enumTy.GetTypeArgs().isEmpty()) {
            className += "<" + GetTypeArgsQualifiedName(enumTy.GetTypeArgs()) + ">"
        }
        let layoutName = GetClassObjLayoutName(className)
        var enumCtorLayoutType = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(layoutName) }.asResource()) {
            enumCtorLayoutType = unsafe { LLVMGetTypeByName2(cgModule.GetLLVMContext().raw, nameCString.value) }
        }
        if (!enumCtorLayoutType.isNull()) {
            return enumCtorLayoutType
        }
        let fieldTypes = ArrayList<Type>()
        let cgEnumType = (CGType.GetOrCreate(cgModule, enumTy) as CGEnumType).getOrThrow()
        fieldTypes.add(if (cgEnumType.IsOptionLike()) {
            cgModule.GetCGContext().GetCHIRBuilder().context.GetBoolTy()
        } else {
            cgModule.GetCGContext().GetCHIRBuilder().context.GetInt32Ty()
        })
        for (paramType in paramTypes) {
            fieldTypes.add(paramType)
        }
        return GetLLVMStructType(cgModule, fieldTypes, layoutName)
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
        var result = LLVMNullType()
        var created = false
        try (nameCString = unsafe { LibC.mallocCString("ArrayBase") }.asResource()) {
            result = unsafe { LLVMGetTypeByName2(context.raw, nameCString.value) }
            if (result.isNull()) {
                result = unsafe { LLVMStructCreateNamed(context.raw, nameCString.value) }
                created = true
            }
        }
        if (created) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(unsafe { LLVMInt64TypeInContext(context.raw) })
            SetStructTypeBody(result, body)
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

    public static func GetCodeGenFunctionType(_: LLVMContextHandle, retType: LLVMTypeRef,
        paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (paramTypes.isEmpty()) {
            return unsafe { LLVMFunctionType(retType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        var result = LLVMNullType()
        try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < paramTypes.size) {
                unsafe { (paramPtr.value + idx).write(paramTypes[idx]) }
                idx++
            }
            result = unsafe { LLVMFunctionType(retType, paramPtr.value, UInt32(paramTypes.size), 0) }
        }
        return result
    }

    public static func GetRefTypeOf(chirBuilder: CHIRBuilder, typeOfCHIR: Type): RefType {
        return chirBuilder.context.GetRefTy(typeOfCHIR)
    }

    public static func GetRefTypeOfCHIRInt8(chirBuilder: CHIRBuilder): RefType {
        return GetRefTypeOf(chirBuilder, chirBuilder.context.GetInt8Ty())
    }

    public static func GetObjectCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetObjectTy().getOrThrow())
    }

    public static func GetInt8CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt8Ty())
    }

    public static func GetInt8PtrCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, CGType.GetRefTypeOfCHIRInt8(cgMod.GetCGContext().GetCHIRBuilder()))
    }

    public static func GetInt16CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt16Ty())
    }

    public static func GetInt32CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt32Ty())
    }

    public static func GetInt64CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt64Ty())
    }

    public static func GetIntNativeCGType(cgMod: CGModule): CGType {
        if (cgMod.GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) {
            return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt32Ty())
        }
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetInt64Ty())
    }

    public static func GetUInt8CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetUInt8Ty())
    }

    public static func GetUInt16CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetUInt16Ty())
    }

    public static func GetUInt32CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetUInt32Ty())
    }

    public static func GetUInt64CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetUInt64Ty())
    }

    public static func GetFloat16CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetFloat16Ty())
    }

    public static func GetFloat32CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetFloat32Ty())
    }

    public static func GetFloat64CGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetFloat64Ty())
    }

    public static func GetUnitCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetUnitTy())
    }

    public static func GetNothingCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetNothingType())
    }

    public static func GetBoolCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetBoolTy())
    }

    public static func GetCStringCGType(cgMod: CGModule): CGType {
        return CGType.GetOrCreate(cgMod, cgMod.GetCGContext().GetCHIRBuilder().context.GetCStringTy())
    }

    public static func GetOrCreateTypeInfoType(context: LLVMContextHandle): LLVMTypeRef {
        var result = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString("TypeInfo") }.asResource()) {
            result = unsafe { LLVMGetTypeByName2(context.raw, nameCString.value) }
            if (!result.isNull()) {
                return result
            }
            result = unsafe { LLVMStructCreateNamed(context.raw, nameCString.value) }
        }
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
        return GetTypeQualifiedName(chirType) + ".ti"
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
