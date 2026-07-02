package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.CPointerType
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.EnumCtorInfo
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TupleType
import cangjie_compiler::chir.VArrayType
import cangjie_compiler::mangle.GetTypeQualifiedName
import cangjie_compiler::option.{ArchType, EnvironmentType, TripleInfo}
import cangjie_compiler::utils.CJC_ASSERT

private let LLVM_POINTER_TYPE_KIND: Int32 = 12
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10

public class AssociatedNonRefLayout {
    public let offsets: ArrayList<UInt32> = ArrayList<UInt32>()
    public var size: UInt32 = 0u32
    public var align: UInt32 = 1u32

    public init() {}
}

public enum CGEnumTypeKind {
    | UNKNOWN
    | NON_EXHAUSTIVE_UNASSOCIATED
    | NON_EXHAUSTIVE_ASSOCIATED
    | EXHAUSTIVE_ZERO_SIZE
    | EXHAUSTIVE_UNASSOCIATED
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    | EXHAUSTIVE_ASSOCIATED_NONREF
    | EXHAUSTIVE_OTHER
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
}

private func CGEnumTypeKindIndex(kind: CGEnumTypeKind): Int64 {
    return match (kind) {
        case CGEnumTypeKind.UNKNOWN => 0
        case CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED => 1
        case CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED => 2
        case CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE => 3
        case CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED => 4
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF => 5
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF => 6
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF => 7
        case CGEnumTypeKind.EXHAUSTIVE_OTHER => 8
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T => 9
    }
}

extend CGEnumTypeKind <: Equatable<CGEnumTypeKind> {
    public operator func ==(right: CGEnumTypeKind): Bool {
        return CGEnumTypeKindIndex(this) == CGEnumTypeKindIndex(right)
    }

    public operator func !=(right: CGEnumTypeKind): Bool {
        return !(this == right)
    }
}

public class CGEnumType <: CGCustomType {
    private var cgEnumTypeKind: CGEnumTypeKind = CGEnumTypeKind.UNKNOWN
    private var optionLikeAssociatedValueType: Option<Type> = None
    private var isAntiOptionLike: Bool = false
    private var sizeOfConstructorUnion: Option<Int64> = None

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_ENUM)
    }

    private func EnsureClassified(): Unit {
        if (cgEnumTypeKind == CGEnumTypeKind.UNKNOWN) {
            if (let Some(enumTy) <- (chirType as EnumType)) {
                let defId = enumTy.ToString()
                if (!cgMod.EnterEnumClassification(defId)) {
                    return
                }
                cgEnumTypeKind = ClassifyEnumType()
                cgMod.ExitEnumClassification(defId)
            } else {
                cgEnumTypeKind = ClassifyEnumType()
            }
        }
    }

    public func IsTrivial(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    public func IsCommonEnum(): Bool {
        if (cgEnumTypeKind == CGEnumTypeKind.UNKNOWN) {
            if (let Some(enumTy) <- (chirType as EnumType)) {
                if (cgMod.IsEnumClassificationActive(enumTy.ToString())) {
                    return true
                }
            }
        }
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER
    }

    public func IsOptionLike(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    public func GetCGEnumTypeKind(): CGEnumTypeKind {
        EnsureClassified()
        return cgEnumTypeKind
    }

    public func IsOptionLikeNonRef(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    public override func IsOptionLikeRef(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
    }

    public func IsOptionLikeT(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
    }

    public func IsZeroSizeEnum(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE
    }

    public func IsAllAssociatedValuesAreNonRef(): Bool {
        EnsureClassified()
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF
    }

    public func PassByReference(): Bool {
        return IsOptionLikeNonRef() || IsOptionLikeT() || IsZeroSizeEnum() || IsAllAssociatedValuesAreNonRef()
    }

    public func IsAntiOptionLike(): Bool {
        EnsureClassified()
        return isAntiOptionLike
    }

    public func GetAssociatedValueTypeOfOptionLike(): Option<Type> {
        EnsureClassified()
        return optionLikeAssociatedValueType
    }

    public func GetSizeOfConstructorUnion(): Option<Int64> {
        EnsureClassified()
        return sizeOfConstructorUnion
    }

    public static func NeedAndroidArm32AlignedEnumLayout(target: TripleInfo): Bool {
        return target.arch == ArchType.ARM32 && target.env == EnvironmentType.ANDROID
    }

    public static func GetAndroidArm32AssociatedNonRefLayoutType(cgMod: CGModule,
        fieldTypes: ArrayList<Type>): LLVMTypeRef {
        if (fieldTypes.isEmpty()) {
            return unsafe { LLVMStructTypeInContext(cgMod.GetLLVMContext().raw, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        let llvmFieldTypes = ArrayList<LLVMTypeRef>()
        for (fieldType in fieldTypes) {
            llvmFieldTypes.add(CGType.GetOrCreate(cgMod, DeRef(fieldType)).GetLLVMType())
        }
        var result = LLVMNullType()
        try (typePtr = LibC.malloc<LLVMTypeRef>(count: llvmFieldTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < llvmFieldTypes.size) {
                unsafe { (typePtr.value + idx).write(llvmFieldTypes[idx]) }
                idx++
            }
            result = unsafe {
                LLVMStructTypeInContext(cgMod.GetLLVMContext().raw, typePtr.value, UInt32(llvmFieldTypes.size), 0)
            }
        }
        return result
    }

    public static func ComputeAssociatedNonRefLayout(cgMod: CGModule,
        fieldTypes: ArrayList<Type>): AssociatedNonRefLayout {
        return if (CGEnumType.NeedAndroidArm32AlignedEnumLayout(cgMod.GetCGContext().GetCompileOptions().target)) {
            ComputeAndroidArm32StructAssociatedNonRefLayout(cgMod, fieldTypes)
        } else {
            ComputeDefaultAssociatedNonRefLayout(cgMod, fieldTypes)
        }
    }

    private static func ComputeDefaultAssociatedNonRefLayout(cgMod: CGModule,
        fieldTypes: ArrayList<Type>): AssociatedNonRefLayout {
        let resultLayout = AssociatedNonRefLayout()
        var currentOffset: UInt32 = 0u32
        for (fieldType in fieldTypes) {
            resultLayout.offsets.add(currentOffset)
            let fieldCGType = CGType.GetOrCreate(cgMod, DeRef(fieldType))
            let fieldSize = fieldCGType.GetSize()
            CJC_ASSERT(fieldSize.isSome())
            currentOffset += UInt32(fieldSize.getOrThrow())
        }
        resultLayout.size = currentOffset
        resultLayout.align = 1u32
        return resultLayout
    }

    private static func ComputeAndroidArm32StructAssociatedNonRefLayout(cgMod: CGModule,
        fieldTypes: ArrayList<Type>): AssociatedNonRefLayout {
        let resultLayout = AssociatedNonRefLayout()
        let modelLayoutType = CGEnumType.GetAndroidArm32AssociatedNonRefLayoutType(cgMod, fieldTypes)
        resultLayout.size = UInt32(cgMod.GetTypeSize(modelLayoutType))
        resultLayout.align = cgMod.GetABITypeAlignment(modelLayoutType)
        var idx: Int64 = 0
        while (idx < fieldTypes.size) {
            resultLayout.offsets.add(UInt32(cgMod.GetOffsetOfElement(modelLayoutType, UInt32(idx))))
            idx++
        }
        return resultLayout
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        EnsureClassified()
        if (llvmType.isSome()) {
            return llvmType.getOrThrow()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            return GenTrivialLLVMType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return GenAssociatedNonRefEnumLLVMType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            return GenCommonEnumLLVMType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            return GenOptionLikeRefLLVMType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            return GenOptionLikeNonRefLLVMType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return GenZeroSizeEnumLLVMType()
        }
        CJC_ASSERT(false)
        return LLVMNullType()
    }

    private func GetEnumTypeName(): String {
        let enumTy = (chirType as EnumType).getOrThrow()
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            return ENUM_TYPE_PREFIX + "Trivial"
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            return ENUM_TYPE_PREFIX + enumTy.GetEnumDef().GetIdentifierWithoutPrefix() + "<T>"
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            return ENUM_TYPE_PREFIX + "OptionLike.Ref"
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return ENUM_TYPE_PREFIX + GetTypeQualifiedName(enumTy)
        }
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            return ENUM_TYPE_PREFIX + "Common"
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return ENUM_TYPE_PREFIX + "Empty"
        }
        CJC_ASSERT(false)
        return ""
    }

    private func GenTrivialLLVMType(): LLVMTypeRef {
        let typeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(typeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
                let body = ArrayList<LLVMTypeRef>()
                body.add(unsafe { LLVMInt32TypeInContext(cgCtx.GetLLVMContext().raw) })
                SetStructTypeBody(enumLayout, body)
            }
        }
        layoutType = enumLayout
        return unsafe { LLVMInt32TypeInContext(cgCtx.GetLLVMContext().raw) }
    }

    private func GenCommonEnumLLVMType(): LLVMTypeRef {
        let typeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(typeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
                let body = ArrayList<LLVMTypeRef>()
                body.add(unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), 1u32) })
                SetStructTypeBody(enumLayout, body)
            }
        }
        layoutType = enumLayout
        return CGType.GetRefType(cgCtx.GetLLVMContext())
    }

    private func GenZeroSizeEnumLLVMType(): LLVMTypeRef {
        let typeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(typeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
                SetStructTypeBody(enumLayout, ArrayList<LLVMTypeRef>())
            }
        }
        layoutType = enumLayout
        return enumLayout
    }

    private func GenOptionLikeRefLLVMType(): LLVMTypeRef {
        let typeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(typeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
                let i8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
                let body = ArrayList<LLVMTypeRef>()
                body.add(unsafe { LLVMPointerType(i8Ty, 1u32) })
                body.add(unsafe { LLVMArrayType(i8Ty, 0u32) })
                SetStructTypeBody(enumLayout, body)
            }
        }
        layoutType = enumLayout
        cgCtx.AddGeneratedStructType(typeName)
        return CGType.GetRefType(cgCtx.GetLLVMContext())
    }

    private func GenOptionLikeNonRefLLVMType(): LLVMTypeRef {
        let elemCGType = CGType.GetOrCreate(cgMod, optionLikeAssociatedValueType.getOrThrow())
        if (elemCGType.GetSize().isNone()) {
            return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let enumTypeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(enumTypeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (!enumLayout.isNull() && cgCtx.IsGeneratedStructType(enumTypeName)) {
                layoutType = enumLayout
                llvmType = enumLayout
                return enumLayout
            }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
            }
        }
        layoutType = enumLayout
        llvmType = enumLayout
        cgCtx.AddGeneratedStructType(enumTypeName)
        let elemTypes = ArrayList<LLVMTypeRef>()
        elemTypes.add(unsafe { LLVMInt1TypeInContext(cgCtx.GetLLVMContext().raw) })
        elemTypes.add(elemCGType.GetLLVMType())
        SetStructTypeBody(enumLayout, elemTypes)
        return enumLayout
    }

    private func GenAssociatedNonRefEnumLLVMType(): LLVMTypeRef {
        CJC_ASSERT(sizeOfConstructorUnion.isSome())
        let layoutSize = 4u32 + UInt32(sizeOfConstructorUnion.getOrThrow())
        let rawLLVMType = unsafe { LLVMArrayType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), layoutSize) }
        llvmType = rawLLVMType
        let enumTypeName = GetEnumTypeName()
        var enumLayout = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString(enumTypeName) }.asResource()) {
            enumLayout = unsafe { LLVMGetTypeByName2(cgCtx.GetLLVMContext().raw, nameCString.value) }
            if (!enumLayout.isNull() && cgCtx.IsGeneratedStructType(enumTypeName)) {
                layoutType = enumLayout
                return rawLLVMType
            }
            if (enumLayout.isNull()) {
                enumLayout = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
            }
        }
        layoutType = enumLayout
        cgCtx.AddGeneratedStructType(enumTypeName)
        let body = ArrayList<LLVMTypeRef>()
        body.add(rawLLVMType)
        SetStructTypeBody(enumLayout, body)
        return rawLLVMType
    }

    protected override func GenContainedCGTypes(): Unit {
        if (cgEnumTypeKind == CGEnumTypeKind.UNKNOWN) {
            cgEnumTypeKind = ClassifyEnumType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, cgCtx.GetCHIRBuilder().context.GetInt32Ty()))
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            if (let Some(associatedTy) <- optionLikeAssociatedValueType) {
                containedCGTypes.add(CGType.GetOrCreate(cgMod, associatedTy))
            }
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, cgCtx.GetCHIRBuilder().context.GetBoolTy()))
            containedCGTypes.add(CGType.GetOrCreate(cgMod, optionLikeAssociatedValueType.getOrThrow()))
            return
        }
        CJC_ASSERT(false)
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            let rawTy = llvmType.getOrThrow()
            size = Int64(cgMod.GetTypeSize(rawTy))
            align = size
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            let rawTy = llvmType.getOrThrow()
            size = Int64(cgMod.GetTypeSize(rawTy))
            align = Int64(cgMod.GetABITypeAlignment(rawTy))
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            CJC_ASSERT(sizeOfConstructorUnion.isSome())
            size = 4 + sizeOfConstructorUnion.getOrThrow()
            align = if (CGEnumType.NeedAndroidArm32AlignedEnumLayout(cgCtx.GetCompileOptions().target)) { 4 } else { 1 }
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            if (let Some(rawLayout) <- layoutType) {
                size = Int64(cgMod.GetTypeSize(rawLayout))
                align = Int64(cgMod.GetABITypeAlignment(rawLayout))
            } else {
                size = None
                align = None
            }
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            size = None
            align = None
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            size = 0
            align = 1
            return
        }
        CJC_ASSERT(false)
    }

    private func ClassifyEnumType(): CGEnumTypeKind {
        if (let Some(enumTy) <- (chirType as EnumType)) {
            let enumDef = enumTy.GetEnumDef()
            if (!enumDef.IsExhaustive()) {
                return if (enumDef.IsAllCtorsTrivial()) {
                    CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED
                } else {
                    CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED
                }
            }
            let (hasRefAssociatedValue, constructorUnionSize) = ObtainingAuxiliaryInformation(enumTy)
            sizeOfConstructorUnion = constructorUnionSize
            let ctors = enumDef.GetCtors()
            if (ctors.size == 1 && enumTy.GetGenericArgs().isEmpty()) {
                if (let Some(unionSize) <- constructorUnionSize) {
                    if (unionSize == 0) {
                        return CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE
                    }
                }
            }
            if (enumDef.IsAllCtorsTrivial()) {
                return CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
            }
            if (IsOptionLikeByConstructors(ctors)) {
                return ClassifyOptionLikeEnum(enumTy, ctors)
            }
            if (!hasRefAssociatedValue && enumTy.GetGenericArgs().isEmpty()) {
                return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF
            }
            return CGEnumTypeKind.EXHAUSTIVE_OTHER
        }
        return CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    private func ClassifyOptionLikeEnum(enumTy: EnumType, ctors: ArrayList<EnumCtorInfo>): CGEnumTypeKind {
        isAntiOptionLike = ctors[0].payloadTypes.isEmpty()
        let associatedTy = if (isAntiOptionLike) {
            ctors[1].payloadTypes[0]
        } else {
            ctors[0].payloadTypes[0]
        }
        let instantiatedAssociatedTy = InstantiateEnumPayloadType(enumTy, associatedTy)
        optionLikeAssociatedValueType = Some(instantiatedAssociatedTy)
        if (instantiatedAssociatedTy.IsGeneric()) {
            return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
        }
        let baseType = instantiatedAssociatedTy.StripAllRefs()
        if (let Some(baseEnumTy) <- (baseType as EnumType)) {
            if (let Some(baseEnumCGType) <- (CGType.GetOrCreate(cgMod, baseEnumTy) as CGEnumType)) {
                if (baseEnumCGType.IsCommonEnum()) {
                    return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
                }
            }
        }
        if (baseType.IsReferenceType()) {
            return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
        }
        return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    private func IsOptionLikeByConstructors(ctors: ArrayList<EnumCtorInfo>): Bool {
        if (ctors.size != 2) {
            return false
        }
        return (ctors[0].payloadTypes.isEmpty() && ctors[1].payloadTypes.size == 1) ||
            (ctors[0].payloadTypes.size == 1 && ctors[1].payloadTypes.isEmpty())
    }

    private func ObtainingAuxiliaryInformation(enumTy: EnumType): (Bool, Option<Int64>) {
        var hasRefAssociatedValue = false
        var maxUnionSize: Option<Int64> = Some(0)
        for (ctor in GetInstantiatedCtorInfos(enumTy)) {
            hasRefAssociatedValue = hasRefAssociatedValue || HasRefAssociatedValue(ctor.payloadTypes)
            if (let Some(currentMax) <- maxUnionSize) {
                if (let Some(candidateSize) <- TryComputeConstructorUnionSize(ctor.payloadTypes)) {
                    maxUnionSize = Some(if (currentMax < candidateSize) { candidateSize } else { currentMax })
                } else {
                    maxUnionSize = None
                }
            }
        }
        return (hasRefAssociatedValue, maxUnionSize)
    }

    private func GetInstantiatedCtorInfos(enumTy: EnumType): ArrayList<EnumCtorInfo> {
        let out = ArrayList<EnumCtorInfo>()
        for (ctor in enumTy.GetEnumDef().GetCtors()) {
            let payloadTypes = ArrayList<Type>()
            for (payloadTy in ctor.payloadTypes) {
                payloadTypes.add(InstantiateEnumPayloadType(enumTy, payloadTy))
            }
            out.add(EnumCtorInfo(ctor.name, payloadTypes, mangledName: ctor.mangledName,
                funcType: InstantiateEnumCtorFuncType(enumTy, ctor, payloadTypes), annoInfo: ctor.annoInfo))
        }
        return out
    }

    private func InstantiateEnumCtorFuncType(enumTy: EnumType, ctor: EnumCtorInfo,
        payloadTypes: ArrayList<Type>): Option<FuncType> {
        if (let Some(funcTy) <- ctor.funcType) {
            if (let Some(instFuncTy) <- (InstantiateEnumPayloadType(enumTy, funcTy) as FuncType)) {
                return Some(instFuncTy)
            }
        }
        return Some(FuncType(payloadTypes, enumTy))
    }

    private func HasRefAssociatedValue(paramTypes: ArrayList<Type>): Bool {
        for (paramTy in paramTypes) {
            if (ContainsActiveEnumType(paramTy)) {
                return true
            }
            if (ContainsRefType(CGType.GetOrCreate(cgMod, paramTy).GetLLVMType())) {
                return true
            }
        }
        return false
    }

    private func ContainsRefType(llvmTy: LLVMTypeRef): Bool {
        if (llvmTy.isNull()) {
            return false
        }
        let kind = unsafe { LLVMGetTypeKind(llvmTy) }
        if (kind == LLVM_POINTER_TYPE_KIND) {
            return unsafe { LLVMGetPointerAddressSpace(llvmTy) } == 1u32
        }
        if (kind == LLVM_STRUCT_TYPE_KIND) {
            let elementCount = unsafe { LLVMCountStructElementTypes(llvmTy) }
            if (elementCount == 0u32) {
                return false
            }
            var result = false
            try (elementPtr = LibC.malloc<LLVMTypeRef>(count: Int64(elementCount)).asResource()) {
                unsafe { LLVMGetStructElementTypes(llvmTy, elementPtr.value) }
                var idx: Int64 = 0
                while (idx < Int64(elementCount)) {
                    if (ContainsRefType(unsafe { (elementPtr.value + idx).read() })) {
                        result = true
                        break
                    }
                    idx++
                }
            }
            return result
        }
        return false
    }

    private func TryComputeConstructorUnionSize(paramTypes: ArrayList<Type>): Option<Int64> {
        return if (CGEnumType.NeedAndroidArm32AlignedEnumLayout(cgMod.GetCGContext().GetCompileOptions().target)) {
            TryComputeAndroidArm32StructConstructorUnionSize(paramTypes)
        } else {
            TryComputeDefaultConstructorUnionSize(paramTypes)
        }
    }

    private func TryComputeDefaultConstructorUnionSize(paramTypes: ArrayList<Type>): Option<Int64> {
        var accumulatedSize: Int64 = 0
        for (paramTy in paramTypes) {
            if (ContainsActiveEnumType(paramTy)) {
                return None
            }
            if (let Some(paramSize) <- CGType.GetOrCreate(cgMod, paramTy).GetSize()) {
                accumulatedSize += paramSize
            } else {
                return None
            }
        }
        return Some(accumulatedSize)
    }

    private func TryComputeAndroidArm32StructConstructorUnionSize(paramTypes: ArrayList<Type>): Option<Int64> {
        let fullFieldTypes = ArrayList<Type>()
        fullFieldTypes.add(cgCtx.GetCHIRBuilder().context.GetInt32Ty())
        for (paramTy in paramTypes) {
            if (CGType.GetOrCreate(cgMod, paramTy).GetSize().isNone()) {
                return None
            }
            fullFieldTypes.add(paramTy)
        }
        let fullLayout = CGEnumType.ComputeAssociatedNonRefLayout(cgMod, fullFieldTypes)
        return Some(Int64(fullLayout.size) - 4)
    }

    private func ContainsActiveEnumType(ty: Type): Bool {
        let stripped = ty.StripAllRefs()
        if (let Some(enumTy) <- (stripped as EnumType)) {
            if (cgMod.IsEnumClassificationActive(enumTy.ToString())) {
                return true
            }
        }
        for (argTy in stripped.GetTypeArgs()) {
            if (ContainsActiveEnumType(argTy)) {
                return true
            }
        }
        if (let Some(funcTy) <- (stripped as FuncType)) {
            for (paramTy in funcTy.GetParamTypes()) {
                if (ContainsActiveEnumType(paramTy)) {
                    return true
                }
            }
            return ContainsActiveEnumType(funcTy.GetReturnType())
        }
        return false
    }

    private func InstantiateEnumPayloadType(enumTy: EnumType, payloadTy: Type): Type {
        return SubstituteGenericType(payloadTy, enumTy.GetEnumDef().GetGenericTypeParams(), enumTy.GetGenericArgs())
    }

    private func SubstituteGenericType(ty: Type, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Type {
        if (let Some(genericTy) <- (ty as GenericType)) {
            var idx: Int64 = 0
            while (idx < genericParams.size && idx < replacements.size) {
                if (genericTy.IsEqual(genericParams[idx])) {
                    return replacements[idx]
                }
                idx++
            }
            return ty
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return RefType(SubstituteGenericType(refTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return RawArrayType(SubstituteGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return VArrayType(SubstituteGenericType(varrayTy.GetElementType(), genericParams, replacements),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return CPointerType(SubstituteGenericType(pointerTy.GetElementType(), genericParams, replacements))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return BoxType(SubstituteGenericType(boxTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return TupleType(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericParams, replacements))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = SubstituteGenericTypeArgs(funcTy.GetParamTypes(), genericParams, replacements)
            let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
            return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return StructType(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return ClassType(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return EnumType(enumTy.GetEnumDef(),
                SubstituteGenericTypeArgs(enumTy.GetGenericArgs(), genericParams, replacements))
        }
        return ty
    }

    private func SubstituteGenericTypeArgs(args: ArrayList<Type>, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (arg in args) {
            out.add(SubstituteGenericType(arg, genericParams, replacements))
        }
        return out
    }

}
