package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::option.GlobalOptions

public func GenPackageModules(chirData: CHIRData, options: GlobalOptions, enableIncrement: Bool,
    cachedMangleMap!: CachedMangleMap = CachedMangleMap()): ArrayList<LLVMModuleHandle> {
    let cgPkgContext = CGPkgContext(chirData, options, enableIncrement, cachedMangleMap)
    let splitter = CHIRSplitter(cgPkgContext)
    for (subPackage in splitter.SplitCHIRPackage()) {
        let cgMod = CGModule(subPackage, cgPkgContext)
        cgPkgContext.AddCGModule(cgMod)
        for (globalVar in subPackage.chirGVs) {
            EmitGlobalVariableIR(cgMod, globalVar)
        }
        for (chirFunc in subPackage.chirFuncs) {
            EmitFunctionIR(cgMod, chirFunc)
        }
        cgMod.EraseUselessInstsAndDeclarations()
        cgMod.Opt()
    }
    return cgPkgContext.ReleaseLLVMModules()
}

public func SavePackageModule(module: LLVMModuleHandle, bcFilePath: String): Bool {
    var result: Int32 = 1
    try (pathCString = unsafe { LibC.mallocCString(bcFilePath) }.asResource()) {
        result = unsafe { LLVMWriteBitcodeToFile(module.raw, pathCString.value) }
    }
    return result == 0
}

public func ClearPackageModules(packageModules: ArrayList<LLVMModuleHandle>): Unit {
    for (moduleHandle in packageModules) {
        unsafe { LLVMDisposeModule(moduleHandle.raw) }
    }
    packageModules.clear()
}
