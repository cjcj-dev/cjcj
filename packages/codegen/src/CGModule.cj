package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.Value
import cangjie_compiler::option.ArchType
import cangjie_compiler::option.EnvironmentType
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::option.TripleInfo
import cangjie_compiler::option.enumIndex

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
    private var diBuilder: Option<DIBuilder> = None

    public init(subCHIRPackage: SubCHIRPackage, cgPkgCtx: CGPkgContext) {
        cgCtx = CGContext(subCHIRPackage, cgPkgCtx)
        let moduleName = "${subCHIRPackage.subCHIRPackageIdx}-" + cgPkgCtx.GetCurrentPkgName()
        let moduleHandle = LLVMModuleHandle.Create(moduleName, cgCtx.GetLLVMContext())
        moduleHandle.SetDataLayout(CGModule.GetDataLayoutString(cgCtx.GetCompileOptions().target))
        moduleHandle.SetTargetTriple(CGModule.GetTargetTripleString(cgCtx.GetCompileOptions().target))
        module = moduleHandle
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
        return released
    }

    public func ResetLLVMModule(newModule: LLVMModuleHandle): Unit {
        module = newModule
    }

    public func GetOrInsertCGFunction(chirValue: Value, forWrapper!: Bool = false): CGFunction {
        let name = chirValue.GetIdentifierWithoutPrefix()
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
                createdFunction = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
            }
            createdFunction
        } else {
            LLVMNullValue()
        }
        let cgFunc = CGFunction(rawFunction, cgFuncType, chirValue, this)
        functions[name] = cgFunc
        valueMapping[name] = cgFunc
        return cgFunc
    }

    public func GetOrInsertGlobalVariable(chirGV: GlobalVar): CGValue {
        let name = chirGV.GetIdentifierWithoutPrefix()
        if (globalVariables.contains(name)) {
            return globalVariables[name]
        }
        let chirType = if (let Some(valueType) <- chirGV.GetType()) {
            valueType
        } else {
            throw IllegalArgumentException("global variable has no CHIR type: " + name)
        }
        let cgType = CGType.GetOrCreate(this, chirType)
        let rawGlobal = if (let Some(moduleHandle) <- module) {
            var createdGlobal = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                createdGlobal = unsafe { LLVMAddGlobal(moduleHandle.raw, cgType.GetLLVMType(), nameCString.value) }
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
        let name = chirValue.GetIdentifierWithoutPrefix()
        if (valueMapping.contains(name)) {
            return valueMapping[name]
        }
        return None
    }

    public func SetOrUpdateMappedCGValue(chirValue: Value, value: CGValue): Unit {
        valueMapping[chirValue.GetIdentifierWithoutPrefix()] = value
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
        let createdBlock = irBuilder.CreateEntryBasicBlock(functionValue, blockName)
        SetOrUpdateMappedBB(chirBlock, createdBlock)
        return createdBlock
    }

    public func MapFunctionParameters(chirFunc: Function, cgFunc: CGFunction): Unit {
        var idx: Int64 = 0
        while (idx < chirFunc.GetNumOfParams()) {
            let param = chirFunc.GetParam(idx)
            let rawArg = cgFunc.GetArgByIndexFromCHIR(idx)
            SetOrUpdateMappedCGValue(param, CGValue(rawArg, GetCGTypeForValue(param)))
            idx++
        }
    }

    public func EraseUselessInstsAndDeclarations(): Unit {
        ClearLinkNameUsedInMeta()
        for ((functionName, cgFunction) in functions) {
            if (functionName != FOR_KEEPING_SOME_TYPES_FUNC_NAME) {
                cgFunction.Opt()
                CGFunction.EraseUselessLoadAndAlloca(cgFunction.GetRawFunction())
            }
        }
        let irBuilder = IRBuilder2(this)
        irBuilder.ClearInsertionPoint()
        if (let Some(moduleHandle) <- module) {
            EraseUnusedGVsAndFunctions(moduleHandle.raw, declarationsOnly: true)
        }
    }

    public func EraseUselessGVAndFunctions(): Unit {
        let options = cgCtx.GetCompileOptions()
        if (enumIndex(options.optimizationLevel) < enumIndex(OptimizationLevel.O2) || options.enableCoverage) {
            return
        }
        if (let Some(moduleHandle) <- module) {
            ClearLinkNameUsedInMeta()
            EraseUnusedGVsAndFunctions(moduleHandle.raw, declarationsOnly: false)
        }
    }

    public func Opt(): Unit {
        for ((_, cgFunction) in functions) {
            cgFunction.Opt()
        }
    }

    public func Verify(): Bool {
        if (let Some(moduleHandle) <- module) {
            let outMessage = CPointer<CString>()
            let status = unsafe {
                LLVMVerifyModule(moduleHandle.raw, LLVMVerifierFailureActionValue(LLVMVerifierFailureAction.ReturnStatus), outMessage)
            }
            return status == 0
        }
        return false
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

    private func AddUInt32ModuleFlag(moduleRef: LLVMModuleRef, key: String, value: UInt64): Unit {
        let metadata = CreateUInt32Metadata(GetLLVMContext(), value)
        try (keyCString = unsafe { LibC.mallocCString(key) }.asResource()) {
            unsafe {
                LLVMAddModuleFlag(moduleRef, LLVM_MODULE_FLAG_WARNING, keyCString.value,
                    UIntNative(key.size), metadata)
            }
        }
    }

    private func EraseUnusedGVsAndFunctions(moduleRef: LLVMModuleRef, declarationsOnly!: Bool): Unit {
        var erased = true
        while (erased) {
            erased = false
            let globals = CollectGlobals(moduleRef)
            for (global in globals) {
                if (CanEraseGlobal(global, declarationsOnly: declarationsOnly)) {
                    unsafe { LLVMDeleteGlobal(global) }
                    erased = true
                }
            }
            let functionValues = CollectFunctions(moduleRef)
            for (functionValue in functionValues) {
                if (CanEraseFunction(functionValue, declarationsOnly: declarationsOnly)) {
                    unsafe { LLVMDeleteFunction(functionValue) }
                    erased = true
                }
            }
        }
    }

    private func CollectGlobals(moduleRef: LLVMModuleRef): ArrayList<LLVMValueRef> {
        let globals = ArrayList<LLVMValueRef>()
        var global = unsafe { LLVMGetFirstGlobal(moduleRef) }
        while (!global.isNull()) {
            globals.add(global)
            global = unsafe { LLVMGetNextGlobal(global) }
        }
        return globals
    }

    private func CollectFunctions(moduleRef: LLVMModuleRef): ArrayList<LLVMValueRef> {
        let functionValues = ArrayList<LLVMValueRef>()
        var functionValue = unsafe { LLVMGetFirstFunction(moduleRef) }
        while (!functionValue.isNull()) {
            functionValues.add(functionValue)
            functionValue = unsafe { LLVMGetNextFunction(functionValue) }
        }
        return functionValues
    }

    private func CanEraseGlobal(global: LLVMValueRef, declarationsOnly!: Bool): Bool {
        if (!CGFunction.HasNoUse(global) || IsRetainedGlobalValue(global, checkCompileUnit: true)) {
            return false
        }
        if (declarationsOnly) {
            return unsafe { LLVMIsDeclaration(global) } != 0
        }
        return unsafe { LLVMIsDeclaration(global) } != 0 || IsLocalLinkage(global)
    }

    private func CanEraseFunction(functionValue: LLVMValueRef, declarationsOnly!: Bool): Bool {
        if (!CGFunction.HasNoUse(functionValue) || IsRetainedGlobalValue(functionValue, checkCompileUnit: false)) {
            return false
        }
        if (declarationsOnly) {
            return unsafe { LLVMIsDeclaration(functionValue) } != 0
        }
        return unsafe { LLVMIsDeclaration(functionValue) } != 0 || IsLocalLinkage(functionValue)
    }

    private func IsRetainedGlobalValue(global: LLVMValueRef, checkCompileUnit!: Bool): Bool {
        let name = unsafe { LLVMGetValueName(global) }
        if (name.isNull()) {
            return false
        }
        if (checkCompileUnit && cgCtx.IsGlobalsOfCompileUnitCString(name)) {
            return true
        }
        if (CGContext.ContainsCString(linkNameUsedInMeta, name)) {
            return true
        }
        return CGContext.ContainsCString(cgCtx.GetLLVMUsedVars(), name)
    }

    private func IsLocalLinkage(global: LLVMValueRef): Bool {
        let linkage = unsafe { LLVMGetLinkage(global) }
        return linkage == LLVMLinkageValue(LLVMLinkage.Internal) ||
            linkage == LLVMLinkageValue(LLVMLinkage.Private)
    }

    public func GenerateUnitTypeValue(): LLVMValueRef {
        return unsafe { LLVMConstNull(CGType.GetUnitType(GetLLVMContext())) }
    }

    public func ClearLinkNameUsedInMeta(): Unit { linkNameUsedInMeta.clear() }
    public func IsLinkNameUsedInMeta(linkageName: String): Bool { return linkNameUsedInMeta.contains(linkageName) }
    public func AddNonExternalExtensionDef(extensionDef: LLVMValueRef): Unit { nonExternalExtensionDefs.add(extensionDef) }
    public func AddExternalExtensionDef(extensionDef: LLVMValueRef): Unit { externalExtensionDefs.add(extensionDef) }
    public func GetNonExternalExtensionDefs(): ArrayList<LLVMValueRef> { return nonExternalExtensionDefs }
    public func GetExternalExtensionDefs(): ArrayList<LLVMValueRef> { return externalExtensionDefs }

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
        return target.GetEffectiveTripleString()
    }

    private func GetCGTypeForValue(chirValue: Value): CGType {
        if (let Some(valueType) <- chirValue.GetType()) {
            return CGType.GetOrCreate(this, valueType)
        }
        return CGType(this, cgCtx, Type(TypeKind.TYPE_INVALID))
    }
}
