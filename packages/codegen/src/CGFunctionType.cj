package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.Type
import cangjie_compiler::utils.CJC_ASSERT

private class GenericParamIndex {
    public let chirGenericTy: GenericType
    public let llvmParamIndex: Int64

    public init(chirGenericTy: GenericType, llvmParamIndex: Int64) {
        this.chirGenericTy = chirGenericTy
        this.llvmParamIndex = llvmParamIndex
    }
}

public class CGFunctionType <: CGType {
    private var hasSRet: Bool = false
    private var hasBasePtr: Bool = false
    private var llvmFunctionType: Option<LLVMTypeRef> = None
    private let realParamIndices: ArrayList<Int64> = ArrayList<Int64>()
    private let structParamNeedsBasePtr: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let genericParamIndicesMap: ArrayList<GenericParamIndex> = ArrayList<GenericParamIndex>()
    private var methodTypeInfoIndex: Option<Int64> = None
    private var staticMethodTypeInfoIndex: Option<Int64> = None
    private let chirFunc: Option<Function>
    private let allowBasePtr: Bool
    private let methodType: Bool
    private let staticMethodType: Bool
    private let forWrapper: Bool
    private let constructorType: Bool
    private let instantiatedParamTypes: ArrayList<Type> = ArrayList<Type>()
    public let closureParamIndices: ArrayList<LLVMMetadataRef> = ArrayList<LLVMMetadataRef>()

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: FuncType, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_FUNCTION)
        CJC_ASSERT(chirType.IsFunc())
        CJC_ASSERT(!extraInfo.forWrapper)
        chirFunc = None
        allowBasePtr = true
        methodType = extraInfo.isMethod
        staticMethodType = extraInfo.isStaticMethod
        forWrapper = false
        constructorType = false
        for (ty in extraInfo.instantiatedParamTypes) {
            instantiatedParamTypes.add(ty)
        }
    }

    public init(cgMod: CGModule, cgCtx: CGContext, chirFunc: Function, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, if (let Some(overrideSrcFuncType) <- chirFunc.GetOverrideSrcFuncType()) {
            overrideSrcFuncType
        } else {
            chirFunc.GetType().getOrThrow()
        }, cgTypeKind: CGTypeKind.CG_FUNCTION)
        this.chirFunc = chirFunc
        allowBasePtr = if (extraInfo.forWrapper) { false } else { extraInfo.allowBasePtr }
        methodType = chirFunc.GetParentCustomTypeDef().isSome()
        staticMethodType = chirFunc.TestAttr(Attribute.STATIC)
        forWrapper = extraInfo.forWrapper
        constructorType = chirFunc.IsConstructor()
        for (genericTy in chirFunc.GetGenericTypeParams()) {
            instantiatedParamTypes.add(genericTy)
        }
    }

    public func HasSRet(): Bool { Complete(); return hasSRet }
    public func HasBasePtr(): Bool { Complete(); return hasBasePtr }
    public func IsMethodType(): Bool { return methodType }
    public func IsStaticMethodType(): Bool { return staticMethodType }
    public func IsConstructorType(): Bool { return constructorType }
    public func GetRealArgIndices(): ArrayList<Int64> { Complete(); return realParamIndices }
    public func GetStructParamNeedsBasePtrIndices(): HashMap<Int64, Int64> {
        Complete()
        let out = HashMap<Int64, Int64>()
        for ((argIdx, containedIdx) in structParamNeedsBasePtr) {
            out[argIdx] = containedIdx
        }
        return out
    }
    public func GetGenericParamIndex(genericTy: Type): Option<Int64> {
        Complete()
        for (item in genericParamIndicesMap) {
            if (genericTy.objectId == item.chirGenericTy.objectId) {
                return Some(item.llvmParamIndex)
            }
        }
        return None
    }
    public func GetGenericParamIndicesMap(): ArrayList<(GenericType, Int64)> {
        Complete()
        let out = ArrayList<(GenericType, Int64)>()
        for (item in genericParamIndicesMap) {
            out.add((item.chirGenericTy, item.llvmParamIndex))
        }
        return out
    }
    public func GetMethodTypeInfoIndex(): Option<Int64> { Complete(); return methodTypeInfoIndex }
    public func GetOuterTypeInfoIndex(): Option<Int64> { Complete(); return methodTypeInfoIndex }
    public func GetStaticMethodTypeInfoIndex(): Option<Int64> { Complete(); return staticMethodTypeInfoIndex }
    public func GetThisTypeInfoIndex(): Option<Int64> { Complete(); return staticMethodTypeInfoIndex }
    public func GetParamType(idx: Int64): CGType {
        let types = GetContainedTypes()
        CJC_ASSERT(idx + 1 < types.size)
        return types[idx + 1]
    }

    public func GetLLVMFunctionType(): LLVMTypeRef {
        Complete()
        if (let Some(funcTy) <- (chirType as FuncType)) {
            if (funcTy.IsCFunc()) {
                return cgMod.GetCGCFFI().GetCFuncType(funcTy)
            }
        }
        if (let Some(rawFunctionTy) <- llvmFunctionType) {
            return rawFunctionTy
        }
        return GetLLVMType()
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let funcTy = (chirType as FuncType).getOrThrow()
        if (funcTy.IsCFunc()) {
            llvmType = unsafe {
                LLVMPointerType(LLVMStructTypeInContext(cgCtx.GetLLVMContext().raw, CPointer<LLVMTypeRef>(), 0u32, 0),
                    0u32)
            }
            let rawCFuncType = cgMod.GetCGCFFI().GetCFuncType(funcTy)
            if (!rawCFuncType.isNull()) {
                llvmFunctionType = rawCFuncType
                llvmType = unsafe { LLVMPointerType(rawCFuncType, 0u32) }
            }
            return llvmType.getOrThrow()
        }
        let retCGType = CGType.GetOrCreate(cgMod, funcTy.GetReturnType())
        let retTy = funcTy.GetReturnType()
        hasSRet = !IsVoidLikeReturn(retTy) && ShouldUseSRet(retCGType)
        let retLLVMType = if (IsVoidLikeReturn(retTy) || hasSRet) {
            unsafe { LLVMVoidTypeInContext(cgCtx.GetLLVMContext().raw) }
        } else {
            retCGType.GetLLVMType()
        }
        let paramLLVMTypes = ArrayList<LLVMTypeRef>()
        var realArgIdx: Int64 = 0
        if (hasSRet) {
            let sretAddrspace = if (retCGType.GetSize().isNone() && !retTy.IsGeneric()) { 1u32 } else { 0u32 }
            paramLLVMTypes.add(unsafe { LLVMPointerType(retCGType.GetLLVMType(), sretAddrspace) })
            realArgIdx++
        }
        realParamIndices.clear()
        structParamNeedsBasePtr.clear()
        genericParamIndicesMap.clear()
        var containedCGTypeIndex: Int64 = 1
        for (paramTy in funcTy.GetParamTypes()) {
            let paramCGType = CGType.GetOrCreate(cgMod, paramTy)
            realParamIndices.add(realArgIdx)
            let derefParamTy = paramTy.StripAllRefs()
            if (paramTy.IsRef() && (derefParamTy.IsStruct() || derefParamTy.IsTuple())) {
                let derefParamCGType = CGType.GetOrCreate(cgMod, derefParamTy)
                paramLLVMTypes.add(unsafe { LLVMPointerType(derefParamCGType.GetLLVMType(), 1u32) })
                if (allowBasePtr) {
                    paramLLVMTypes.add(CGType.GetRefType(cgCtx.GetLLVMContext()))
                    structParamNeedsBasePtr[realArgIdx] = containedCGTypeIndex
                    realArgIdx++
                    hasBasePtr = true
                }
            } else if (paramTy.IsStruct() || paramTy.IsTuple() ||
                (paramCGType.GetSize().isNone() && !paramTy.IsGeneric())) {
                let addrspace = if (IsFirstStructOrExtendThisParam(containedCGTypeIndex)) {
                    0u32
                } else if (paramCGType.GetSize().isSome()) {
                    0u32
                } else {
                    1u32
                }
                paramLLVMTypes.add(unsafe { LLVMPointerType(paramCGType.GetLLVMType(), addrspace) })
            } else if (paramCGType.IsStructType() || paramCGType.IsVArrayType()) {
                paramLLVMTypes.add(unsafe { LLVMPointerType(paramCGType.GetLLVMType(), 0u32) })
            } else {
                paramLLVMTypes.add(paramCGType.GetLLVMType())
            }
            containedCGTypeIndex++
            realArgIdx++
        }
        if (let Some(fn) <- chirFunc) {
            for (chirGenericTy in fn.GetGenericTypeParams()) {
                genericParamIndicesMap.add(GenericParamIndex(chirGenericTy, realArgIdx))
                paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
                realArgIdx++
            }
        } else {
            for (_ in instantiatedParamTypes) {
                paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
                realArgIdx++
            }
        }
        if (methodType) {
            methodTypeInfoIndex = Some(realArgIdx)
            paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
            realArgIdx++
        }
        if (staticMethodType) {
            staticMethodTypeInfoIndex = Some(realArgIdx)
            paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
            realArgIdx++
        }
        if (paramLLVMTypes.isEmpty()) {
            llvmFunctionType = unsafe {
                LLVMFunctionType(retLLVMType, CPointer<LLVMTypeRef>(), 0u32, if (funcTy.HasVarArg()) { 1 } else { 0 })
            }
        } else {
            try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramLLVMTypes.size).asResource()) {
                var idx: Int64 = 0
                while (idx < paramLLVMTypes.size) {
                    unsafe { (paramPtr.value + idx).write(paramLLVMTypes[idx]) }
                    idx++
                }
                llvmFunctionType = unsafe {
                    LLVMFunctionType(retLLVMType, paramPtr.value, UInt32(paramLLVMTypes.size),
                        if (funcTy.HasVarArg()) { 1 } else { 0 })
                }
            }
        }
        if (let Some(rawFunctionType) <- llvmFunctionType) {
            if (!funcTy.IsCFunc()) {
                return CGType.GetRefType(cgCtx.GetLLVMContext())
            }
            return unsafe { LLVMPointerType(rawFunctionType, 0u32) }
        }
        return LLVMNullType()
    }

    protected override func GenContainedCGTypes(): Unit {
        let funcTy = (chirType as FuncType).getOrThrow()
        var containedCGTypeIndex: Int64 = 0
        containedCGTypes.add(GetFixedCGType(funcTy.GetReturnType(), containedCGTypeIndex))
        containedCGTypeIndex++
        for (paramTy in funcTy.GetParamTypes()) {
            containedCGTypes.add(GetFixedCGType(paramTy, containedCGTypeIndex))
            containedCGTypeIndex++
        }
        if (let Some(fn) <- chirFunc) {
            for (_ in fn.GetGenericTypeParams()) {
                containedCGTypes.add(CGTIType(cgMod))
            }
            if (fn.GetOuterDeclaredOrExtendedDef().isSome()) {
                containedCGTypes.add(CGTIType(cgMod))
            }
            if (staticMethodType) {
                containedCGTypes.add(CGTIType(cgMod))
            }
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        let rawType = llvmType.getOrThrow()
        size = Int64(cgMod.GetTypeSize(rawType))
        align = Int64(cgMod.GetABITypeAlignment(rawType))
    }

    private func ShouldUseSRet(retCGType: CGType): Bool {
        let retLLVMType = retCGType.GetLLVMType()
        if (!retLLVMType.isNull()) {
            let kind = unsafe { LLVMGetTypeKind(retLLVMType) }
            if (kind == 10 || kind == 11) {
                return true
            }
        }
        return retCGType.GetSize().isNone()
    }

    private func IsVoidLikeReturn(retTy: Type): Bool {
        if (constructorType) {
            return true
        }
        return retTy.IsNothing() || retTy.IsVoid()
    }

    private func GetFixedCGType(paramTy: Type, containedCGTypeIndex: Int64): CGType {
        let paramCGType = CGType.GetOrCreate(cgMod, paramTy)
        let derefParamTy = paramTy.StripAllRefs()
        if (paramTy.IsRef() && derefParamTy.IsStruct()) {
            return CGType.GetOrCreate(cgMod, paramTy, extraInfo: TypeExtraInfo(1u32))
        } else if (paramTy.IsStruct() || paramTy.IsTuple() || (paramCGType.GetSize().isNone() && !paramTy.IsGeneric())) {
            let refType = cgCtx.GetCHIRBuilder().context.GetRefTy(paramTy)
            if (IsFirstStructOrExtendThisParamForContained(containedCGTypeIndex)) {
                return CGType.GetOrCreate(cgMod, refType)
            }
            let addrspace = if (paramCGType.GetSize().isSome()) { 0u32 } else { 1u32 }
            return CGType.GetOrCreate(cgMod, refType, extraInfo: TypeExtraInfo(addrspace))
        } else if (paramCGType.IsStructType() || paramCGType.IsVArrayType()) {
            return CGType.GetOrCreate(cgMod, cgCtx.GetCHIRBuilder().context.GetRefTy(paramTy),
                extraInfo: TypeExtraInfo(0u32))
        } else if (paramCGType.IsStructPtrType() || IsVArrayPtrType(paramCGType)) {
            return CGType.GetOrCreate(cgMod, paramTy, extraInfo: TypeExtraInfo(1u32))
        }
        return CGType.GetOrCreate(cgMod, paramTy)
    }

    private func IsVArrayPtrType(cgType: CGType): Bool {
        if (!cgType.IsPointerType()) {
            return false
        }
        let contained = cgType.GetContainedTypes()
        return !contained.isEmpty() && contained[0].IsVArrayType()
    }

    private func IsFirstStructOrExtendThisParam(containedCGTypeIndex: Int64): Bool {
        if (forWrapper || containedCGTypeIndex != 1 || chirFunc.isNone()) {
            return false
        }
        let fn = chirFunc.getOrThrow()
        return !fn.TestAttr(Attribute.STATIC) && IsStructOrExtendMethod(fn)
    }

    private func IsFirstStructOrExtendThisParamForContained(containedCGTypeIndex: Int64): Bool {
        if (forWrapper || containedCGTypeIndex != 1 || chirFunc.isNone()) {
            return false
        }
        return IsStructOrExtendMethod(chirFunc.getOrThrow())
    }

}
