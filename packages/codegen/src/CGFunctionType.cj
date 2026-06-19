package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.VoidType

private func ChirFunctionTypeOf(chirFunc: Function): Type {
    if (let Some(fnTy) <- chirFunc.GetType()) {
        return fnTy
    }
    return FuncType(ArrayList<Type>(), VoidType())
}

public class CGFunctionType <: CGType {
    private var hasSRet: Bool = false
    private var hasBasePtr: Bool = false
    private var llvmFunctionType: Option<LLVMTypeRef> = None
    private let realParamIndices: ArrayList<Int64> = ArrayList<Int64>()
    private let chirFunc: Option<Function>
    private let allowBasePtr: Bool
    private let methodType: Bool
    private let staticMethodType: Bool
    private let forWrapper: Bool
    private let constructorType: Bool

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: FuncType, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_FUNCTION)
        chirFunc = None
        allowBasePtr = extraInfo.allowBasePtr
        methodType = extraInfo.isMethod
        staticMethodType = extraInfo.isStaticMethod
        forWrapper = extraInfo.forWrapper
        constructorType = false
    }

    public init(cgMod: CGModule, cgCtx: CGContext, chirFunc: Function, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, ChirFunctionTypeOf(chirFunc), cgTypeKind: CGTypeKind.CG_FUNCTION)
        this.chirFunc = chirFunc
        allowBasePtr = extraInfo.allowBasePtr
        methodType = chirFunc.GetParentCustomTypeDef().isSome()
        staticMethodType = chirFunc.TestAttr(Attribute.STATIC)
        forWrapper = extraInfo.forWrapper
        constructorType = chirFunc.IsConstructor()
    }

    public func HasSRet(): Bool { Complete(); return hasSRet }
    public func HasBasePtr(): Bool { Complete(); return hasBasePtr }
    public func IsMethodType(): Bool { return methodType }
    public func IsStaticMethodType(): Bool { return staticMethodType }
    public func IsConstructorType(): Bool { return constructorType }
    public func GetRealArgIndices(): ArrayList<Int64> { return realParamIndices }

    public func GetLLVMFunctionType(): LLVMTypeRef {
        Complete()
        if (let Some(rawFunctionTy) <- llvmFunctionType) {
            return rawFunctionTy
        }
        return GetLLVMType()
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (let Some(funcTy) <- (chirType as FuncType)) {
            let retCGType = CGType.GetOrCreate(cgMod, funcTy.GetReturnType())
            let retTy = funcTy.GetReturnType()
            hasSRet = !IsVoidLikeReturn(retTy) && ShouldUseSRet(retTy, retCGType)
            let retLLVMType = if (IsVoidLikeReturn(retTy) || hasSRet) {
                unsafe { LLVMVoidTypeInContext(cgCtx.GetLLVMContext().raw) }
            } else {
                retCGType.GetLLVMType()
            }
            let paramLLVMTypes = ArrayList<LLVMTypeRef>()
            if (hasSRet) {
                if (ContainsGenericType(retTy) && !retTy.IsGeneric()) {
                    paramLLVMTypes.add(CGType.GetRefType(cgCtx.GetLLVMContext()))
                } else {
                    let sretAddrspace = if (retCGType.GetSize().isNone() && !retTy.IsGeneric()) { 1u32 } else { 0u32 }
                    paramLLVMTypes.add(unsafe { LLVMPointerType(retCGType.GetLLVMType(), sretAddrspace) })
                }
            }
            realParamIndices.clear()
            for (paramTy in funcTy.GetParamTypes()) {
                realParamIndices.add(paramLLVMTypes.size)
                let derefParamTy = paramTy.StripAllRefs()
                if (paramTy.IsRef() && (derefParamTy.IsStruct() || derefParamTy.IsTuple())) {
                    let derefParamCGType = CGType.GetOrCreate(cgMod, derefParamTy)
                    paramLLVMTypes.add(unsafe { LLVMPointerType(derefParamCGType.GetLLVMType(), 1u32) })
                    if (allowBasePtr) {
                        paramLLVMTypes.add(CGType.GetRefType(cgCtx.GetLLVMContext()))
                        hasBasePtr = true
                    }
                } else {
                    let paramCGType = CGType.GetOrCreate(cgMod, paramTy)
                    if (ShouldNeedBasePtr(paramTy) && allowBasePtr) {
                        paramLLVMTypes.add(unsafe { LLVMPointerType(paramCGType.GetLLVMType(), 0u32) })
                    } else {
                        paramLLVMTypes.add(paramCGType.GetLLVMType())
                    }
                }
            }
            if (methodType) {
                paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
            }
            if (staticMethodType) {
                paramLLVMTypes.add(CGType.GetOrCreateTypeInfoPtrType(cgCtx.GetLLVMContext()))
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
                return unsafe { LLVMPointerType(rawFunctionType, 0u32) }
            }
            return LLVMNullType()
        }
        let voidTy = unsafe { LLVMVoidTypeInContext(cgCtx.GetLLVMContext().raw) }
        llvmFunctionType = unsafe { LLVMFunctionType(voidTy, CPointer<LLVMTypeRef>(), 0u32, 0) }
        if (let Some(rawFallbackType) <- llvmFunctionType) {
            return unsafe { LLVMPointerType(rawFallbackType, 0u32) }
        }
        return LLVMNullType()
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(funcTy) <- (chirType as FuncType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, funcTy.GetReturnType()))
            for (paramTy in funcTy.GetParamTypes()) {
                containedCGTypes.add(CGType.GetOrCreate(cgMod, paramTy))
            }
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }

    private func ShouldUseSRet(retTy: Type, retCGType: CGType): Bool {
        if (retTy.IsReferenceType() || retTy.IsRef() || retCGType.IsReference()) {
            return false
        }
        return retTy.IsUnit() || retTy.IsStruct() || retTy.IsTuple() || retTy.IsVArray() ||
            (ContainsGenericType(retTy) && !retTy.IsReferenceType()) || retCGType.GetSize().isNone()
    }

    private func IsVoidLikeReturn(retTy: Type): Bool {
        if (constructorType) {
            return true
        }
        return retTy.IsNothing() || retTy.IsVoid()
    }

    private func ShouldNeedBasePtr(paramTy: Type): Bool {
        return paramTy.IsStruct() || paramTy.IsTuple()
    }
}
