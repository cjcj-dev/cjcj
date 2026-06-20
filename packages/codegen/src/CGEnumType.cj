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
import cangjie_compiler::option.{ArchType, EnvironmentType}

private let LLVM_POINTER_TYPE_KIND: Int32 = 12
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10

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
                let defId = enumTy.GetEnumDef().nodeId
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
                if (cgMod.IsEnumClassificationActive(enumTy.GetEnumDef().nodeId)) {
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

    public func IsOptionLikeRef(): Bool {
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

    protected override func GenLLVMType(): LLVMTypeRef {
        EnsureClassified()
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
            let enumLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
            layoutType = enumLayout
            let refType = CGType.GetRefType(cgCtx.GetLLVMContext())
            llvmType = refType
            if (!cgCtx.IsGeneratedStructType(layoutName)) {
                let body = ArrayList<LLVMTypeRef>()
                body.add(CGType.GetRefType(cgCtx.GetLLVMContext()))
                SetStructTypeBody(enumLayout, body)
                cgCtx.AddGeneratedStructType(layoutName)
            }
            return refType
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            let i8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
            llvmType = i8Ty
            return i8Ty
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            let refTy = CGType.GetRefType(cgCtx.GetLLVMContext())
            llvmType = refTy
            layoutType = refTy
            return refTy
        }
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let enumLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = enumLayout
        llvmType = enumLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            SetStructTypeBody(enumLayout, BuildEnumFieldTypes())
        }
        return enumLayout
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
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            if (let Some(associatedTy) <- optionLikeAssociatedValueType) {
                containedCGTypes.add(CGType.GetOrCreate(cgMod, associatedTy))
            }
            return
        }
        let selectorTy = if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            cgCtx.GetCHIRBuilder().context.GetBoolTy()
        } else {
            cgCtx.GetCHIRBuilder().context.GetUInt32Ty()
        }
        containedCGTypes.add(CGType.GetOrCreate(cgMod, selectorTy))
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_OTHER ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            let rawTy = GetLLVMType()
            size = Int64(cgMod.GetTypeSize(rawTy))
            align = Int64(cgMod.GetABITypeAlignment(rawTy))
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            size = None
            align = None
            return
        }
        if (ContainsGenericType(chirType)) {
            size = None
            align = None
            return
        }
        var total: Int64 = 0
        var maxAlign: Int64 = 1
        for (fieldCGType in GetContainedTypes()) {
            let fieldAlign = if (let Some(value) <- fieldCGType.GetAlign()) { value } else { 1 }
            let fieldSize = if (let Some(value) <- fieldCGType.GetSize()) { value } else { 0 }
            if (total % fieldAlign != 0) {
                total += fieldAlign - (total % fieldAlign)
            }
            total += fieldSize
            if (fieldAlign > maxAlign) { maxAlign = fieldAlign }
        }
        if (total % maxAlign != 0) {
            total += maxAlign - (total % maxAlign)
        }
        size = total
        align = maxAlign
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
            out.add(EnumCtorInfo(ctor.name, payloadTypes))
        }
        return out
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
        return if (NeedAndroidArm32AlignedEnumLayout()) {
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
            if (ContainsActiveEnumType(paramTy)) {
                return None
            }
            if (CGType.GetOrCreate(cgMod, paramTy).GetSize().isNone()) {
                return None
            }
            fullFieldTypes.add(paramTy)
        }
        let fieldLLVMTypes = ArrayList<LLVMTypeRef>()
        for (fieldTy in fullFieldTypes) {
            fieldLLVMTypes.add(CGType.GetOrCreate(cgMod, fieldTy.StripAllRefs()).GetLLVMType())
        }
        let layoutType = CreateAnonymousStructType(fieldLLVMTypes)
        return Some(Int64(cgMod.GetTypeSize(layoutType)) - 4)
    }

    private func CreateAnonymousStructType(fieldLLVMTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (fieldLLVMTypes.isEmpty()) {
            return unsafe { LLVMStructTypeInContext(cgCtx.GetLLVMContext().raw, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        var result = LLVMNullType()
        try (typePtr = LibC.malloc<LLVMTypeRef>(count: fieldLLVMTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < fieldLLVMTypes.size) {
                unsafe { (typePtr.value + idx).write(fieldLLVMTypes[idx]) }
                idx++
            }
            result = unsafe {
                LLVMStructTypeInContext(cgCtx.GetLLVMContext().raw, typePtr.value, UInt32(fieldLLVMTypes.size), 0)
            }
        }
        return result
    }

    private func NeedAndroidArm32AlignedEnumLayout(): Bool {
        let target = cgCtx.GetCompileOptions().target
        return target.arch == ArchType.ARM32 && target.env == EnvironmentType.ANDROID
    }

    private func ContainsActiveEnumType(ty: Type): Bool {
        let stripped = ty.StripAllRefs()
        if (let Some(enumTy) <- (stripped as EnumType)) {
            if (cgMod.IsEnumClassificationActive(enumTy.GetEnumDef().nodeId)) {
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

    private func BuildEnumFieldTypes(): ArrayList<LLVMTypeRef> {
        let out = ArrayList<LLVMTypeRef>()
        let selectorTy = if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            cgCtx.GetCHIRBuilder().context.GetBoolTy()
        } else {
            cgCtx.GetCHIRBuilder().context.GetUInt32Ty()
        }
        out.add(CGType.GetOrCreate(cgMod, selectorTy).GetLLVMType())
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            out.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
        }
        return out
    }

    private func BuildEnumPayloadFieldTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            if (let Some(associatedTy) <- optionLikeAssociatedValueType) {
                out.add(associatedTy)
            }
            return out
        }
        if (let Some(enumTy) <- (chirType as EnumType)) {
            for (ctor in enumTy.GetEnumDef().GetCtors()) {
                var idx: Int64 = 0
                for (payloadTy in ctor.payloadTypes) {
                    let instantiatedPayloadTy = InstantiateEnumPayloadType(enumTy, payloadTy)
                    if (idx >= out.size) {
                        out.add(instantiatedPayloadTy)
                    } else if (!out[idx].IsEqual(instantiatedPayloadTy)) {
                        out[idx] = PickEnumPayloadStorageType(out[idx], instantiatedPayloadTy)
                    }
                    idx++
                }
            }
        }
        return out
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

    private func PickEnumPayloadStorageType(left: Type, right: Type): Type {
        if (left.IsEqual(right)) {
            return left
        }
        if (left.IsRef() && right.IsRef()) {
            return left
        }
        if (left.IsRef() || right.IsRef()) {
            return cgCtx.GetCHIRBuilder().context.GetUInt64Ty()
        }
        let leftSize = CGType.GetOrCreate(cgMod, left).GetSize() ?? 0
        let rightSize = CGType.GetOrCreate(cgMod, right).GetSize() ?? 0
        return if (leftSize >= rightSize) { left } else { right }
    }
}
