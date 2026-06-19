package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.Value
import cangjie_compiler::option.ArchType
import cangjie_compiler::option.EnvironmentType
import cangjie_compiler::option.TripleInfo

private let CJ_PERSONALITY_FUNC_NAME: String = "__cj_personality_v0$"

public func SetCangjieGC(rawFunction: LLVMValueRef): Unit {
    if (rawFunction.isNull()) {
        return
    }
    try (gcName = unsafe { LibC.mallocCString("cangjie") }.asResource()) {
        unsafe { LLVMSetGC(rawFunction, gcName.value) }
    }
}

public open class CGValue {
    private var rawVal: LLVMValueRef
    private var cgType: Option<CGType>
    private var sRetArg: Bool

    public init() {
        rawVal = LLVMNullValue()
        cgType = None
        sRetArg = false
    }

    public init(rawVal: LLVMValueRef, cgType: CGType, isSRetArg!: Bool = false) {
        this.rawVal = rawVal
        this.cgType = cgType
        sRetArg = isSRetArg
    }

    public func GetRawValue(): LLVMValueRef { return rawVal }
    public func GetCGType(): Option<CGType> { return cgType }
    public func GetLLVMType(): LLVMTypeRef {
        if (let Some(valueType) <- cgType) {
            return valueType.GetLLVMType()
        }
        return LLVMNullType()
    }
    public func IsSRetArg(): Bool { return sRetArg }
}

public class CGModule {
    private let cgCtx: CGContext
    private var module: Option<LLVMModuleHandle>
    private let functions: HashMap<String, CGFunction> = HashMap<String, CGFunction>()
    private let valueMapping: HashMap<String, CGValue> = HashMap<String, CGValue>()
    private let globalVariables: HashMap<String, CGValue> = HashMap<String, CGValue>()
    private let basicBlocks: HashMap<Int64, LLVMBasicBlockRef> = HashMap<Int64, LLVMBasicBlockRef>()
    private let linkNameUsedInMeta: HashSet<String> = HashSet<String>()
    private let externalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let nonExternalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let extensionDefStartIndices: HashMap<String, Int64> = HashMap<String, Int64>()
    private var diBuilder: Option<DIBuilder> = None

    public init(subCHIRPackage: SubCHIRPackage, cgPkgCtx: CGPkgContext) {
        cgCtx = CGContext(subCHIRPackage, cgPkgCtx)
        let moduleName = "${subCHIRPackage.subCHIRPackageIdx}-" + cgPkgCtx.GetCurrentPkgName()
        let moduleHandle = LLVMModuleHandle.Create(moduleName, cgCtx.GetLLVMContext())
        module = moduleHandle
        InitModuleFlags(moduleHandle)
        moduleHandle.SetDataLayout(CGModule.GetDataLayoutString(cgCtx.GetCompileOptions().target))
        moduleHandle.SetTargetTriple(CGModule.GetTargetTripleString(cgCtx.GetCompileOptions().target))
        InitDebugInfo()
    }

    public func GetCGContext(): CGContext { return cgCtx }
    public func GetLLVMContext(): LLVMContextHandle { return cgCtx.GetLLVMContext() }

    public func GetLLVMModule(): Option<LLVMModuleHandle> {
        return module
    }

    public func ReleaseLLVMModule(): Option<LLVMModuleHandle> {
        FinalizeDebugInfo()
        let released = module
        module = None
        if (let Some(moduleHandle) <- released) {
            moduleHandle.EnableContextDisposalOnClose()
        }
        return released
    }

    public func ResetLLVMModule(newModule: LLVMModuleHandle): Unit {
        if (let Some(oldModule) <- module) {
            oldModule.close()
        }
        module = newModule
    }

    public func Clear(): Unit {
        FinalizeDebugInfo()
        if (let Some(moduleHandle) <- module) {
            moduleHandle.close()
            module = None
        }
        functions.clear()
        valueMapping.clear()
        globalVariables.clear()
        basicBlocks.clear()
        linkNameUsedInMeta.clear()
        externalExtensionDefs.clear()
        nonExternalExtensionDefs.clear()
        extensionDefStartIndices.clear()
        cgCtx.Clear()
        cgCtx.GetLLVMContext().close()
    }

    public func GetOrInsertCGFunction(chirValue: Value, forWrapper!: Bool = false): CGFunction {
        let name = GetCodeGenGlobalName(chirValue)
        if (functions.contains(name)) {
            return functions[name]
        }
        let cgFuncType = CGType.GetOrCreateWithNode(this, chirValue, allowBasePtr: true, forWrapper: forWrapper)
        let functionType = if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
            functionCGType.GetLLVMFunctionType()
        } else {
            cgFuncType.GetLLVMType()
        }
        let rawFunction = if (let Some(moduleHandle) <- module) {
            var createdFunction = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                createdFunction = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (createdFunction.isNull()) {
                    createdFunction = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            createdFunction
        } else {
            LLVMNullValue()
        }
        let cgFunc = CGFunction(rawFunction, cgFuncType, chirValue, this)
        ApplyFunctionABIAttributes(rawFunction, chirValue, cgFuncType)
        MaybeAttachExceptionPersonality(rawFunction, chirValue)
        MaybeSetCangjieGC(rawFunction, chirValue)
        functions[name] = cgFunc
        valueMapping[name] = cgFunc
        return cgFunc
    }

    public func GetOrInsertFunction(funcName: String, functionType: LLVMTypeRef): LLVMValueRef {
        if (let Some(moduleHandle) <- module) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(funcName) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func GetExceptionIntrinsicPersonality(): LLVMValueRef {
        let returnType = unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }
        let functionType = unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 1) }
        if (cgCtx.GetCompileOptions().target.IsMacOS()) {
            return GetOrInsertFunction(CJ_PERSONALITY_FUNC_NAME, functionType)
        }
        if (let Some(moduleHandle) <- module) {
            var result = LLVMNullValue()
            var created = false
            try (nameCString = unsafe { LibC.mallocCString(CJ_PERSONALITY_FUNC_NAME) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                    created = true
                }
            }
            if (created && !result.isNull()) {
                AddLinkageTypeMetadata(result, LLVMLinkage.Private, false)
                try (entryBuilder = IRBuilder2(this)) {
                    let entryBlock = entryBuilder.CreateEntryBasicBlock(result, "entry")
                    try (personalityBuilder = IRBuilder2(this, entryBlock)) {
                        _ = personalityBuilder.CreateRet(unsafe { LLVMConstInt(returnType, 0u64, 0) })
                    }
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func SetExceptionIntrinsicPersonality(rawFunction: LLVMValueRef): Unit {
        if (rawFunction.isNull()) {
            return
        }
        let personality = GetExceptionIntrinsicPersonality()
        if (!personality.isNull()) {
            unsafe { LLVMSetPersonalityFn(rawFunction, personality) }
        }
    }

    public func HasPersonalityFunction(rawFunction: LLVMValueRef): Bool {
        return !rawFunction.isNull() && unsafe { LLVMHasPersonalityFn(rawFunction) } != 0
    }

    public func GetPersonalityFunction(rawFunction: LLVMValueRef): LLVMValueRef {
        if (rawFunction.isNull() || !HasPersonalityFunction(rawFunction)) {
            return LLVMNullValue()
        }
        return unsafe { LLVMGetPersonalityFn(rawFunction) }
    }

    private func MaybeAttachExceptionPersonality(rawFunction: LLVMValueRef, chirValue: Value): Unit {
        if (rawFunction.isNull() || !chirValue.IsFuncWithBody() || chirValue.TestAttr(Attribute.FOREIGN) ||
            chirValue.TestAttr(Attribute.IMPORTED)) {
            return
        }
        if (let Some(functionValue) <- (chirValue as Function)) {
            if (functionValue.IsCFFIWrapper()) {
                return
            }
        }
        SetExceptionIntrinsicPersonality(rawFunction)
    }

    private func MaybeSetCangjieGC(rawFunction: LLVMValueRef, chirValue: Value): Unit {
        if (rawFunction.isNull()) {
            return
        }
        if (let Some(chirTy) <- chirValue.GetType()) {
            if (let Some(funcTy) <- (chirTy as FuncType)) {
                if (!funcTy.IsCFunc()) {
                    SetCangjieGC(rawFunction)
                }
            }
        }
    }

    private func ApplyFunctionABIAttributes(rawFunction: LLVMValueRef, chirValue: Value, cgFuncType: CGType): Unit {
        if (rawFunction.isNull()) {
            return
        }
        if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
            if (functionCGType.HasBasePtr()) {
                AddFnStringAttr(rawFunction, STRUCT_MUT_FUNC_ATTR)
                AddFnStringAttr(rawFunction, THIS_PARAM_HAS_BP)
            }
            if (let Some(chirType) <- chirValue.GetType()) {
                if (let Some(funcType) <- (chirType as FuncType)) {
                    if (funcType.IsCFunc()) {
                        SetZExtAttrForCFunc(rawFunction, functionCGType.GetLLVMFunctionType())
                    }
                }
            }
            if (!functionCGType.HasSRet()) {
                return
            }
            if (let Some(chirType) <- chirValue.GetType()) {
                if (let Some(funcType) <- (chirType as FuncType)) {
                    let retCGType = CGType.GetOrCreate(this, funcType.GetReturnType())
                    AddSRetAttribute(rawFunction, retCGType.GetLLVMType())
                    AddNoAliasAttribute(rawFunction)
                    return
                }
            }
            AddSRetAttribute(rawFunction)
            AddNoAliasAttribute(rawFunction)
        }
    }

    public func GetOrInsertGlobalVariable(chirGV: GlobalVar): CGValue {
        let name = GetCodeGenGlobalName(chirGV)
        if (globalVariables.contains(name)) {
            return globalVariables[name]
        }
        let chirType = if (let Some(valueType) <- chirGV.GetType()) {
            valueType
        } else {
            throw IllegalArgumentException("global variable has no CHIR type: " + name)
        }
        let cgType = CGType.GetOrCreate(this, chirType)
        let globalType = if (let Some(elementType) <- cgType.GetPointerElementType()) {
            elementType.GetLLVMType()
        } else {
            cgType.GetLLVMType()
        }
        let rawGlobal = if (let Some(moduleHandle) <- module) {
            var createdGlobal = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                createdGlobal = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (createdGlobal.isNull()) {
                    createdGlobal = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
                }
            }
            createdGlobal
        } else {
            LLVMNullValue()
        }
        let cgValue = CGValue(rawGlobal, cgType)
        globalVariables[name] = cgValue
        valueMapping[name] = cgValue
        return cgValue
    }

    public func GetMappedValue(chirValue: Value): Option<CGValue> {
        let name = GetCodeGenValueKey(chirValue)
        if (valueMapping.contains(name)) {
            return valueMapping[name]
        }
        return None
    }

    public func SetOrUpdateMappedCGValue(chirValue: Value, value: CGValue): Unit {
        valueMapping[GetCodeGenValueKey(chirValue)] = value
    }

    public func MaterializeValue(irBuilder: IRBuilder2, chirValue: Value): CGValue {
        if (let Some(mappedValue) <- GetMappedValue(chirValue)) {
            return mappedValue
        }
        if (let Some(functionValue) <- (chirValue as Function)) {
            return GetOrInsertCGFunction(functionValue)
        }
        if (let Some(globalValue) <- (chirValue as GlobalVar)) {
            return GetOrInsertGlobalVariable(globalValue)
        }
        if (let Some(localValue) <- (chirValue as LocalVar)) {
            if (let Some(ownerExpr) <- localValue.GetExpr()) {
                let emitted = DispatchExpression(irBuilder, ownerExpr)
                let cgValue = CGValue(emitted, GetCGTypeForValue(localValue))
                SetOrUpdateMappedCGValue(localValue, cgValue)
                return cgValue
            }
        }
        let fallback = CGValue(LLVMNullValue(), GetCGTypeForValue(chirValue))
        SetOrUpdateMappedCGValue(chirValue, fallback)
        return fallback
    }

    public func SetOrUpdateMappedBB(chirBlock: Block, llvmBlock: LLVMBasicBlockRef): Unit {
        basicBlocks[chirBlock.nodeId] = llvmBlock
    }

    public func GetMappedBB(chirBlock: Block): Option<LLVMBasicBlockRef> {
        if (basicBlocks.contains(chirBlock.nodeId)) {
            return basicBlocks[chirBlock.nodeId]
        }
        return None
    }

    public func CreateOrGetMappedBB(irBuilder: IRBuilder2, functionValue: LLVMValueRef, chirBlock: Block): LLVMBasicBlockRef {
        if (let Some(mappedBlock) <- GetMappedBB(chirBlock)) {
            return mappedBlock
        }
        let blockName = PREFIX_FOR_BB_NAME + chirBlock.GetIdentifierWithoutPrefix()
        let createdBlock = irBuilder.CreateBasicBlockAtEnd(functionValue, blockName)
        SetOrUpdateMappedBB(chirBlock, createdBlock)
        return createdBlock
    }

    public func MapFunctionParameters(chirFunc: Function, cgFunc: CGFunction): Unit {
        var idx: Int64 = 0
        while (idx < chirFunc.GetNumOfParams()) {
            let param = chirFunc.GetParam(idx)
            let rawArg = cgFunc.GetArgByIndexFromCHIR(idx)
            let paramCGType = if (let Some(paramTy) <- param.GetType()) {
                if (!paramTy.IsRef() && (paramTy.IsStruct() || paramTy.IsTuple())) {
                    CGType.GetOrCreate(this, cgCtx.GetCGPkgContext().GetCHIRBuilder().context.GetRefTy(paramTy))
                } else {
                    GetCGTypeForValue(param)
                }
            } else {
                GetCGTypeForValue(param)
            }
            SetOrUpdateMappedCGValue(param, CGValue(rawArg, paramCGType))
            idx++
        }
    }

    public func EraseUselessInstsAndDeclarations(): Unit {
        EraseUselessInstsAndDeclarationsImpl(this)
    }

    public func EraseUselessGVAndFunctions(): Unit {
        EraseUselessGVAndFunctionsImpl(this)
    }

    public func Opt(): Unit {
        for ((_, cgFunction) in functions) {
            cgFunction.Opt()
        }
    }

    public func Verify(): Bool {
        if (let Some(moduleHandle) <- module) {
            let verifyResult = VerifyModule(moduleHandle)
            if (!verifyResult.message.isEmpty()) {
                eprintln(verifyResult.message)
            }
            return verifyResult.ok
        }
        return false
    }

    private func InitModuleFlags(moduleHandle: LLVMModuleHandle): Unit {
        AddUInt32ModuleFlag(moduleHandle.raw, "CJBC", 1u64)
        AddUInt32ModuleFlag(moduleHandle.raw, "Cangjie_OPT", 0u64)
        if (cgCtx.GetCompileOptions().target.IsMacOS()) {
            AddStringModuleFlag(moduleHandle.raw, "Cangjie_PACKAGE_ID",
                CGModule.NormalizePackageIdentifier(cgCtx.GetCurrentPkgName()))
        }
    }

    public func InitDebugInfo(): Unit {
        if (let Some(moduleHandle) <- module) {
            AddUInt32ModuleFlag(moduleHandle.raw, "Debug Info Version",
                UInt64(unsafe { LLVMDebugMetadataVersion() }))
            AddUInt32ModuleFlag(moduleHandle.raw, "Dwarf Version", DWARF_VERSION)
            let builder = DIBuilder(this)
            builder.CreateCompileUnit(moduleHandle.name)
            builder.CreateNameSpace(cgCtx.GetCurrentPkgName())
            diBuilder = builder
        }
    }

    public func GetDIBuilder(): Option<DIBuilder> { return diBuilder }

    public func FinalizeDebugInfo(): Unit {
        if (let Some(builder) <- diBuilder) {
            builder.Finalize()
            diBuilder = None
        }
    }

    private func AddStringModuleFlag(moduleRef: LLVMModuleRef, key: String, value: String): Unit {
        try (keyCString = unsafe { LibC.mallocCString(key) }.asResource(),
            valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
            let metadata = unsafe {
                LLVMMDStringInContext2(GetLLVMContext().raw, valueCString.value, UIntNative(value.size))
            }
            unsafe {
                LLVMAddModuleFlag(moduleRef, LLVM_MODULE_FLAG_WARNING, keyCString.value,
                    UIntNative(key.size), metadata)
            }
        }
    }

    private func AddUInt32ModuleFlag(moduleRef: LLVMModuleRef, key: String, value: UInt64): Unit {
        let metadata = CreateUInt32Metadata(GetLLVMContext(), value)
        try (keyCString = unsafe { LibC.mallocCString(key) }.asResource()) {
            unsafe {
                LLVMAddModuleFlag(moduleRef, LLVM_MODULE_FLAG_WARNING, keyCString.value,
                    UIntNative(key.size), metadata)
            }
        }
    }

    public func GenerateUnitTypeValue(): LLVMValueRef {
        let unitType = CGType.GetUnitType(GetLLVMContext())
        if (let Some(moduleHandle) <- module) {
            var unitValue = LLVMNullValue()
            try (unitName = unsafe { LibC.mallocCString(UNIT_VAL_STR) }.asResource()) {
                unitValue = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, unitName.value) }
                if (unitValue.isNull()) {
                    unitValue = unsafe { LLVMAddGlobal(moduleHandle.raw, unitType, unitName.value) }
                    unsafe { LLVMSetInitializer(unitValue, LLVMGetUndef(unitType)) }
                    let linkage = if (cgCtx.GetCompileOptions().target.IsMinGW()) {
                        LLVMLinkage.Private
                    } else {
                        LLVMLinkage.WeakODR
                    }
                    AddLinkageTypeMetadata(unitValue, linkage, false)
                }
            }
            return unitValue
        }
        return unsafe { LLVMConstNull(unitType) }
    }

    public func GetModuleTargetData(): LLVMTargetDataHandle {
        if (let Some(moduleHandle) <- module) {
            return LLVMTargetDataHandle.FromModule(moduleHandle)
        }
        return LLVMTargetDataHandle(LLVMNullTargetData(), owned: false)
    }

    public func CopyDataLayoutString(): String {
        return GetModuleTargetData().CopyStringRep()
    }

    public func GetPointerSize(addressSpace!: UInt32 = 0u32): UInt32 {
        return GetModuleTargetData().GetPointerSize(addressSpace: addressSpace)
    }

    public func GetIntPtrType(addressSpace!: UInt32 = 0u32): LLVMTypeRef {
        return GetModuleTargetData().GetIntPtrType(GetLLVMContext(), addressSpace: addressSpace)
    }

    public func GetTypeSize(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeAllocSize(codeGenType)
    }

    public func GetTypeSizeInBits(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeSizeInBits(codeGenType)
    }

    public func GetTypeStoreSize(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeStoreSize(codeGenType)
    }

    public func GetABITypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetABITypeAlignment(codeGenType)
    }

    public func GetCallFrameTypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetCallFrameTypeAlignment(codeGenType)
    }

    public func GetPrefTypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetPrefTypeAlignment(codeGenType)
    }

    public func GetPreferredAlignmentOfGlobal(globalVar: LLVMValueRef): UInt32 {
        return GetModuleTargetData().GetPreferredAlignmentOfGlobal(globalVar)
    }

    public func GetElementContainingOffset(structTy: LLVMTypeRef, offset: UInt64): UInt32 {
        return GetModuleTargetData().GetElementContainingOffset(structTy, offset)
    }

    public func GetOffsetOfElement(structTy: LLVMTypeRef, element: UInt32): UInt64 {
        return GetModuleTargetData().GetOffsetOfElement(structTy, element)
    }

    public func ClearLinkNameUsedInMeta(): Unit { linkNameUsedInMeta.clear() }
    public func IsLinkNameUsedInMeta(linkageName: String): Bool { return linkNameUsedInMeta.contains(linkageName) }
    public func GetLinkNamesUsedInMeta(): HashSet<String> { return linkNameUsedInMeta }
    public func AddNonExternalExtensionDef(extensionDef: LLVMValueRef): Unit { nonExternalExtensionDefs.add(extensionDef) }
    public func AddExternalExtensionDef(extensionDef: LLVMValueRef): Unit { externalExtensionDefs.add(extensionDef) }
    public func GetNonExternalExtensionDefs(): ArrayList<LLVMValueRef> { return nonExternalExtensionDefs }
    public func GetExternalExtensionDefs(): ArrayList<LLVMValueRef> { return externalExtensionDefs }
    public func GetNonExternalExtensionDefsNum(): Int64 { return nonExternalExtensionDefs.size }

    public func RegisterExtensionDefStart(chirTy: Type, startIdx: Int64): Unit {
        extensionDefStartIndices[CGType.GetRuntimeTypeName(chirTy.StripAllRefs())] = startIdx
    }

    public func GetExtensionDefStart(chirTy: Type): Option<Int64> {
        return extensionDefStartIndices.get(CGType.GetRuntimeTypeName(chirTy.StripAllRefs()))
    }

    public static func GetDataLayoutString(target: TripleInfo): String {
        if (target.IsMacOS() && target.arch == ArchType.AARCH64) {
            return "e-m:o-i64:64-i128:128-n32:64-S128"
        }
        if (target.arch == ArchType.ARM32) {
            return "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        }
        if (target.IsMinGW()) {
            return "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
        }
        return "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    }

    public static func GetTargetTripleString(target: TripleInfo): String {
        if (target.IsMacOS()) {
            if (target.arch == ArchType.AARCH64) {
                return "arm64-apple-macosx12.0.0"
            }
            return target.ArchToString() + "-apple-macosx12.0.0"
        }
        if (target.arch == ArchType.AARCH64 && target.env == EnvironmentType.OHOS) {
            return target.ArchToString() + "-unknown-linux-ohos"
        }
        if (target.arch == ArchType.ARM32) {
            return "armv7a-linux-gnu"
        }
        let defaultTriple = LLVMGetDefaultTargetTripleString()
        if (!defaultTriple.isEmpty()) {
            return defaultTriple
        }
        return target.GetEffectiveTripleString()
    }

    private static func NormalizePackageIdentifier(pkgName: String): String {
        let out = ArrayList<UInt8>()
        for (byte in pkgName.toArray()) {
            if (byte == b'/') {
                out.add(b'.')
            } else {
                out.add(byte)
            }
        }
        return String.fromUtf8(out.toArray())
    }

    private func GetCGTypeForValue(chirValue: Value): CGType {
        if (let Some(valueType) <- chirValue.GetType()) {
            return CGType.GetOrCreate(this, valueType)
        }
        return CGType(this, cgCtx, Type(TypeKind.TYPE_INVALID))
    }
}
