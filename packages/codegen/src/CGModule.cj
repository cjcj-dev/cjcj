package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::option.ArchType
import cangjie_compiler::option.EnvironmentType
import cangjie_compiler::option.TripleInfo

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
    private let linkNameUsedInMeta: HashSet<String> = HashSet<String>()
    private let externalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let nonExternalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()

    public init(subCHIRPackage: SubCHIRPackage, cgPkgCtx: CGPkgContext) {
        cgCtx = CGContext(subCHIRPackage, cgPkgCtx)
        let moduleName = "${subCHIRPackage.subCHIRPackageIdx}-" + cgPkgCtx.GetCurrentPkgName()
        let moduleHandle = LLVMModuleHandle.Create(moduleName, cgCtx.GetLLVMContext())
        moduleHandle.SetDataLayout(CGModule.GetDataLayoutString(cgCtx.GetCompileOptions().target))
        moduleHandle.SetTargetTriple(CGModule.GetTargetTripleString(cgCtx.GetCompileOptions().target))
        module = moduleHandle
    }

    public func GetCGContext(): CGContext { return cgCtx }
    public func GetLLVMContext(): LLVMContextHandle { return cgCtx.GetLLVMContext() }

    public func GetLLVMModule(): Option<LLVMModuleHandle> {
        return module
    }

    public func ReleaseLLVMModule(): Option<LLVMModuleHandle> {
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

    public func EraseUselessInstsAndDeclarations(): Unit {
        // TODO(selfhost:CodeGen): port EraseUselessIRs.cpp once generated LLVM ownership and use-lists are available.
    }

    public func EraseUselessGVAndFunctions(): Unit {
        // TODO(selfhost:CodeGen): port CGModule dead global/function pruning against real LLVM module iteration.
    }

    public func Opt(): Unit {
        // TODO(selfhost:CodeGen): port CGFunction/CGModule optimization passes and native LICM pipeline.
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
        // TODO(selfhost:CodeGen): port DIBuilder.cpp and CJNativeDIBuilder.cpp debug metadata emission.
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
}
