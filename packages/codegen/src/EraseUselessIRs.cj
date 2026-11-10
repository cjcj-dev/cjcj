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
    let retainedNames = RetainedNames(cgMod)
    var erased = true
    while (erased) {
        erased = false
        let globals = CollectIRGlobals(moduleRef)
        for (globalValue in globals) {
            unsafe { LLVMSelfhostGlobalValueRemoveDeadConstantUsers(globalValue) }
            if (CanEraseGlobal(retainedNames, globalValue, declarationsOnly: declarationsOnly)) {
                unsafe { LLVMDeleteGlobal(globalValue) }
                erased = true
            }
        }
        let functionValues = CollectIRFunctions(moduleRef)
        for (functionValue in functionValues) {
            unsafe { LLVMSelfhostGlobalValueRemoveDeadConstantUsers(functionValue) }
            if (CanEraseFunction(retainedNames, functionValue, declarationsOnly: declarationsOnly)) {
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

private func CanEraseGlobal(retainedNames: RetainedNames, globalValue: LLVMValueRef, declarationsOnly!: Bool): Bool {
    if (!CGFunction.HasNoUse(globalValue) || retainedNames.Contains(globalValue, checkCompileUnit: true)) {
        return false
    }
    if (declarationsOnly) {
        return unsafe { LLVMIsDeclaration(globalValue) } != 0
    }
    return unsafe { LLVMIsDeclaration(globalValue) } != 0 || IsLocalLinkage(globalValue)
}

private func CanEraseFunction(retainedNames: RetainedNames, functionValue: LLVMValueRef, declarationsOnly!: Bool): Bool {
    if (!CGFunction.HasNoUse(functionValue) || retainedNames.Contains(functionValue, checkCompileUnit: false)) {
        return false
    }
    if (declarationsOnly) {
        return IsFunctionDeclaration(functionValue)
    }
    return IsFunctionDeclaration(functionValue) || IsLocalLinkage(functionValue)
}

// The names that keep an unused global or function, for one EraseUnusedGVsAndFunctions run.
// The run only deletes globals and functions: it adds no entry to the two context sets and no
// module metadata. So the NUL state of the context sets is read once, and the metadata link
// names are collected once at the first query that reaches them, also when none exist.
private class RetainedNames {
    private let cgMod: CGModule
    private let cgCtx: CGContext
    private let compileUnitGlobalsHaveNul: Bool
    private let usedVars: HashSet<String>
    private let usedVarsHaveNul: Bool
    private var metaNames: Option<HashSet<String>> = None
    private var metaNamesHaveNul: Bool = false

    init(cgMod: CGModule) {
        let context = cgMod.GetCGContext()
        let usedNames = context.GetLLVMUsedVars()
        this.cgMod = cgMod
        this.cgCtx = context
        this.compileUnitGlobalsHaveNul = context.GlobalsOfCompileUnitHaveNul()
        this.usedVars = usedNames
        this.usedVarsHaveNul = CGContext.HasNulEntry(usedNames)
    }

    func Contains(globalValue: LLVMValueRef, checkCompileUnit!: Bool): Bool {
        let name = unsafe { LLVMGetValueName(globalValue) }
        if (name.isNull()) {
            return false
        }
        let converted = CGContext.CheckedString(name)
        if (checkCompileUnit && cgCtx.IsGlobalsOfCompileUnitCString(name, compileUnitGlobalsHaveNul, converted)) {
            return true
        }
        if (CGContext.ContainsCString(usedVars, usedVarsHaveNul, name, converted)) {
            return true
        }
        let names = match (metaNames) {
            case Some(collected) => collected
            case None =>
                let (collected, haveNul) = cgMod.GetLinkNamesUsedInMetaWithNulState()
                metaNames = Some(collected)
                metaNamesHaveNul = haveNul
                collected
        }
        return CGContext.ContainsCString(names, metaNamesHaveNul, name, converted)
    }
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
