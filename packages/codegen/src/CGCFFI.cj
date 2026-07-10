package cjcj::codegen

import std.collection.*
import cjcj::chir.FuncType
import cjcj::chir.StructType
import cjcj::chir.Type
import cjcj::chir.TypeKind
import cjcj::chir.VArrayType
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG}

private let BITS_PER_BYTE: UInt64 = 8u64
private let BYTES_PER_WORD: UInt64 = 8u64
private let MAX_SPLIT_NUM: Int64 = 2
private let MAX_FIELD_NUM: Int64 = 8

private let LLVM_VOID_TYPE_KIND: Int32 = 0
private let LLVM_HALF_TYPE_KIND: Int32 = 1
private let LLVM_FLOAT_TYPE_KIND: Int32 = 2
private let LLVM_DOUBLE_TYPE_KIND: Int32 = 3
private let LLVM_X86_FP80_TYPE_KIND: Int32 = 4
private let LLVM_FP128_TYPE_KIND: Int32 = 5
private let LLVM_PPC_FP128_TYPE_KIND: Int32 = 6
private let LLVM_INTEGER_TYPE_KIND: Int32 = 8
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let LLVM_ARRAY_TYPE_KIND: Int32 = 11
private let LLVM_POINTER_TYPE_KIND: Int32 = 12

public enum ProcessKind {
    | NO_PROCESS
    | SKIP
    | DIRECT
    | INDIRECT
    | EXPAND
}

private func ProcessKindIndex(kind: ProcessKind): Int64 {
    return match (kind) {
        case ProcessKind.NO_PROCESS => 0
        case ProcessKind.SKIP => 1
        case ProcessKind.DIRECT => 2
        case ProcessKind.INDIRECT => 3
        case ProcessKind.EXPAND => 4
    }
}

extend ProcessKind <: Equatable<ProcessKind> {
    public operator func ==(right: ProcessKind): Bool { return ProcessKindIndex(this) == ProcessKindIndex(right) }
    public operator func !=(right: ProcessKind): Bool { return !(this == right) }
}

public enum WordClass {
    | NO_CLASS
    | INTEGER
    | SSE
    | SSEUP
    | X87
    | X87UP
    | COMPLEX_X87
    | MEMORY
}

private func WordClassIndex(kind: WordClass): Int64 {
    return match (kind) {
        case WordClass.NO_CLASS => 0
        case WordClass.INTEGER => 1
        case WordClass.SSE => 2
        case WordClass.SSEUP => 3
        case WordClass.X87 => 4
        case WordClass.X87UP => 5
        case WordClass.COMPLEX_X87 => 6
        case WordClass.MEMORY => 7
    }
}

extend WordClass <: Equatable<WordClass> {
    public operator func ==(right: WordClass): Bool { return WordClassIndex(this) == WordClassIndex(right) }
    public operator func !=(right: WordClass): Bool { return !(this == right) }
}

public class ABIArgInfo {
    private let types: ArrayList<LLVMTypeRef> = ArrayList<LLVMTypeRef>()

    private init() {}

    public static func GetIndirect(): ABIArgInfo {
        return ABIArgInfo()
    }

    public static func GetDirect(ty: LLVMTypeRef): ABIArgInfo {
        let ai = ABIArgInfo()
        ai.types.add(ty)
        return ai
    }

    public static func GetExpand(ty1: LLVMTypeRef, ty2: LLVMTypeRef): ABIArgInfo {
        let ai = ABIArgInfo()
        ai.types.add(ty1)
        ai.types.add(ty2)
        return ai
    }

    public func IsDirect(): Bool {
        return types.size == 1
    }

    public func IsIndirect(): Bool {
        return types.isEmpty()
    }

    public func IsExpand(): Bool {
        return types.size == MAX_SPLIT_NUM
    }

    public func ArgNums(): Int64 {
        return types.size
    }

    public operator func [](idx: Int64): LLVMTypeRef {
        CJC_ASSERT(idx >= 0 && idx < types.size)
        return types[idx]
    }
}

public class LLVMFuncArgIt {
    private let llvmFunc: LLVMValueRef
    public var idx: UInt32

    public init(llvmFunc: LLVMValueRef, idx: UInt32) {
        this.llvmFunc = llvmFunc
        this.idx = idx
    }

    public func GetValue(): LLVMValueRef {
        return unsafe { LLVMGetParam(llvmFunc, idx) }
    }

    public func GetType(): LLVMTypeRef {
        return unsafe { LLVMTypeOf(GetValue()) }
    }

    public func Increment(): Unit {
        idx++
    }
}

public class CFuncInfo {
    public let llvmFunctionType: LLVMTypeRef
    public let kinds: ArrayList<ProcessKind>

    public init(llvmFunctionType: LLVMTypeRef, kinds: ArrayList<ProcessKind>) {
        this.llvmFunctionType = llvmFunctionType
        this.kinds = kinds
    }
}

public open class CGCFFI {
    public init() {}

    public open func GetCFuncType(_: FuncType): LLVMTypeRef {
        CJC_ASSERT(false)
        return LLVMNullType()
    }

    public open func AddFunctionAttr(_: FuncType, _: LLVMValueRef): Unit {
        CJC_ASSERT(false)
    }

    public open func NeedProcessParam(_: FuncType, _: Int64): Bool {
        CJC_ASSERT(false)
        return false
    }

    public open func ProcessParam(_: Type, _: LLVMFuncArgIt, _: LLVMValueRef, _: IRBuilder2): Unit {
        CJC_ASSERT(false)
    }

    public open func ProcessInvocation(_: FuncType, _: ArrayList<CGValue>, _: IRBuilder2): Bool {
        CJC_ASSERT(false)
        return false
    }

    public open func ProcessCallRet(chirRetTy: Type, ret: LLVMValueRef, sret: LLVMValueRef,
        builder: IRBuilder2): LLVMValueRef {
        let retType = unsafe { LLVMTypeOf(ret) }
        let place = builder.CreateEntryAlloca(retType, name: "cffi")
        builder.CreateStore(ret, place)
        let cgMod = builder.GetCGModule()
        let actualSize = GetTypeSize(cgMod, chirRetTy)
        builder.CreateMemCpy(sret, UInt32(GetTypeAlignment(cgMod, chirRetTy)), place,
            UInt32(GetTypeAlignment(cgMod, retType)), SizeValue(builder, actualSize))
        return sret
    }

    public open func ProcessRetValue(_: LLVMTypeRef, _: LLVMValueRef, _: IRBuilder2): LLVMValueRef {
        CJC_ASSERT(false)
        return LLVMNullValue()
    }
}

public open class LinuxCJNativeCGCFFI <: CGCFFI {
    protected let ctx: CGContext
    protected let cgMod: CGModule
    protected let typeMap: ArrayList<(Type, ABIArgInfo)> = ArrayList<(Type, ABIArgInfo)>()
    protected let cfuncMap: ArrayList<(FuncType, CFuncInfo)> = ArrayList<(FuncType, CFuncInfo)>()

    public init(cgMod: CGModule) {
        super()
        this.cgMod = cgMod
        ctx = cgMod.GetCGContext()
    }

    public override func ProcessInvocation(chirFuncTy: FuncType, args: ArrayList<CGValue>,
        builder: IRBuilder2): Bool {
        let found = match (FindCFuncInfo(chirFuncTy)) {
            case Some(foundInfo) => foundInfo
            case None => return false
        }
        let kinds = found.kinds
        var kindIdx: Int64 = 0
        let argIdx = Int64Box(0)
        while (kindIdx < kinds.size) {
            while (kindIdx < kinds.size && kinds[kindIdx] == ProcessKind.SKIP) {
                kindIdx++
            }
            if (kindIdx >= kinds.size) {
                break
            }
            if (kinds[kindIdx] == ProcessKind.NO_PROCESS) {
                kindIdx++
                argIdx.value++
                continue
            }
            let paramTy = (chirFuncTy.GetParamType(kindIdx) as StructType).getOrThrow()
            ProcessInvocationArg(paramTy, kinds[kindIdx], argIdx, args, builder)
            kindIdx++
            argIdx.value++
        }
        let foundRet = match (FindABIArgInfo(typeMap, chirFuncTy.GetReturnType())) {
            case Some(foundInfo) => foundInfo
            case None => return false
        }
        return !foundRet.IsIndirect()
    }

    public override func NeedProcessParam(chirFuncTy: FuncType, idx: Int64): Bool {
        let found = match (FindCFuncInfo(chirFuncTy)) {
            case Some(foundInfo) => foundInfo
            case None => return false
        }
        CJC_ASSERT(idx >= 0 && idx < chirFuncTy.GetNumOfParams())
        let paramTy = chirFuncTy.GetParamType(idx)
        if (paramTy.IsVArray()) {
            return true
        }
        let kinds = found.kinds
        return idx < kinds.size && (kinds[idx] == ProcessKind.DIRECT || kinds[idx] == ProcessKind.EXPAND)
    }

    protected func GetReturnType(chirTy: Type, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (IsUnitOrNothing(chirTy)) {
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        if (IsUnsizedStructTy(chirTy)) {
            return LLVMNullType()
        }
        if (let Some(structTy) <- (chirTy as StructType)) {
            return GetStructReturnType(structTy, params)
        }
        return GetLLVMType(chirTy)
    }

    protected func IsUnsizedStructTy(chirTy: Type): Bool {
        return chirTy.IsStruct() && unsafe { LLVMTypeIsSized(GetLLVMType(chirTy)) } == 0
    }

    protected func GetLLVMType(chirTy: Type): LLVMTypeRef {
        return CGType.GetOrCreate(cgMod, chirTy).GetLLVMType()
    }

    protected open func ProcessInvocationArg(_: StructType, _: ProcessKind, _: Int64Box,
        _: ArrayList<CGValue>, _: IRBuilder2): Unit {
        CJC_ASSERT(false)
    }

    protected open func GetStructReturnType(_: StructType, _: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        CJC_ASSERT(false)
        return LLVMNullType()
    }

    protected func FindCFuncInfo(chirFuncTy: FuncType): Option<CFuncInfo> {
        for ((cachedTy, cachedInfo) in cfuncMap) {
            if (refEq(cachedTy, chirFuncTy)) {
                return cachedInfo
            }
        }
        return None
    }

    protected func SetCFuncInfo(chirFuncTy: FuncType, functionType: LLVMTypeRef,
        kinds: ArrayList<ProcessKind>): LLVMTypeRef {
        let info = CFuncInfo(functionType, kinds)
        var idx: Int64 = 0
        while (idx < cfuncMap.size) {
            if (refEq(cfuncMap[idx][0], chirFuncTy)) {
                cfuncMap[idx] = (chirFuncTy, info)
                return functionType
            }
            idx++
        }
        cfuncMap.add((chirFuncTy, info))
        return functionType
    }
}

public class LinuxAmd64CJNativeCGCFFI <: LinuxCJNativeCGCFFI {
    public init(cgMod: CGModule) {
        super(cgMod)
    }

    public override func GetCFuncType(chirFuncTy: FuncType): LLVMTypeRef {
        if (let Some(found) <- FindCFuncInfo(chirFuncTy)) {
            return found.llvmFunctionType
        }
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let intNum = Int64Box(6)
        let sseNum = Int64Box(8)
        let paramTys = ArrayList<LLVMTypeRef>()
        let kinds = ArrayList<ProcessKind>()
        let retTy = GetReturnType(chirFuncTy.GetReturnType(), paramTys)
        if (retTy.isNull()) {
            return LLVMNullType()
        }
        for (paramTy in chirFuncTy.GetParamTypes()) {
            CJC_ASSERT(IsMetCType(paramTy))
            if (IsUnsizedStructTy(paramTy)) {
                return LLVMNullType()
            }
            kinds.add(GetParamType(paramTy, intNum, sseNum, paramTys))
        }
        return SetCFuncInfo(chirFuncTy, CreateFunctionType(retTy, paramTys, chirFuncTy.HasVarArg()), kinds)
    }

    public override func AddFunctionAttr(chirFuncTy: FuncType, llvmFunc: LLVMValueRef): Unit {
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let found = match (FindCFuncInfo(chirFuncTy)) {
            case Some(foundInfo) => foundInfo
            case None => return
        }
        var argIdx: UInt32 = 0u32
        if (let Some(foundRet) <- FindABIArgInfo(typeMap, chirFuncTy.GetReturnType())) {
            if (foundRet.IsIndirect()) {
                AddSRetAttribute(llvmFunc, GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, 0u32)) }))
                argIdx++
            } else if (isIntegerTy(unsafe { LLVMGetReturnType(found.llvmFunctionType) }, 1u32)) {
                AddRetAttr(llvmFunc, "zeroext")
            }
        } else if (isIntegerTy(unsafe { LLVMGetReturnType(found.llvmFunctionType) }, 1u32)) {
            AddRetAttr(llvmFunc, "zeroext")
        }
        let kinds = found.kinds
        var kindIdx: Int64 = 0
        while (kindIdx < kinds.size) {
            while (kindIdx < kinds.size && kinds[kindIdx] == ProcessKind.SKIP) {
                kindIdx++
            }
            if (kindIdx >= kinds.size) {
                break
            }
            let argType = unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, argIdx)) }
            if (isIntegerTy(argType, 1u32)) {
                AddParamAttr(llvmFunc, argIdx, "zeroext")
                kindIdx++
                argIdx++
                continue
            }
            if (kinds[kindIdx] == ProcessKind.EXPAND) {
                kindIdx++
                argIdx += 2u32
                continue
            }
            if (kinds[kindIdx] == ProcessKind.INDIRECT) {
                CJC_ASSERT(IsStructPtrTy(argType))
                AddByValAttribute(llvmFunc, argIdx, GetPointerElementType(argType), align: GetTypeAlignment(cgMod, argType))
            }
            kindIdx++
            argIdx++
        }
        AddFnAttr(llvmFunc, CFUNC_ATTR)
    }

    public override func ProcessParam(chirParamTy: Type, arg: LLVMFuncArgIt, place: LLVMValueRef,
        builder: IRBuilder2): Unit {
        if (!chirParamTy.IsStruct()) {
            return
        }
        let info = match (FindABIArgInfo(typeMap, chirParamTy)) {
            case Some(found) => found
            case None => return
        }
        if (info.IsDirect()) {
            let castPlace = builder.CreateBitCast(place, unsafe { LLVMPointerType(arg.GetType(), 0u32) })
            builder.CreateStore(arg.GetValue(), castPlace)
        } else if (info.IsExpand()) {
            let arg1 = arg.GetValue()
            arg.Increment()
            let arg2 = arg.GetValue()
            let destTy = CreateStructType(ctx, MakeTypeList(info[0], info[1]))
            let alloca = builder.CreateEntryAlloca(destTy)
            let part0 = builder.CreateStructGEP(destTy, alloca, 0u32)
            builder.CreateStore(arg1, part0)
            let part1 = builder.CreateStructGEP(destTy, alloca, 1u32)
            builder.CreateStore(arg2, part1)
            builder.CreateMemCpy(place, UInt32(GetTypeAlignment(cgMod, chirParamTy)), alloca,
                UInt32(GetTypeAlignment(cgMod, destTy)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        }
    }

    public override func ProcessRetValue(retType: LLVMTypeRef, value: LLVMValueRef, builder: IRBuilder2): LLVMValueRef {
        CJC_ASSERT(!isVoidTy(retType))
        if (isStructTy(retType) && unsafe { LLVMIsLiteralStruct(retType) } != 0) {
            let tmpVal = builder.CreateBitCast(value, unsafe { LLVMPointerType(retType, 0u32) })
            return builder.CreateLoad(retType, tmpVal)
        }
        var castRes = value
        if (!isStructTy(retType) && IsStructPtrTy(unsafe { LLVMTypeOf(value) })) {
            castRes = builder.CreateBitCast(value, unsafe { LLVMPointerType(retType, 0u32) })
        }
        return builder.CreateLoad(retType, castRes)
    }

    protected override func ProcessInvocationArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64Box,
        args: ArrayList<CGValue>, builder: IRBuilder2): Unit {
        if (kind == ProcessKind.INDIRECT) {
            return
        }
        let info = FindABIArgInfo(typeMap, chirParamTy).getOrThrow()
        if (kind == ProcessKind.DIRECT) {
            CJC_ASSERT(info.IsDirect())
            let rawArg = args[argIdx.value].GetRawValue()
            let argRawType = unsafe { LLVMTypeOf(rawArg) }
            let addrSpace = unsafe { LLVMGetPointerAddressSpace(argRawType) }
            let cast = builder.CreateBitCast(rawArg, unsafe { LLVMPointerType(info[0], addrSpace) })
            args[argIdx.value] = cgMod.CreateGhostCFuncArgValue(builder.CreateLoad(info[0], cast),
                GetCGType(cgMod, info[0]))
            return
        }
        CJC_ASSERT(info.IsExpand())
        let tmpTy = CreateStructType(ctx, MakeTypeList(info[0], info[1]))
        let alloca = builder.CreateEntryAlloca(tmpTy, name: "arg.copy")
        builder.CreateMemCpy(alloca, UInt32(GetTypeAlignment(cgMod, tmpTy)), args[argIdx.value].GetRawValue(),
            UInt32(GetTypeAlignment(cgMod, chirParamTy)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        let argPtr1 = builder.CreateStructGEP(tmpTy, alloca, 0u32)
        let argPtr2 = builder.CreateStructGEP(tmpTy, alloca, 1u32)
        InsertCGValue(args, argIdx.value, cgMod.CreateGhostCFuncArgValue(builder.CreateLoad(info[0], argPtr1),
            GetCGType(cgMod, info[0])))
        argIdx.value++
        args[argIdx.value] = cgMod.CreateGhostCFuncArgValue(builder.CreateLoad(info[1], argPtr2),
            GetCGType(cgMod, info[1]))
    }

    protected override func GetStructReturnType(chirTy: StructType, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (GetTypeSize(cgMod, chirTy) == 0u64) {
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        let info = GetMappingArgInfo(chirTy, false)
        if (info.IsIndirect()) {
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            params.add(unsafe { LLVMPointerType(structType, 0u32) })
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        if (info.IsDirect()) {
            return info[0]
        }
        return CreateStructType(ctx, MakeTypeList(info[0], info[1]))
    }

    private func GetParamType(chirTy: Type, intNum: Int64Box, sseNum: Int64Box,
        params: ArrayList<LLVMTypeRef>): ProcessKind {
        CJC_ASSERT(!IsUnitOrNothing(chirTy))
        if (let Some(structTy) <- (chirTy as StructType)) {
            if (GetTypeSize(cgMod, chirTy) == 0u64) {
                return ProcessKind.SKIP
            }
            let info = GetMappingArgInfo(structTy, true)
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            if (info.IsIndirect()) {
                params.add(unsafe { LLVMPointerType(structType, 0u32) })
                return ProcessKind.INDIRECT
            }
            let resTy = GetParamType(structType, info, intNum, sseNum)
            if (resTy.isNull()) {
                params.add(info[0])
                params.add(info[1])
                return ProcessKind.EXPAND
            }
            if (!SameLLVMType(resTy, structType)) {
                params.add(resTy)
                return ProcessKind.DIRECT
            }
            params.add(unsafe { LLVMPointerType(structType, 0u32) })
            return ProcessKind.INDIRECT
        }
        var paramType = GetLLVMType(chirTy)
        if (chirTy.IsVArray()) {
            paramType = Int8PtrType(ctx)
        }
        if (isIntOrPtrTy(paramType)) {
            if (intNum.value > 0) {
                intNum.value--
            }
        } else if (isFloatingPointTy(paramType)) {
            if (sseNum.value > 0) {
                sseNum.value--
            }
        }
        params.add(paramType)
        return ProcessKind.NO_PROCESS
    }

    private func GetParamType(ty: LLVMTypeRef, info: ABIArgInfo, intNum: Int64Box,
        sseNum: Int64Box): LLVMTypeRef {
        CJC_ASSERT(!info.IsIndirect())
        if (info.IsDirect()) {
            if (isIntOrPtrTy(info[0]) && intNum.value > 0) {
                intNum.value--
            } else if (isFloatingPointTy(info[0]) && sseNum.value > 0) {
                sseNum.value--
            }
            return info[0]
        }
        CJC_ASSERT(info.IsExpand())
        if (isIntOrPtrTy(info[0]) && isIntOrPtrTy(info[1])) {
            if (intNum.value < 2) {
                return ty
            }
            intNum.value -= 2
            return LLVMNullType()
        }
        if (isFloatingPointTy(info[0]) && isFloatingPointTy(info[1])) {
            if (sseNum.value < 2) {
                return ty
            }
            sseNum.value -= 2
            return LLVMNullType()
        }
        if (intNum.value < 1 || sseNum.value < 1) {
            return ty
        }
        intNum.value--
        sseNum.value--
        return LLVMNullType()
    }

    private func GetMappingArgInfo(chirTy: StructType, isArg: Bool): ABIArgInfo {
        if (let Some(found) <- FindABIArgInfo(typeMap, chirTy)) {
            return found
        }
        let llvmType = GetLLVMType(chirTy)
        let classes = ClassifyType(llvmType)
        var lowPartTy = GetLowPartType(llvmType, classes, isArg)
        if (lowPartTy.isNull()) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
        }
        if (classes.size <= 1 || (isVoidTy(lowPartTy) && classes[1] == WordClass.NO_CLASS)) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(lowPartTy))
        }
        var highPartTy = LLVMNullType()
        if (classes[1] == WordClass.INTEGER) {
            if (classes[0] == WordClass.NO_CLASS) {
                return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
            }
            highPartTy = GetIntegerTypeWithOffset(llvmType, BYTES_PER_WORD, llvmType, BYTES_PER_WORD)
        } else if (classes[1] == WordClass.SSE) {
            if (classes[0] == WordClass.NO_CLASS) {
                return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
            }
            highPartTy = GetSseTypeWithOffset(llvmType, BYTES_PER_WORD, llvmType, BYTES_PER_WORD)
        } else if (classes[1] == WordClass.SSEUP) {
            lowPartTy = unsafe { LLVMFP128TypeInContext(ctx.GetLLVMContext().raw) }
        } else if (classes[1] == WordClass.X87UP) {
            CJC_ASSERT(classes[0] == WordClass.X87)
        } else {
            CJC_ASSERT_WITH_MSG(false, "MEMORY, NO_CLASS, X87, COMPLEX_X87 cannot be here.")
        }
        if (highPartTy.isNull()) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(lowPartTy))
        }
        return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetExpand(lowPartTy, highPartTy))
    }

    private func GetLowPartType(llvmType: LLVMTypeRef, classes: ArrayList<WordClass>, isArg: Bool): LLVMTypeRef {
        var lowPartTy = unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        if (classes[0] == WordClass.NO_CLASS) {
            return lowPartTy
        } else if (classes[0] == WordClass.MEMORY) {
            return LLVMNullType()
        } else if (classes[0] == WordClass.INTEGER) {
            lowPartTy = GetIntegerTypeWithOffset(llvmType, 0u64, llvmType, 0u64)
        } else if (classes[0] == WordClass.SSE) {
            lowPartTy = GetSseTypeWithOffset(llvmType, 0u64, llvmType, 0u64)
        } else if (classes[0] == WordClass.X87) {
            if (isArg) {
                return LLVMNullType()
            }
            lowPartTy = unsafe { LLVMX86FP80TypeInContext(ctx.GetLLVMContext().raw) }
        } else if (classes[0] == WordClass.COMPLEX_X87) {
            if (isArg) {
                return LLVMNullType()
            }
            lowPartTy = unsafe { LLVMX86FP80TypeInContext(ctx.GetLLVMContext().raw) }
        } else {
            CJC_ASSERT_WITH_MSG(false, "SSEUP, X87UP cannot be here.")
        }
        return lowPartTy
    }

    private func ClassifyType(llvmType: LLVMTypeRef): ArrayList<WordClass> {
        let wordSize = (GetTypeSize(cgMod, llvmType) + BYTES_PER_WORD - 1u64) / BYTES_PER_WORD
        let wordClasses = ArrayList<WordClass>()
        var idx: UInt64 = 0u64
        while (idx < wordSize) {
            wordClasses.add(WordClass.NO_CLASS)
            idx++
        }
        if (wordSize > 4u64) {
            FillWithMemory(wordClasses)
            return wordClasses
        }
        ClassifyType(llvmType, wordClasses, 0u64)
        FixupClassification(llvmType, wordClasses)
        return wordClasses
    }

    private func ClassifyType(llvmType: LLVMTypeRef, wordClasses: ArrayList<WordClass>, offset: UInt64): Unit {
        let alignment = GetTypeAlignment(cgMod, llvmType)
        let misAlign = offset % alignment
        if (misAlign != 0u64) {
            var wordIdx = offset / BYTES_PER_WORD
            let end = (offset + GetTypeSize(cgMod, llvmType) + BYTES_PER_WORD - 1u64) / BYTES_PER_WORD
            while (wordIdx < end) {
                UnifyWordClass(wordClasses, Int64(wordIdx), WordClass.MEMORY)
                wordIdx++
            }
            return
        }
        let wordOffset = Int64(offset / BYTES_PER_WORD)
        if (isIntOrPtrTy(llvmType)) {
            UnifyWordClass(wordClasses, wordOffset, WordClass.INTEGER)
        } else if (isFloatingPointTy(llvmType)) {
            let bits = getPrimitiveSizeInBits(llvmType)
            if (bits == 16u64 || bits == 32u64 || bits == 64u64) {
                UnifyWordClass(wordClasses, wordOffset, WordClass.SSE)
            } else if (bits == 80u64) {
                UnifyWordClass(wordClasses, wordOffset, WordClass.X87)
                UnifyWordClass(wordClasses, wordOffset + 1, WordClass.X87UP)
            } else {
                CJC_ASSERT_WITH_MSG(false, "Bits in FloatingPointTy are wrong.")
            }
        } else if (isStructTy(llvmType)) {
            ClassifyStructType(GetStructElements(llvmType), wordClasses, offset)
        } else if (isArrayTy(llvmType)) {
            let elemNum = unsafe { LLVMGetArrayLength(llvmType) }
            let elemType = GetPointerElementType(llvmType)
            var elemIdx: UInt32 = 0u32
            var elemOffset = offset
            while (elemIdx < elemNum) {
                ClassifyType(elemType, wordClasses, elemOffset)
                elemOffset += GetTypeSize(cgMod, elemType)
                elemIdx++
            }
        } else {
            CJC_ASSERT_WITH_MSG(false, "Unsupported type.")
        }
    }

    private func ClassifyStructType(fields: ArrayList<LLVMTypeRef>, wordClasses: ArrayList<WordClass>,
        offset: UInt64): Unit {
        if (fields.isEmpty()) {
            return
        }
        var fieldOffset = offset
        for (field in fields) {
            fieldOffset = AlignedUpTo(cgMod, fieldOffset, field)
            ClassifyType(field, wordClasses, fieldOffset)
            fieldOffset += GetTypeSize(cgMod, field)
        }
    }

    private func FixupClassification(llvmType: LLVMTypeRef, wordClasses: ArrayList<WordClass>): Unit {
        var idx: Int64 = 0
        if (wordClasses.size > MAX_SPLIT_NUM && isStructTy(llvmType)) {
            if (wordClasses[idx] != WordClass.SSE) {
                FillWithMemory(wordClasses)
                return
            }
            idx++
            while (idx < wordClasses.size) {
                if (wordClasses[idx] != WordClass.SSEUP) {
                    FillWithMemory(wordClasses)
                    return
                }
                idx++
            }
            return
        }
        while (idx < wordClasses.size) {
            if (wordClasses[idx] == WordClass.MEMORY || wordClasses[idx] == WordClass.X87UP) {
                FillWithMemory(wordClasses)
                return
            }
            if (wordClasses[idx] == WordClass.SSE) {
                do {
                    idx++
                } while (idx < wordClasses.size && wordClasses[idx] == WordClass.SSEUP)
            } else if (wordClasses[idx] == WordClass.X87) {
                do {
                    idx++
                } while (idx < wordClasses.size && wordClasses[idx] == WordClass.X87UP)
            } else {
                idx++
            }
        }
    }

    private func GetIntegerTypeWithOffset(curType: LLVMTypeRef, offset: UInt64, srcType: LLVMTypeRef,
        srcOffset: UInt64): LLVMTypeRef {
        CJC_ASSERT(srcOffset == 0u64 || srcOffset == BYTES_PER_WORD)
        if (offset == 0u64) {
            let typeSize = GetTypeSize(cgMod, curType)
            if (isIntOrPtrTy(curType) && typeSize == BYTES_PER_WORD) {
                return curType
            }
            if (isIntOrPtrTy(curType) && (typeSize == 1u64 || typeSize == 2u64 || typeSize == 4u64) &&
                ContainsUselessBits(srcType, AsBits(srcOffset + typeSize), AsBits(srcOffset + BYTES_PER_WORD))) {
                return curType
            }
        }
        if (isStructTy(curType) && offset < GetTypeSize(cgMod, curType)) {
            let fieldOffsets = CalcFieldOffsets(curType)
            let fieldIdx = GetFieldContainsOffset(fieldOffsets, offset)
            let relOffset = offset - fieldOffsets[fieldIdx]
            return GetIntegerTypeWithOffset(GetStructElementType(curType, fieldIdx), relOffset, srcType, srcOffset)
        }
        let typeSize = GetTypeSize(cgMod, srcType)
        CJC_ASSERT(typeSize != srcOffset)
        let intSize = MinUInt64(typeSize - srcOffset, BYTES_PER_WORD)
        return unsafe { LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(AsBits(intSize))) }
    }

    private func GetSseTypeWithOffset(curType: LLVMTypeRef, offset: UInt64, srcType: LLVMTypeRef,
        srcOffset: UInt64): LLVMTypeRef {
        CJC_ASSERT(srcOffset == 0u64 || srcOffset == BYTES_PER_WORD)
        let bytesOfHalfWord = 4u64
        if (ContainsUselessBits(srcType, AsBits(srcOffset + bytesOfHalfWord), AsBits(srcOffset + BYTES_PER_WORD))) {
            return unsafe { LLVMFloatTypeInContext(ctx.GetLLVMContext().raw) }
        }
        if (ContainsFloatAtOffset(curType, offset) && ContainsFloatAtOffset(curType, offset + bytesOfHalfWord)) {
            return unsafe { LLVMVectorType(LLVMFloatTypeInContext(ctx.GetLLVMContext().raw), 2u32) }
        }
        return unsafe { LLVMDoubleTypeInContext(ctx.GetLLVMContext().raw) }
    }

    private func ContainsUselessBits(llvmType: LLVMTypeRef, start: UInt64, end: UInt64): Bool {
        CJC_ASSERT(start <= end)
        if (AsBits(GetTypeSize(cgMod, llvmType)) <= start) {
            return true
        }
        if (isStructTy(llvmType)) {
            let fieldOffsets = CalcFieldOffsets(llvmType)
            let fields = GetStructElements(llvmType)
            var idx: Int64 = 0
            while (idx < fields.size) {
                let fieldOffset = fieldOffsets[idx]
                let fieldOffsetBits = AsBits(fieldOffset)
                if (fieldOffsetBits >= end) {
                    break
                }
                let fieldStart = if (fieldOffsetBits < start) { start - fieldOffsetBits } else { 0u64 }
                if (!ContainsUselessBits(fields[idx], fieldStart, end - fieldOffsetBits)) {
                    return false
                }
                idx++
            }
            return true
        }
        return false
    }

    private func CalcFieldOffsets(llvmType: LLVMTypeRef): ArrayList<UInt64> {
        let offsets = ArrayList<UInt64>()
        let fields = GetStructElements(llvmType)
        CJC_ASSERT(fields.size <= MAX_FIELD_NUM)
        var offset: UInt64 = 0u64
        for (field in fields) {
            offset = AlignedUpTo(cgMod, offset, field)
            offsets.add(offset)
            offset += GetTypeSize(cgMod, field)
        }
        return offsets
    }

    private func GetFieldContainsOffset(fieldOffsets: ArrayList<UInt64>, offset: UInt64): Int64 {
        var idx: Int64 = 0
        while (idx + 1 < fieldOffsets.size) {
            if (fieldOffsets[idx] <= offset && fieldOffsets[idx + 1] > offset) {
                break
            }
            idx++
        }
        return idx
    }

    private func ContainsFloatAtOffset(llvmType: LLVMTypeRef, offset: UInt64): Bool {
        if (offset == 0u64 && isFloatTy(llvmType)) {
            return true
        }
        if (isStructTy(llvmType)) {
            let fieldOffsets = CalcFieldOffsets(llvmType)
            let fieldIdx = GetFieldContainsOffset(fieldOffsets, offset)
            let relOffset = offset - fieldOffsets[fieldIdx]
            return ContainsFloatAtOffset(GetStructElementType(llvmType, fieldIdx), relOffset)
        }
        return false
    }
}

public open class LinuxAarch64CJNativeCGCFFI <: LinuxCJNativeCGCFFI {
    public init(cgMod: CGModule) {
        super(cgMod)
    }

    public open override func GetCFuncType(chirFuncTy: FuncType): LLVMTypeRef {
        if (let Some(found) <- FindCFuncInfo(chirFuncTy)) {
            return found.llvmFunctionType
        }
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let paramTys = ArrayList<LLVMTypeRef>()
        let kinds = ArrayList<ProcessKind>()
        let retTy = GetReturnType(chirFuncTy.GetReturnType(), paramTys)
        if (retTy.isNull()) {
            return LLVMNullType()
        }
        for (paramTy in chirFuncTy.GetParamTypes()) {
            CJC_ASSERT(IsMetCType(paramTy))
            if (IsUnsizedStructTy(paramTy)) {
                return LLVMNullType()
            }
            let typeSize = GetTypeSize(cgMod, paramTy)
            if (IsUnitOrNothing(paramTy) || typeSize == 0u64) {
                kinds.add(ProcessKind.SKIP)
                continue
            }
            kinds.add(GetParamType(paramTy, paramTys))
        }
        return SetCFuncInfo(chirFuncTy, CreateFunctionType(retTy, paramTys, chirFuncTy.HasVarArg()), kinds)
    }

    public override func AddFunctionAttr(chirFuncTy: FuncType, llvmFunc: LLVMValueRef): Unit {
        CJC_ASSERT(chirFuncTy.IsCFunc())
        if (FindCFuncInfo(chirFuncTy).isNone()) {
            return
        }
        if (let Some(foundRet) <- FindABIArgInfo(typeMap, chirFuncTy.GetReturnType())) {
            if (foundRet.IsIndirect()) {
                AddSRetAttribute(llvmFunc, GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, 0u32)) }))
            }
        }
        AddFnAttr(llvmFunc, CFUNC_ATTR)
    }

    public open override func ProcessParam(chirParamTy: Type, arg: LLVMFuncArgIt, place: LLVMValueRef,
        builder: IRBuilder2): Unit {
        if (!chirParamTy.IsStruct()) {
            return
        }
        let argInfo = match (FindABIArgInfo(typeMap, chirParamTy)) {
            case Some(found) => found
            case None => return
        }
        if (argInfo.IsDirect()) {
            let argType = arg.GetType()
            let alloca = builder.CreateEntryAlloca(argType)
            builder.CreateStore(arg.GetValue(), alloca)
            builder.CreateMemCpy(place, UInt32(GetTypeAlignment(cgMod, chirParamTy)), alloca,
                UInt32(GetTypeAlignment(cgMod, argType)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        }
        CJC_ASSERT(!argInfo.IsExpand())
    }

    public override func ProcessRetValue(retType: LLVMTypeRef, value: LLVMValueRef, builder: IRBuilder2): LLVMValueRef {
        CJC_ASSERT(!isVoidTy(retType))
        var castRes = value
        if (!isStructTy(retType) && IsStructPtrTy(unsafe { LLVMTypeOf(value) })) {
            castRes = builder.CreateBitCast(value, unsafe { LLVMPointerType(retType, 0u32) })
        }
        return builder.CreateLoad(retType, castRes)
    }

    protected open override func ProcessInvocationArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64Box,
        args: ArrayList<CGValue>, builder: IRBuilder2): Unit {
        ProcessAarch64DirectArg(chirParamTy, kind, argIdx.value, args, builder, typeMap)
    }

    protected open override func GetStructReturnType(chirTy: StructType, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (GetTypeSize(cgMod, chirTy) == 0u64) {
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        let argInfo = GetMappingArgInfo(chirTy, false)
        if (argInfo.IsIndirect()) {
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            params.add(unsafe { LLVMPointerType(structType, 0u32) })
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        CJC_ASSERT(argInfo.IsDirect())
        return argInfo[0]
    }

    protected func IsHomogeneousAggregate(llvmType: LLVMTypeRef, baseBox: TypeBox, membersBox: UInt64Box): Bool {
        if (isStructTy(llvmType)) {
            membersBox.value = 0u64
            for (fieldTy in GetStructElements(llvmType)) {
                if (GetTypeSize(cgMod, fieldTy) == 0u64) {
                    continue
                }
                let fdMembers = UInt64Box(0u64)
                if (!IsHomogeneousAggregate(fieldTy, baseBox, fdMembers)) {
                    return false
                }
                membersBox.value += fdMembers.value
            }
            if (baseBox.value.isNull()) {
                return false
            }
            if (GetTypeSize(cgMod, baseBox.value) * membersBox.value != GetTypeSize(cgMod, llvmType)) {
                return false
            }
        } else {
            membersBox.value = 1u64
            if (!isFloatingPointTy(llvmType)) {
                return false
            }
            if (baseBox.value.isNull()) {
                baseBox.value = llvmType
            }
        }
        return membersBox.value > 0u64 && membersBox.value <= 4u64
    }

    protected open func GetParamType(chirTy: Type, params: ArrayList<LLVMTypeRef>): ProcessKind {
        if (let Some(structTy) <- (chirTy as StructType)) {
            let info = GetMappingArgInfo(structTy, true)
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            if (info.IsIndirect()) {
                params.add(unsafe { LLVMPointerType(structType, 0u32) })
                return ProcessKind.INDIRECT
            }
            CJC_ASSERT(info.IsDirect())
            params.add(info[0])
            return ProcessKind.DIRECT
        }
        var paramType = GetLLVMType(chirTy)
        if (chirTy.IsVArray()) {
            paramType = Int8PtrType(ctx)
        }
        params.add(paramType)
        return ProcessKind.NO_PROCESS
    }

    protected open func GetMappingArgInfo(chirTy: StructType, isArg: Bool): ABIArgInfo {
        if (let Some(found) <- FindABIArgInfo(typeMap, chirTy)) {
            return found
        }
        let llvmType = GetLLVMType(chirTy)
        var size = GetTypeSize(cgMod, llvmType)
        let baseBox = TypeBox(LLVMNullType())
        let membersBox = UInt64Box(0u64)
        if (IsHomogeneousAggregate(llvmType, baseBox, membersBox)) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(unsafe {
                LLVMArrayType(baseBox.value, UInt32(membersBox.value))
            }))
        }
        let limitSizeOfSmallStruct = 16u64
        if (size > limitSizeOfSmallStruct) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
        }
        let alignment = GetTypeAlignment(cgMod, llvmType)
        size = AlignedUpTo(size, BYTES_PER_WORD)
        if (alignment < limitSizeOfSmallStruct && size == limitSizeOfSmallStruct) {
            let baseTy = unsafe { LLVMInt64TypeInContext(ctx.GetLLVMContext().raw) }
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(unsafe {
                LLVMArrayType(baseTy, UInt32(size / BYTES_PER_WORD))
            }))
        }
        return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(unsafe {
            LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(size * BITS_PER_BYTE))
        }))
    }

    protected func ProcessAarch64DirectArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64,
        args: ArrayList<CGValue>, builder: IRBuilder2, map: ArrayList<(Type, ABIArgInfo)>): Unit {
        if (kind == ProcessKind.INDIRECT) {
            return
        }
        if (kind != ProcessKind.DIRECT) {
            CJC_ASSERT(false)
            return
        }
        let info = FindABIArgInfo(map, chirParamTy).getOrThrow()
        CJC_ASSERT(info.IsDirect())
        CJC_ASSERT(argIdx < args.size)
        let arg = args[argIdx]
        let actualSize = GetTypeSize(cgMod, chirParamTy)
        if (isIntegerTy(info[0])) {
            let actualIntTy = unsafe { LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(AsBits(actualSize))) }
            let addrSpace = unsafe { LLVMGetPointerAddressSpace(unsafe { LLVMTypeOf(arg.GetRawValue()) }) }
            var tmpVal = builder.CreateBitCast(arg.GetRawValue(), unsafe { LLVMPointerType(actualIntTy, addrSpace) })
            tmpVal = builder.CreateLoad(actualIntTy, tmpVal)
            if (GetTypeSize(cgMod, info[0]) != actualSize) {
                tmpVal = CreateIntCastUnsigned(builder, tmpVal, info[0])
            }
            args[argIdx] = cgMod.CreateGhostCFuncArgValue(tmpVal, GetCGType(cgMod, info[0]))
        } else {
            CJC_ASSERT(isArrayTy(info[0]))
            let tmpVal = builder.CreateEntryAlloca(info[0], name: "arg.copy")
            builder.CreateMemCpy(tmpVal, UInt32(GetTypeAlignment(cgMod, info[0])), arg.GetRawValue(),
                UInt32(GetTypeAlignment(cgMod, chirParamTy)), SizeValue(builder, actualSize))
            args[argIdx] = cgMod.CreateGhostCFuncArgValue(builder.CreateLoad(info[0], tmpVal), GetCGType(cgMod, info[0]))
        }
    }
}

@When[os == "macOS"]
public class MacAArch64CJNativeCGCFFI <: LinuxAarch64CJNativeCGCFFI {
    protected let paramTypeMap: ArrayList<(Type, ABIArgInfo)> = ArrayList<(Type, ABIArgInfo)>()

    public init(cgMod: CGModule) {
        super(cgMod)
    }

    public override func AddFunctionAttr(chirFuncTy: FuncType, llvmFunc: LLVMValueRef): Unit {
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let found = match (FindCFuncInfo(chirFuncTy)) {
            case Some(foundInfo) => foundInfo
            case None => return
        }
        var argIdx: UInt32 = 0u32
        if (let Some(foundRet) <- FindABIArgInfo(typeMap, chirFuncTy.GetReturnType())) {
            if (foundRet.IsIndirect()) {
                AddSRetAttribute(llvmFunc, GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, 0u32)) }))
                argIdx++
            }
        }
        let kinds = found.kinds
        let smallIntThreshold: UInt32 = 32u32
        var kindIdx: Int64 = 0
        while (kindIdx < kinds.size) {
            while (kindIdx < kinds.size && kinds[kindIdx] == ProcessKind.SKIP) {
                kindIdx++
            }
            if (kindIdx >= kinds.size) {
                break
            }
            let argType = chirFuncTy.GetParamType(kindIdx)
            if (argType.IsBoolean() || argType.IsInteger()) {
                AddParamAttr(llvmFunc, argIdx, "noundef")
                let intArgType = unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, argIdx)) }
                if (!isIntegerTy(intArgType) || unsafe { LLVMGetIntTypeWidth(intArgType) } >= smallIntThreshold) {
                    kindIdx++
                    argIdx++
                    continue
                }
                if (argType.IsSignedInteger()) {
                    AddParamAttr(llvmFunc, argIdx, "signext")
                } else {
                    AddParamAttr(llvmFunc, argIdx, "zeroext")
                }
            }
            kindIdx++
            argIdx++
        }
        CJC_ASSERT(argIdx == unsafe { LLVMCountParams(llvmFunc) })
        let retType = chirFuncTy.GetReturnType()
        if (retType.IsBoolean() || retType.IsInteger()) {
            let intRetType = unsafe { LLVMGetReturnType(found.llvmFunctionType) }
            if (!isIntegerTy(intRetType) || unsafe { LLVMGetIntTypeWidth(intRetType) } >= smallIntThreshold) {
                return
            }
            if (retType.IsSignedInteger()) {
                AddRetAttr(llvmFunc, "signext")
            } else {
                AddRetAttr(llvmFunc, "zeroext")
            }
        }
        AddFnAttr(llvmFunc, CFUNC_ATTR)
    }

    public override func ProcessParam(chirParamTy: Type, arg: LLVMFuncArgIt, place: LLVMValueRef,
        builder: IRBuilder2): Unit {
        if (!chirParamTy.IsStruct()) {
            return
        }
        let argInfo = match (FindABIArgInfo(paramTypeMap, chirParamTy)) {
            case Some(found) => found
            case None => return
        }
        if (argInfo.IsDirect()) {
            let argType = arg.GetType()
            let alloca = builder.CreateEntryAlloca(argType)
            builder.CreateStore(arg.GetValue(), alloca)
            builder.CreateMemCpy(place, UInt32(GetTypeAlignment(cgMod, chirParamTy)), alloca,
                UInt32(GetTypeAlignment(cgMod, argType)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        }
        CJC_ASSERT(!argInfo.IsExpand())
    }

    protected override func ProcessInvocationArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64Box,
        args: ArrayList<CGValue>, builder: IRBuilder2): Unit {
        ProcessAarch64DirectArg(chirParamTy, kind, argIdx.value, args, builder, paramTypeMap)
    }

    protected override func GetStructReturnType(chirTy: StructType, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        let llvmType = GetLLVMType(chirTy)
        let size = GetTypeSize(cgMod, llvmType)
        if (size == 0u64) {
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        let baseBox = TypeBox(LLVMNullType())
        let membersBox = UInt64Box(0u64)
        if (IsHomogeneousAggregate(llvmType, baseBox, membersBox)) {
            let info = ABIArgInfo.GetDirect(llvmType)
            SetABIArgInfo(typeMap, chirTy, info)
            return info[0]
        }
        if (size < BYTES_PER_WORD) {
            let resTy = unsafe { LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(size * BITS_PER_BYTE)) }
            let info = ABIArgInfo.GetDirect(resTy)
            SetABIArgInfo(typeMap, chirTy, info)
            return info[0]
        }
        return super.GetStructReturnType(chirTy, params)
    }

    protected override func GetParamType(chirTy: Type, params: ArrayList<LLVMTypeRef>): ProcessKind {
        if (let Some(structTy) <- (chirTy as StructType)) {
            let info = GetMappingArgInfo(structTy, true)
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            if (info.IsIndirect()) {
                params.add(unsafe { LLVMPointerType(structType, 0u32) })
                return ProcessKind.INDIRECT
            }
            CJC_ASSERT(info.IsDirect())
            params.add(info[0])
            return ProcessKind.DIRECT
        }
        var paramType = GetLLVMType(chirTy)
        if (chirTy.IsVArray()) {
            paramType = Int8PtrType(ctx)
        }
        params.add(paramType)
        return ProcessKind.NO_PROCESS
    }

    protected override func GetMappingArgInfo(chirTy: StructType, isArg: Bool): ABIArgInfo {
        let map = if (isArg) { paramTypeMap } else { typeMap }
        if (let Some(found) <- FindABIArgInfo(map, chirTy)) {
            return found
        }
        let llvmType = GetLLVMType(chirTy)
        var size = GetTypeSize(cgMod, llvmType)
        let baseBox = TypeBox(LLVMNullType())
        let membersBox = UInt64Box(0u64)
        if (IsHomogeneousAggregate(llvmType, baseBox, membersBox)) {
            return SetABIArgInfo(map, chirTy, ABIArgInfo.GetDirect(unsafe {
                LLVMArrayType(baseBox.value, UInt32(membersBox.value))
            }))
        }
        let limitSizeOfSmallStruct = 16u64
        if (size > limitSizeOfSmallStruct) {
            return SetABIArgInfo(map, chirTy, ABIArgInfo.GetIndirect())
        }
        let alignment = GetTypeAlignment(cgMod, llvmType)
        size = AlignedUpTo(size, BYTES_PER_WORD)
        if (alignment < limitSizeOfSmallStruct && size == limitSizeOfSmallStruct) {
            let baseTy = unsafe { LLVMInt64TypeInContext(ctx.GetLLVMContext().raw) }
            return SetABIArgInfo(map, chirTy, ABIArgInfo.GetDirect(unsafe {
                LLVMArrayType(baseTy, UInt32(size / BYTES_PER_WORD))
            }))
        }
        return SetABIArgInfo(map, chirTy, ABIArgInfo.GetDirect(unsafe {
            LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(size * BITS_PER_BYTE))
        }))
    }
}

public class WindowsAmd64CJNativeCGCFFI <: LinuxCJNativeCGCFFI {
    public init(cgMod: CGModule) {
        super(cgMod)
    }

    public override func GetCFuncType(chirFuncTy: FuncType): LLVMTypeRef {
        if (let Some(found) <- FindCFuncInfo(chirFuncTy)) {
            return found.llvmFunctionType
        }
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let paramTypes = ArrayList<LLVMTypeRef>()
        let kinds = ArrayList<ProcessKind>()
        let retTy = GetReturnType(chirFuncTy.GetReturnType(), paramTypes)
        if (retTy.isNull()) {
            return LLVMNullType()
        }
        for (paramTy in chirFuncTy.GetParamTypes()) {
            CJC_ASSERT(IsMetCType(paramTy))
            if (IsUnsizedStructTy(paramTy)) {
                return LLVMNullType()
            }
            CJC_ASSERT(!IsUnitOrNothing(paramTy))
            kinds.add(GetParamType(paramTy, paramTypes))
        }
        return SetCFuncInfo(chirFuncTy, CreateFunctionType(retTy, paramTypes, chirFuncTy.HasVarArg()), kinds)
    }

    public override func AddFunctionAttr(chirFuncTy: FuncType, llvmFunc: LLVMValueRef): Unit {
        CJC_ASSERT(chirFuncTy.IsCFunc())
        if (FindCFuncInfo(chirFuncTy).isNone()) {
            return
        }
        let retTy = chirFuncTy.GetReturnType()
        if (retTy.IsBoolean()) {
            AddRetAttr(llvmFunc, "zeroext")
        } else if (let Some(foundRet) <- FindABIArgInfo(typeMap, retTy)) {
            if (foundRet.IsIndirect()) {
                let sretArgType = unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, 0u32)) }
                AddSRetAttribute(llvmFunc, GetPointerElementType(sretArgType))
                AddNoAliasAttribute(llvmFunc)
                AddAlignAttributeAtIndex(llvmFunc, 1u32, GetTypeAlignment(cgMod, GetPointerElementType(sretArgType)))
            }
        }
        let paramCount = unsafe { LLVMCountParams(llvmFunc) }
        var paramIdx: UInt32 = 0u32
        while (paramIdx < paramCount) {
            if (isIntegerTy(unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, paramIdx)) }, 1u32)) {
                AddParamAttr(llvmFunc, paramIdx, "zeroext")
            }
            paramIdx++
        }
        AddFnAttr(llvmFunc, CFUNC_ATTR)
    }

    public override func ProcessParam(chirParamTy: Type, arg: LLVMFuncArgIt, place: LLVMValueRef,
        builder: IRBuilder2): Unit {
        if (!chirParamTy.IsStruct()) {
            return
        }
        let argInfo = match (FindABIArgInfo(typeMap, chirParamTy)) {
            case Some(found) => found
            case None => return
        }
        if (argInfo.IsDirect()) {
            let argType = arg.GetType()
            let alloca = builder.CreateEntryAlloca(argType)
            builder.CreateStore(arg.GetValue(), alloca)
            builder.CreateMemCpy(place, UInt32(GetTypeAlignment(cgMod, chirParamTy)), alloca,
                UInt32(GetTypeAlignment(cgMod, argType)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        }
        CJC_ASSERT(!argInfo.IsExpand())
    }

    public override func ProcessRetValue(retType: LLVMTypeRef, value: LLVMValueRef, builder: IRBuilder2): LLVMValueRef {
        CJC_ASSERT(!isVoidTy(retType))
        var castRes = value
        if (!isStructTy(retType) && IsStructPtrTy(unsafe { LLVMTypeOf(value) })) {
            castRes = builder.CreateBitCast(value, unsafe { LLVMPointerType(retType, 0u32) })
        }
        return builder.CreateLoad(retType, castRes)
    }

    protected override func ProcessInvocationArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64Box,
        args: ArrayList<CGValue>, builder: IRBuilder2): Unit {
        let info = FindABIArgInfo(typeMap, chirParamTy).getOrThrow()
        if (kind == ProcessKind.DIRECT) {
            CJC_ASSERT(info.IsDirect())
            let rawArg = args[argIdx.value].GetRawValue()
            let addrSpace = unsafe { LLVMGetPointerAddressSpace(unsafe { LLVMTypeOf(rawArg) }) }
            let arg = builder.CreateBitCast(rawArg, unsafe { LLVMPointerType(info[0], addrSpace) })
            args[argIdx.value] = cgMod.CreateGhostCFuncArgValue(builder.CreateLoad(info[0], arg),
                GetCGType(cgMod, info[0]))
        } else if (kind == ProcessKind.INDIRECT) {
            CJC_ASSERT(info.IsIndirect())
            let arg = args[argIdx.value]
            let argCGType = arg.GetCGType().getOrThrow()
            let copy = builder.CreateEntryAlloca(argCGType.GetPointerElementType().getOrThrow(), name: "arg.copy")
            let align = UInt32(GetTypeAlignment(cgMod, arg.GetLLVMType()))
            builder.CreateMemCpy(copy, align, arg.GetRawValue(), align, SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
            args[argIdx.value] = cgMod.CreateGhostCFuncArgValue(copy, argCGType)
        } else {
            CJC_ASSERT(false)
        }
    }

    protected override func GetStructReturnType(chirTy: StructType, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        let argInfo = GetMappingArgInfo(chirTy, false)
        if (!argInfo.IsIndirect()) {
            CJC_ASSERT(argInfo.IsDirect())
            return argInfo[0]
        }
        let structType = GetLLVMType(chirTy)
        CJC_ASSERT(isStructTy(structType))
        params.add(unsafe { LLVMPointerType(structType, 0u32) })
        return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
    }

    private func GetParamType(chirTy: Type, params: ArrayList<LLVMTypeRef>): ProcessKind {
        if (let Some(structTy) <- (chirTy as StructType)) {
            let info = GetMappingArgInfo(structTy, true)
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            if (info.IsIndirect()) {
                params.add(unsafe { LLVMPointerType(structType, 0u32) })
                return ProcessKind.INDIRECT
            }
            CJC_ASSERT(info.IsDirect())
            params.add(info[0])
            return ProcessKind.DIRECT
        }
        var paramType = GetLLVMType(chirTy)
        if (chirTy.IsVArray()) {
            paramType = Int8PtrType(ctx)
        }
        params.add(paramType)
        return ProcessKind.NO_PROCESS
    }

    private func GetMappingArgInfo(chirTy: StructType, isArg: Bool): ABIArgInfo {
        if (let Some(found) <- FindABIArgInfo(typeMap, chirTy)) {
            return found
        }
        let llvmType = GetLLVMType(chirTy)
        let size = GetTypeSize(cgMod, llvmType)
        if (size > 8u64 || !(size == 1u64 || size == 2u64 || size == 4u64 || size == 8u64)) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
        }
        return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetDirect(unsafe {
            LLVMIntTypeInContext(ctx.GetLLVMContext().raw, UInt32(AsBits(size)))
        }))
    }
}

public class LinuxOhosArm32CJNativeCGCFFI <: LinuxAarch64CJNativeCGCFFI {
    protected let paramTypeMap: ArrayList<(Type, ABIArgInfo)> = ArrayList<(Type, ABIArgInfo)>()

    public init(cgMod: CGModule) {
        super(cgMod)
    }

    public override func GetCFuncType(chirFuncTy: FuncType): LLVMTypeRef {
        if (let Some(found) <- FindCFuncInfo(chirFuncTy)) {
            return found.llvmFunctionType
        }
        CJC_ASSERT(chirFuncTy.IsCFunc())
        let paramTys = ArrayList<LLVMTypeRef>()
        let kinds = ArrayList<ProcessKind>()
        let retTy = GetReturnType(chirFuncTy.GetReturnType(), paramTys)
        if (retTy.isNull()) {
            return LLVMNullType()
        }
        for (paramTy in chirFuncTy.GetParamTypes()) {
            CJC_ASSERT(IsMetCType(paramTy))
            if (IsUnsizedStructTy(paramTy)) {
                return LLVMNullType()
            }
            let typeSize = GetTypeSize(cgMod, paramTy)
            if (IsUnitOrNothing(paramTy) || typeSize == 0u64) {
                kinds.add(ProcessKind.SKIP)
                continue
            }
            kinds.add(GetParamType(paramTy, paramTys))
        }
        return SetCFuncInfo(chirFuncTy, CreateFunctionType(retTy, paramTys, chirFuncTy.HasVarArg()), kinds)
    }

    public override func ProcessParam(chirParamTy: Type, arg: LLVMFuncArgIt, place: LLVMValueRef,
        builder: IRBuilder2): Unit {
        if (!chirParamTy.IsStruct()) {
            return
        }
        let argInfo = match (FindABIArgInfo(paramTypeMap, chirParamTy)) {
            case Some(found) => found
            case None => return
        }
        if (argInfo.IsDirect()) {
            let argType = arg.GetType()
            let alloca = builder.CreateEntryAlloca(argType)
            builder.CreateStore(arg.GetValue(), alloca)
            builder.CreateMemCpy(place, UInt32(GetTypeAlignment(cgMod, chirParamTy)), alloca,
                UInt32(GetTypeAlignment(cgMod, argType)), SizeValue(builder, GetTypeSize(cgMod, chirParamTy)))
        }
        CJC_ASSERT(!argInfo.IsExpand())
    }

    protected override func ProcessInvocationArg(chirParamTy: StructType, kind: ProcessKind, argIdx: Int64Box,
        args: ArrayList<CGValue>, builder: IRBuilder2): Unit {
        ProcessAarch64DirectArg(chirParamTy, kind, argIdx.value, args, builder, paramTypeMap)
    }

    protected override func GetStructReturnType(chirTy: StructType, params: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (GetTypeSize(cgMod, chirTy) == 0u64) {
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        let argInfo = GetMappingArgInfo(chirTy, false)
        if (argInfo.IsIndirect()) {
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            params.add(unsafe { LLVMPointerType(structType, 0u32) })
            return unsafe { LLVMVoidTypeInContext(ctx.GetLLVMContext().raw) }
        }
        CJC_ASSERT(argInfo.IsDirect())
        return argInfo[0]
    }

    protected override func GetParamType(chirTy: Type, params: ArrayList<LLVMTypeRef>): ProcessKind {
        if (let Some(structTy) <- (chirTy as StructType)) {
            let info = GetMappingArgInfo(structTy, true)
            let structType = GetLLVMType(chirTy)
            CJC_ASSERT(isStructTy(structType))
            if (info.IsIndirect()) {
                params.add(unsafe { LLVMPointerType(structType, 0u32) })
                return ProcessKind.INDIRECT
            }
            CJC_ASSERT(info.IsDirect())
            params.add(info[0])
            return ProcessKind.DIRECT
        }
        var paramType = GetLLVMType(chirTy)
        if (chirTy.IsVArray()) {
            paramType = Int8PtrType(ctx)
        }
        params.add(paramType)
        return ProcessKind.NO_PROCESS
    }

    protected override func GetMappingArgInfo(chirTy: StructType, isArg: Bool): ABIArgInfo {
        let map = if (isArg) { paramTypeMap } else { typeMap }
        if (let Some(found) <- FindABIArgInfo(map, chirTy)) {
            return found
        }
        let llvmType = GetLLVMType(chirTy)
        var size = GetTypeSize(cgMod, llvmType)
        if (isArg) {
            var alignment = GetTypeAlignment(cgMod, llvmType)
            var baseTy = LLVMNullType()
            if (alignment <= 4u64) {
                alignment = 4u64
                baseTy = unsafe { LLVMInt32TypeInContext(ctx.GetLLVMContext().raw) }
            } else if (alignment >= 8u64) {
                alignment = 8u64
                baseTy = unsafe { LLVMInt64TypeInContext(ctx.GetLLVMContext().raw) }
            } else {
                CJC_ASSERT(true)
            }
            size = AlignedUpTo(size, alignment)
            return SetABIArgInfo(paramTypeMap, chirTy, ABIArgInfo.GetDirect(unsafe {
                LLVMArrayType(baseTy, UInt32(size / alignment))
            }))
        }
        if (size > 4u64) {
            return SetABIArgInfo(typeMap, chirTy, ABIArgInfo.GetIndirect())
        }
        return SetABIArgInfo(typeMap, chirTy,
            ABIArgInfo.GetDirect(unsafe { LLVMInt32TypeInContext(ctx.GetLLVMContext().raw) }))
    }
}

public class TypeBox {
    public var value: LLVMTypeRef
    public init(value: LLVMTypeRef) {
        this.value = value
    }
}

public class UInt64Box {
    public var value: UInt64
    public init(value: UInt64) {
        this.value = value
    }
}

public class Int64Box {
    public var value: Int64
    public init(value: Int64) {
        this.value = value
    }
}

private func FindABIArgInfo(map: ArrayList<(Type, ABIArgInfo)>, chirTy: Type): Option<ABIArgInfo> {
    for ((cachedTy, cachedInfo) in map) {
        if (refEq(cachedTy, chirTy)) {
            return cachedInfo
        }
    }
    return None
}

private func SetABIArgInfo(map: ArrayList<(Type, ABIArgInfo)>, chirTy: Type, info: ABIArgInfo): ABIArgInfo {
    var idx: Int64 = 0
    while (idx < map.size) {
        if (refEq(map[idx][0], chirTy)) {
            map[idx] = (chirTy, info)
            return info
        }
        idx++
    }
    map.add((chirTy, info))
    return info
}

private func IsStructPtrTy(llvmType: LLVMTypeRef): Bool {
    return IsStructPtrType(llvmType)
}

private func IsMetCType(chirTy: Type): Bool {
    if (chirTy.IsVArray() || IsVArrayRef(chirTy)) {
        let varrTy = if (chirTy.IsRef()) { chirTy.GetTypeArgs()[0] } else { chirTy }
        let elemType = (varrTy as VArrayType).getOrThrow().GetElementType()
        CJC_ASSERT(!elemType.IsInvalid())
        return IsMetCType(elemType)
    }
    let isPrimitiveCType = match (chirTy.GetTypeKind()) {
        case TypeKind.TYPE_UNIT | TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 |
            TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 |
            TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 | TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE |
            TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 => true
        case _ => false
    }
    return isPrimitiveCType || chirTy.IsCPointer() || chirTy.IsCString() || chirTy.IsCFunc() ||
        (chirTy.IsStruct() && (chirTy as StructType).getOrThrow().GetStructDef().IsCStruct())
}

private func GetCGType(cgMod: CGModule, llvmTy: LLVMTypeRef): CGType {
    let chirContext = cgMod.GetCGContext().GetCHIRBuilder().context
    if (isIntegerTy(llvmTy, 1u32)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetBoolTy())
    }
    if (isIntegerTy(llvmTy, 8u32)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetInt8Ty())
    }
    if (isIntegerTy(llvmTy, 16u32)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetInt16Ty())
    }
    if (isIntegerTy(llvmTy, 32u32)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetInt32Ty())
    }
    if (isIntegerTy(llvmTy, 64u32)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetInt64Ty())
    }
    if (isFloatTy(llvmTy)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetFloat32Ty())
    }
    if (isDoubleTy(llvmTy)) {
        return CGType.GetOrCreate(cgMod, chirContext.GetFloat64Ty())
    }
    return CGType.GetOrCreate(cgMod, chirContext.GetInt8Ty())
}

private func CreateFunctionType(retTy: LLVMTypeRef, paramTys: ArrayList<LLVMTypeRef>, hasVarArg: Bool): LLVMTypeRef {
    if (paramTys.isEmpty()) {
        return unsafe { LLVMFunctionType(retTy, CPointer<LLVMTypeRef>(), 0u32, if (hasVarArg) { 1 } else { 0 }) }
    }
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTys.size).asResource()) {
        var idx: Int64 = 0
        while (idx < paramTys.size) {
            unsafe { (paramPtr.value + idx).write(paramTys[idx]) }
            idx++
        }
        result = unsafe { LLVMFunctionType(retTy, paramPtr.value, UInt32(paramTys.size), if (hasVarArg) { 1 } else { 0 }) }
    }
    return result
}

private func CreateStructType(ctx: CGContext, elementTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
    if (elementTypes.isEmpty()) {
        return unsafe { LLVMStructTypeInContext(ctx.GetLLVMContext().raw, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }
    var result = LLVMNullType()
    try (typePtr = LibC.malloc<LLVMTypeRef>(count: elementTypes.size).asResource()) {
        var idx: Int64 = 0
        while (idx < elementTypes.size) {
            unsafe { (typePtr.value + idx).write(elementTypes[idx]) }
            idx++
        }
        result = unsafe { LLVMStructTypeInContext(ctx.GetLLVMContext().raw, typePtr.value, UInt32(elementTypes.size), 0) }
    }
    return result
}

private func MakeTypeList(ty1: LLVMTypeRef, ty2: LLVMTypeRef): ArrayList<LLVMTypeRef> {
    let out = ArrayList<LLVMTypeRef>()
    out.add(ty1)
    out.add(ty2)
    return out
}

private func SizeValue(builder: IRBuilder2, size: UInt64): LLVMValueRef {
    return unsafe { LLVMConstInt(LLVMInt64TypeInContext(builder.GetLLVMContext().raw), size, 0) }
}

private func Int8PtrType(ctx: CGContext): LLVMTypeRef {
    return unsafe { LLVMPointerType(LLVMInt8TypeInContext(ctx.GetLLVMContext().raw), 0u32) }
}

private func InsertCGValue(args: ArrayList<CGValue>, idx: Int64, value: CGValue): Unit {
    CJC_ASSERT(idx >= 0 && idx <= args.size)
    if (idx == args.size) {
        args.add(value)
        return
    }
    args.add(args[args.size - 1])
    var moveIdx = args.size - 1
    while (moveIdx > idx) {
        args[moveIdx] = args[moveIdx - 1]
        moveIdx--
    }
    args[idx] = value
}

private func FillWithMemory(wordClasses: ArrayList<WordClass>): Unit {
    var idx: Int64 = 0
    while (idx < wordClasses.size) {
        wordClasses[idx] = WordClass.MEMORY
        idx++
    }
}

private func UnifyWordClass(wordClasses: ArrayList<WordClass>, idx: Int64, newClass: WordClass): Unit {
    if (idx < 0 || idx >= wordClasses.size) {
        return
    }
    let oldClass = wordClasses[idx]
    if (oldClass == newClass) {
        return
    } else if (oldClass == WordClass.NO_CLASS) {
        wordClasses[idx] = newClass
    } else if (newClass == WordClass.NO_CLASS) {
        return
    } else if (oldClass == WordClass.MEMORY || newClass == WordClass.MEMORY) {
        wordClasses[idx] = WordClass.MEMORY
    } else if (oldClass == WordClass.INTEGER || newClass == WordClass.INTEGER) {
        wordClasses[idx] = WordClass.INTEGER
    } else if (oldClass == WordClass.X87 || oldClass == WordClass.X87UP || oldClass == WordClass.COMPLEX_X87 ||
        newClass == WordClass.X87 || newClass == WordClass.X87UP || newClass == WordClass.COMPLEX_X87) {
        wordClasses[idx] = WordClass.MEMORY
    } else {
        wordClasses[idx] = newClass
    }
}

private func AsBits(bytes: UInt64): UInt64 {
    return bytes * BITS_PER_BYTE
}

private func MinUInt64(left: UInt64, right: UInt64): UInt64 {
    return if (left < right) { left } else { right }
}

private func isVoidTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_VOID_TYPE_KIND
}

private func isIntegerTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_INTEGER_TYPE_KIND
}

private func isIntegerTy(llvmType: LLVMTypeRef, bits: UInt32): Bool {
    return isIntegerTy(llvmType) && unsafe { LLVMGetIntTypeWidth(llvmType) } == bits
}

private func isPointerTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_POINTER_TYPE_KIND
}

private func isIntOrPtrTy(llvmType: LLVMTypeRef): Bool {
    return isIntegerTy(llvmType) || isPointerTy(llvmType)
}

private func isStructTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_STRUCT_TYPE_KIND
}

private func isArrayTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_ARRAY_TYPE_KIND
}

private func isFloatTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_FLOAT_TYPE_KIND
}

private func isDoubleTy(llvmType: LLVMTypeRef): Bool {
    return !llvmType.isNull() && unsafe { LLVMGetTypeKind(llvmType) } == LLVM_DOUBLE_TYPE_KIND
}

private func isFloatingPointTy(llvmType: LLVMTypeRef): Bool {
    let kind = if (llvmType.isNull()) { -1i32 } else { unsafe { LLVMGetTypeKind(llvmType) } }
    return kind == LLVM_HALF_TYPE_KIND || kind == LLVM_FLOAT_TYPE_KIND || kind == LLVM_DOUBLE_TYPE_KIND ||
        kind == LLVM_X86_FP80_TYPE_KIND || kind == LLVM_FP128_TYPE_KIND || kind == LLVM_PPC_FP128_TYPE_KIND
}

private func getPrimitiveSizeInBits(llvmType: LLVMTypeRef): UInt64 {
    if (isIntegerTy(llvmType)) {
        return UInt64(unsafe { LLVMGetIntTypeWidth(llvmType) })
    }
    let kind = unsafe { LLVMGetTypeKind(llvmType) }
    if (kind == LLVM_HALF_TYPE_KIND) {
        return 16u64
    }
    if (kind == LLVM_FLOAT_TYPE_KIND) {
        return 32u64
    }
    if (kind == LLVM_DOUBLE_TYPE_KIND) {
        return 64u64
    }
    if (kind == LLVM_X86_FP80_TYPE_KIND) {
        return 80u64
    }
    if (kind == LLVM_FP128_TYPE_KIND || kind == LLVM_PPC_FP128_TYPE_KIND) {
        return 128u64
    }
    return unsafe { LLVMSelfhostGetPrimitiveSizeInBits(llvmType) }
}

private func GetStructElements(llvmType: LLVMTypeRef): ArrayList<LLVMTypeRef> {
    let out = ArrayList<LLVMTypeRef>()
    let count = unsafe { LLVMCountStructElementTypes(llvmType) }
    if (count == 0u32) {
        return out
    }
    try (elements = LibC.malloc<LLVMTypeRef>(count: Int64(count)).asResource()) {
        unsafe { LLVMGetStructElementTypes(llvmType, elements.value) }
        var idx: UInt32 = 0u32
        while (idx < count) {
            out.add(unsafe { (elements.value + Int64(idx)).read() })
            idx++
        }
    }
    return out
}

private func GetStructElementType(llvmType: LLVMTypeRef, idx: Int64): LLVMTypeRef {
    let elements = GetStructElements(llvmType)
    CJC_ASSERT(idx >= 0 && idx < elements.size)
    return elements[idx]
}

private func SameLLVMType(left: LLVMTypeRef, right: LLVMTypeRef): Bool {
    if (left.isNull() || right.isNull()) {
        return left.isNull() && right.isNull()
    }
    if (unsafe { LLVMGetTypeKind(left) } != unsafe { LLVMGetTypeKind(right) }) {
        return false
    }
    if (isIntegerTy(left)) {
        return unsafe { LLVMGetIntTypeWidth(left) } == unsafe { LLVMGetIntTypeWidth(right) }
    }
    if (isPointerTy(left)) {
        return unsafe { LLVMGetPointerAddressSpace(left) } == unsafe { LLVMGetPointerAddressSpace(right) } &&
            SameLLVMType(GetPointerElementType(left), GetPointerElementType(right))
    }
    if (isArrayTy(left)) {
        return unsafe { LLVMGetArrayLength(left) } == unsafe { LLVMGetArrayLength(right) } &&
            SameLLVMType(GetPointerElementType(left), GetPointerElementType(right))
    }
    return left.toUIntNative() == right.toUIntNative()
}

private func CreateIntCastUnsigned(builder: IRBuilder2, value: LLVMValueRef, destType: LLVMTypeRef): LLVMValueRef {
    let sourceType = unsafe { LLVMTypeOf(value) }
    if (!isIntegerTy(sourceType) || !isIntegerTy(destType)) {
        return value
    }
    let sourceWidth = unsafe { LLVMGetIntTypeWidth(sourceType) }
    let destWidth = unsafe { LLVMGetIntTypeWidth(destType) }
    if (sourceWidth == destWidth) {
        return value
    }
    if (sourceWidth < destWidth) {
        return builder.CreateZExt(value, destType)
    }
    return builder.CreateTrunc(value, destType)
}

private func AddAlignAttributeAtIndex(value: LLVMValueRef, idx: UInt32, align: UInt64): Unit {
    if (value.isNull()) {
        return
    }
    var alignKind: UInt32 = 0u32
    try (attrCString = unsafe { LibC.mallocCString("align") }.asResource()) {
        alignKind = unsafe { LLVMGetEnumAttributeKindForName(attrCString.value, UIntNative(5)) }
    }
    if (alignKind == 0u32) {
        return
    }
    let attrContext = unsafe { LLVMGetTypeContext(LLVMTypeOf(value)) }
    if (attrContext.isNull()) {
        return
    }
    let attr = unsafe { LLVMCreateEnumAttribute(attrContext, alignKind, align) }
    unsafe { LLVMAddAttributeAtIndex(value, idx, attr) }
}
