package cangjie_compiler::codegen

import std.collection.*
import std.sort.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::utils.REFLECT_PACKAGE_NAME

public class SubCHIRPackage {
    public var mainModule: Bool = false
    public var subCHIRPackageIdx: Int64 = 0
    public var exprNumInChirFuncs: Int64 = 0
    public var splitNum: Int64
    public let chirCustomDefs: ArrayList<CustomTypeDef> = ArrayList<CustomTypeDef>()
    public let chirGVs: ArrayList<GlobalVar> = ArrayList<GlobalVar>()
    public let chirFuncs: ArrayList<Function> = ArrayList<Function>()
    public let chirForeigns: ArrayList<Function> = ArrayList<Function>()
    public let chirImportedCFuncs: ArrayList<Function> = ArrayList<Function>()
    private let ownedTypeTemplateNames: HashSet<String> = HashSet<String>()

    public init(splitNum: Int64) {
        this.splitNum = splitNum
    }

    public func Clear(): Unit {
        chirCustomDefs.clear()
        chirGVs.clear()
        chirFuncs.clear()
        chirForeigns.clear()
        chirImportedCFuncs.clear()
        ownedTypeTemplateNames.clear()
    }

    public func OwnsCustomDef(def: CustomTypeDef): Bool {
        for (ownedDef in chirCustomDefs) {
            if (ownedDef.nodeId == def.nodeId) {
                return true
            }
        }
        return false
    }

    public func OwnsGlobalVar(globalVar: GlobalVar): Bool {
        let name = globalVar.GetIdentifierWithoutPrefix()
        for (ownedGV in chirGVs) {
            if (ownedGV.GetIdentifierWithoutPrefix() == name) {
                return true
            }
        }
        return false
    }

    public func AddGlobalVar(globalVar: GlobalVar): Bool {
        if (OwnsGlobalVar(globalVar)) {
            return false
        }
        chirGVs.add(globalVar)
        return true
    }

    public func OwnsFunction(fn: Function): Bool {
        let name = fn.GetIdentifierWithoutPrefix()
        for (ownedFn in chirFuncs) {
            if (ownedFn.GetIdentifierWithoutPrefix() == name) {
                return true
            }
        }
        return false
    }

    public func AddFunction(fn: Function): Bool {
        if (OwnsFunction(fn)) {
            return false
        }
        chirFuncs.add(fn)
        return true
    }

    private func ContainsFunction(functions: ArrayList<Function>, fn: Function): Bool {
        let name = fn.GetIdentifierWithoutPrefix()
        for (ownedFn in functions) {
            if (ownedFn.GetIdentifierWithoutPrefix() == name) {
                return true
            }
        }
        return false
    }

    public func AddForeign(fn: Function): Bool {
        if (ContainsFunction(chirForeigns, fn)) {
            return false
        }
        chirForeigns.add(fn)
        return true
    }

    public func AddImportedCFunc(fn: Function): Bool {
        if (ContainsFunction(chirImportedCFuncs, fn)) {
            return false
        }
        chirImportedCFuncs.add(fn)
        return true
    }

    public func AddOwnedTypeTemplateName(name: String): Unit {
        ownedTypeTemplateNames.add(name)
    }

    public func OwnsTypeTemplateName(name: String): Bool {
        return ownedTypeTemplateNames.contains(name)
    }
}

private class FunctionSplitItem {
    let exprNum: Int64
    let fn: Function

    init(exprNum: Int64, fn: Function) {
        this.exprNum = exprNum
        this.fn = fn
    }
}

public class CHIRSplitter {
    private let cgPkgCtx: CGPkgContext
    private var splitNum: Int64 = 0
    private var index: Int64 = 0
    private let functionOwnerIndices: HashMap<String, Int64> = HashMap<String, Int64>()
    private let foreignOwnerIndices: HashMap<String, Int64> = HashMap<String, Int64>()
    private let importedCFuncOwnerIndices: HashMap<String, Int64> = HashMap<String, Int64>()
    private let globalVarOwnerIndices: HashMap<String, Int64> = HashMap<String, Int64>()

    public init(cgPkgCtx: CGPkgContext) {
        this.cgPkgCtx = cgPkgCtx
    }

    public func SplitCHIRPackage(): ArrayList<SubCHIRPackage> {
        splitNum = CalcSplitsNum()
        index = 0
        functionOwnerIndices.clear()
        foreignOwnerIndices.clear()
        importedCFuncOwnerIndices.clear()
        globalVarOwnerIndices.clear()
        let packages = ArrayList<SubCHIRPackage>()
        var idx: Int64 = 0
        while (idx < splitNum) {
            let subPackage = SubCHIRPackage(splitNum)
            subPackage.subCHIRPackageIdx = idx
            packages.add(subPackage)
            idx++
        }
        SplitCHIRFunctions(packages)
        SplitCHIRClasses(packages)
        SplitCHIREnums(packages)
        SplitCHIRStructs(packages)
        SplitCHIRExtends(packages)
        SplitCHIRGlobalVars(packages)
        SplitCHIRImportedCFuncs(packages)
        RegisterOwnedTypeTemplates(packages)
        return packages
    }

    private func CalcSplitsNum(): Int64 {
        let options = cgPkgCtx.GetGlobalOptions()
        let chirPkg = cgPkgCtx.GetCHIRPackage()
        var count = if (options.aggressiveParallelCompile.hasValue) {
            Int64(options.aggressiveParallelCompile.value)
        } else {
            1
        }
        let bodyFuncCount = chirPkg.GetGlobalFuncsWithBody().size
        if (count > bodyFuncCount) {
            count = bodyFuncCount
        }
        return count
    }

    private func NextRoundRobinIndex(packages: ArrayList<SubCHIRPackage>): Int64 {
        let idx = index % packages.size
        index++
        return idx
    }

    private func FindLightestPackage(packages: ArrayList<SubCHIRPackage>): Int64 {
        var best: Int64 = 0
        var idx: Int64 = 1
        while (idx < packages.size) {
            if (packages[idx].exprNumInChirFuncs < packages[best].exprNumInChirFuncs ||
                (packages[idx].exprNumInChirFuncs == packages[best].exprNumInChirFuncs &&
                packages[idx].subCHIRPackageIdx < packages[best].subCHIRPackageIdx)) {
                best = idx
            }
            idx++
        }
        return best
    }

    private func FunctionExprNum(fn: Function): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return body.GetExpressionsNum()
        }
        return 0
    }

    private func SplitCHIRFunctions(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        let chirPkg = cgPkgCtx.GetCHIRPackage()
        let packageInitFunc = chirPkg.GetPackageInitFunc()
        let literalInitFunc = chirPkg.GetPackageLiteralInitFunc()
        let toAnyFuncs = ArrayList<Function>()
        let normalFuncs = ArrayList<FunctionSplitItem>()
        for (fn in chirPkg.GetGlobalFuncsWithBody()) {
            if (chirPkg.GetName() == REFLECT_PACKAGE_NAME && fn.GetSrcCodeIdentifier() == "toAny") {
                toAnyFuncs.add(fn)
            } else if (!SameFunction(fn, packageInitFunc) && !SameFunction(fn, literalInitFunc)) {
                normalFuncs.add(FunctionSplitItem(FunctionExprNum(fn), fn))
            }
        }
        SplitSpecialFuncs(packages, packageInitFunc, literalInitFunc, toAnyFuncs)
        SplitNormalFuncs(packages, normalFuncs)
        SplitForeigns(packages)
    }

    private func SameFunction(fn: Function, other: Option<Function>): Bool {
        if (let Some(otherFn) <- other) {
            return fn.GetIdentifier() == otherFn.GetIdentifier()
        }
        return false
    }

    private func SplitSpecialFuncs(packages: ArrayList<SubCHIRPackage>, packageInitFunc: Option<Function>,
        literalInitFunc: Option<Function>, toAnyFuncs: ArrayList<Function>): Unit {
        if (let Some(initFn) <- packageInitFunc) {
            let targetIndex = FindLightestPackage(packages)
            packages[targetIndex].mainModule = true
            functionOwnerIndices[initFn.GetIdentifierWithoutPrefix()] = targetIndex
            if (packages[targetIndex].AddFunction(initFn)) {
                packages[targetIndex].exprNumInChirFuncs += FunctionExprNum(initFn)
            }
            if (let Some(literalFn) <- literalInitFunc) {
                functionOwnerIndices[literalFn.GetIdentifierWithoutPrefix()] = targetIndex
                if (packages[targetIndex].AddFunction(literalFn)) {
                    packages[targetIndex].exprNumInChirFuncs += FunctionExprNum(literalFn)
                }
            }
            for (toAnyFn in toAnyFuncs) {
                functionOwnerIndices[toAnyFn.GetIdentifierWithoutPrefix()] = targetIndex
                if (packages[targetIndex].AddFunction(toAnyFn)) {
                    packages[targetIndex].exprNumInChirFuncs += FunctionExprNum(toAnyFn)
                }
            }
        }
    }

    private func SplitNormalFuncs(packages: ArrayList<SubCHIRPackage>,
        normalFuncs: ArrayList<FunctionSplitItem>): Unit {
        sort(normalFuncs, by: { left: FunctionSplitItem, right: FunctionSplitItem =>
            if (left.exprNum < right.exprNum) {
                Ordering.LT
            } else if (left.exprNum > right.exprNum) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        var idx = normalFuncs.size - 1
        while (idx >= 0) {
            let item = normalFuncs[idx]
            let name = item.fn.GetIdentifierWithoutPrefix()
            let targetIndex = if (functionOwnerIndices.contains(name)) {
                functionOwnerIndices[name]
            } else {
                FindLightestPackage(packages)
            }
            if (packages[targetIndex].AddFunction(item.fn)) {
                packages[targetIndex].exprNumInChirFuncs += item.exprNum
            }
            functionOwnerIndices[name] = targetIndex
            idx--
        }
    }

    private func SplitForeigns(packages: ArrayList<SubCHIRPackage>): Unit {
        let chirPkg = cgPkgCtx.GetCHIRPackage()
        for (fn in chirPkg.GetGlobalFuncsWithoutBody()) {
            if (!fn.TestAttr(Attribute.FOREIGN) || fn.GetPackageName() != chirPkg.GetName()) {
                continue
            }
            let name = fn.GetIdentifierWithoutPrefix()
            let targetIndex = if (foreignOwnerIndices.contains(name)) {
                foreignOwnerIndices[name]
            } else {
                FindLightestPackage(packages)
            }
            if (packages[targetIndex].AddForeign(fn)) {
                packages[targetIndex].exprNumInChirFuncs += 1
            }
            foreignOwnerIndices[name] = targetIndex
        }
    }

    private func SplitCHIRGlobalVars(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (globalVar in cgPkgCtx.GetCHIRPackage().GetGlobalVarsWithInit()) {
            let name = globalVar.GetIdentifierWithoutPrefix()
            let targetIndex = if (globalVarOwnerIndices.contains(name)) {
                globalVarOwnerIndices[name]
            } else {
                NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddGlobalVar(globalVar)
            globalVarOwnerIndices[name] = targetIndex
        }
    }

    private func SplitCHIRClasses(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetClasses()) {
            let targetIndex = NextRoundRobinIndex(packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
        }
    }

    private func SplitCHIREnums(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetEnums()) {
            let targetIndex = NextRoundRobinIndex(packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetImportedEnums()) {
            let targetIndex = NextRoundRobinIndex(packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
        }
    }

    private func SplitCHIRStructs(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetStructs()) {
            let targetIndex = NextRoundRobinIndex(packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
        }
    }

    private func SplitCHIRExtends(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetExtends()) {
            let targetIndex = NextRoundRobinIndex(packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
        }
    }

    private func SplitCHIRImportedCFuncs(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (fn in cgPkgCtx.GetCHIRPackage().GetGlobalFuncsWithoutBody()) {
            let isCFunc = if (let Some(funcTy) <- fn.GetFuncType()) {
                funcTy.IsCFunc()
            } else {
                false
            }
            if (!isCFunc || (!fn.TestAttr(Attribute.PRIVATE) && !fn.TestAttr(Attribute.FOREIGN))) {
                continue
            }
            let name = fn.GetIdentifierWithoutPrefix()
            let targetIndex = if (importedCFuncOwnerIndices.contains(name)) {
                importedCFuncOwnerIndices[name]
            } else {
                NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddImportedCFunc(fn)
            importedCFuncOwnerIndices[name] = targetIndex
        }
    }

    private func RegisterOwnedTypeTemplates(packages: ArrayList<SubCHIRPackage>): Unit {
        let seen = HashSet<String>()
        for (subPackage in packages) {
            for (customDef in subPackage.chirCustomDefs) {
                if (customDef.IsExtend() || !customDef.IsGenericDef()) {
                    continue
                }
                if (let Some(customTy) <- customDef.GetType()) {
                    let typeTemplateName = CGType.GetNameOfTypeTemplateGV(customTy)
                    if (!seen.contains(typeTemplateName)) {
                        seen.add(typeTemplateName)
                        subPackage.AddOwnedTypeTemplateName(typeTemplateName)
                    }
                }
            }
        }
    }
}
