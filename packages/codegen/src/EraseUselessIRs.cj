package cjcj::codegen

import std.collection.*
import cjcj::option.OptimizationLevel
import cjcj::option.enumIndex

public func EraseUselessInstsAndDeclarationsImpl(cgMod: CGModule): Unit {
    cgMod.ClearLinkNameUsedInMeta()
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let functionValues = CollectIRFunctions(moduleHandle.raw)
        for (functionValue in functionValues) {
            if (!IsFunctionDeclaration(functionValue) && !HasLLVMName(functionValue, FOR_KEEPING_SOME_TYPES_FUNC_NAME)) {
                CGFunction.RemoveUnreachableBlocks(functionValue)
                CGFunction.EraseUselessLoadAndAlloca(functionValue)
            }
        }
        EraseUnusedGVsAndFunctions(cgMod, moduleHandle.raw, declarationsOnly: true)
    }

    let irBuilder = IRBuilder2(cgMod)
    irBuilder.ClearInsertionPoint()
}

public func EraseUselessGVAndFunctionsImpl(cgMod: CGModule): Unit {
    let options = cgMod.GetCGContext().GetCompileOptions()
    if (enumIndex(options.optimizationLevel) < enumIndex(OptimizationLevel.O2) || options.enableCoverage) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        cgMod.ClearLinkNameUsedInMeta()
        EraseUnusedGVsAndFunctions(cgMod, moduleHandle.raw, declarationsOnly: false)
    }
}

private func EraseUnusedGVsAndFunctions(cgMod: CGModule, moduleRef: LLVMModuleRef, declarationsOnly!: Bool): Unit {
    var erased = true
    while (erased) {
        erased = false
        let globals = CollectIRGlobals(moduleRef)
        for (globalValue in globals) {
            if (CanEraseGlobal(cgMod, globalValue, declarationsOnly: declarationsOnly)) {
                unsafe { LLVMDeleteGlobal(globalValue) }
                erased = true
            }
        }
        let functionValues = CollectIRFunctions(moduleRef)
        for (functionValue in functionValues) {
            if (CanEraseFunction(cgMod, functionValue, declarationsOnly: declarationsOnly)) {
                unsafe { LLVMDeleteFunction(functionValue) }
                erased = true
            }
        }
    }
}

private func CollectIRGlobals(moduleRef: LLVMModuleRef): ArrayList<LLVMValueRef> {
    let globals = ArrayList<LLVMValueRef>()
    var globalValue = unsafe { LLVMGetFirstGlobal(moduleRef) }
    while (!globalValue.isNull()) {
        globals.add(globalValue)
        globalValue = unsafe { LLVMGetNextGlobal(globalValue) }
    }
    return globals
}

private func CollectIRFunctions(moduleRef: LLVMModuleRef): ArrayList<LLVMValueRef> {
    let functionValues = ArrayList<LLVMValueRef>()
    var functionValue = unsafe { LLVMGetFirstFunction(moduleRef) }
    while (!functionValue.isNull()) {
        functionValues.add(functionValue)
        functionValue = unsafe { LLVMGetNextFunction(functionValue) }
    }
    return functionValues
}

private func CanEraseGlobal(cgMod: CGModule, globalValue: LLVMValueRef, declarationsOnly!: Bool): Bool {
    if (!CGFunction.HasNoUse(globalValue) || IsRetainedGlobalValue(cgMod, globalValue, checkCompileUnit: true)) {
        return false
    }
    if (declarationsOnly) {
        return unsafe { LLVMIsDeclaration(globalValue) } != 0
    }
    return unsafe { LLVMIsDeclaration(globalValue) } != 0 || IsLocalLinkage(globalValue)
}

private func CanEraseFunction(cgMod: CGModule, functionValue: LLVMValueRef, declarationsOnly!: Bool): Bool {
    if (!CGFunction.HasNoUse(functionValue) || IsRetainedGlobalValue(cgMod, functionValue, checkCompileUnit: false)) {
        return false
    }
    if (declarationsOnly) {
        return IsFunctionDeclaration(functionValue)
    }
    return IsFunctionDeclaration(functionValue) || IsLocalLinkage(functionValue)
}

private func IsRetainedGlobalValue(cgMod: CGModule, globalValue: LLVMValueRef, checkCompileUnit!: Bool): Bool {
    let name = unsafe { LLVMGetValueName(globalValue) }
    if (name.isNull()) {
        return false
    }
    if (checkCompileUnit && cgMod.GetCGContext().IsGlobalsOfCompileUnitCString(name)) {
        return true
    }
    if (CGContext.ContainsCString(cgMod.GetCGContext().GetLLVMUsedVars(), name)) {
        return true
    }
    return IsLinkNameUsedInMetaCString(cgMod, name)
}

private func IsFunctionDeclaration(functionValue: LLVMValueRef): Bool {
    return unsafe { LLVMIsDeclaration(functionValue) } != 0
}

private func IsLocalLinkage(globalValue: LLVMValueRef): Bool {
    let linkage = unsafe { LLVMGetLinkage(globalValue) }
    return linkage == LLVMLinkageValue(LLVMLinkage.Internal) ||
        linkage == LLVMLinkageValue(LLVMLinkage.Private)
}

private func HasLLVMName(value: LLVMValueRef, expected: String): Bool {
    let name = unsafe { LLVMGetValueName(value) }
    if (name.isNull()) {
        return false
    }
    var matched = false
    try (expectedCString = unsafe { LibC.mallocCString(expected) }.asResource()) {
        matched = unsafe { strcmp(name, expectedCString.value) } == 0
    }
    return matched
}

private func IsLinkNameUsedInMetaCString(cgMod: CGModule, linkageName: CString): Bool {
    for (name in cgMod.GetLinkNamesUsedInMeta()) {
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (unsafe { strcmp(linkageName, nameCString.value) } == 0) {
                return true
            }
        }
    }
    return false
}
