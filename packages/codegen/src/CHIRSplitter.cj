package cangjie_compiler::codegen

import std.collection.*
import std.sort.*
import cangjie_compiler::basic.Errorln
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar
@When[os == "Windows"]
import cangjie_compiler::basic.StringConvertor
import cangjie_compiler::utils.{CJC_ASSERT, FileUtil, REFLECT_PACKAGE_NAME}

private var counter: Int64 = 0

private func GetSubCHIRPackageIdx(splitNum: Int64): Int64 {
    let idx = counter % splitNum
    counter++
    return idx
}

private func DumpIR(llvmModule: LLVMModuleHandle, filePath: String): Unit {
    if (filePath.isEmpty()) {
        print(llvmModule.PrintToString())
        return
    }
    @When[os == "Windows"]
    let tempPath = StringConvertor.NormalizeStringToUTF8(filePath)
    @When[os == "Windows"]
    let normalizedPath = if (let Some(value) <- tempPath) {
        value
    } else {
        CJC_ASSERT(false)
        filePath
    }
    @When[os != "Windows"]
    let normalizedPath = filePath
    let _ = FileUtil.WriteToFile(normalizedPath, llvmModule.PrintToString())
}

private func SaveToBitcodeFile(module: LLVMModuleHandle, bcFilePath: String): Bool {
    @When[os == "Windows"]
    let tempPath = StringConvertor.NormalizeStringToUTF8(bcFilePath)
    @When[os == "Windows"]
    let path = if (let Some(value) <- tempPath) {
        value
    } else {
        CJC_ASSERT(false)
        bcFilePath
    }
    @When[os != "Windows"]
    let path = bcFilePath
    let result = LLVMWriteBitcodeToFileChecked(module, path)
    if (!result.ok) {
        Errorln("Failed to write bitcode to file:" + result.message)
        return false
    }
    return true
}

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
        subCHIRPackageIdx = GetSubCHIRPackageIdx(splitNum)
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
        let name = globalVar.GetIdentifierWithoutPrefix()
        var idx: Int64 = 0
        while (idx < chirGVs.size) {
            let ownedName = chirGVs[idx].GetIdentifierWithoutPrefix()
            if (ownedName == name) {
                return false
            }
            if (name < ownedName) {
                chirGVs.add(globalVar, at: idx)
                return true
            }
            idx++
        }
        chirGVs.add(globalVar)
        return true
    }

    public func AddCustomDef(def: CustomTypeDef): Bool {
        let name = def.GetIdentifierWithoutPrefix()
        var idx: Int64 = 0
        while (idx < chirCustomDefs.size) {
            let ownedName = chirCustomDefs[idx].GetIdentifierWithoutPrefix()
            if (ownedName == name) {
                return false
            }
            if (name < ownedName) {
                chirCustomDefs.add(def, at: idx)
                return true
            }
            idx++
        }
        chirCustomDefs.add(def)
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
        return AddFunctionTo(chirFuncs, fn)
    }

    private func AddFunctionTo(functions: ArrayList<Function>, fn: Function): Bool {
        let name = fn.GetIdentifierWithoutPrefix()
        var idx: Int64 = 0
        while (idx < functions.size) {
            let ownedName = functions[idx].GetIdentifierWithoutPrefix()
            if (ownedName == name) {
                return false
            }
            if (name < ownedName) {
                functions.add(fn, at: idx)
                return true
            }
            idx++
        }
        functions.add(fn)
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
        return AddFunctionTo(chirForeigns, fn)
    }

    public func AddImportedCFunc(fn: Function): Bool {
        return AddFunctionTo(chirImportedCFuncs, fn)
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

private class SubCHIRPackagesCache {
    var splitNum: Option<Int64> = None
    let classesCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let enumsCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let structsCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let extendDefCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let gvsCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let funcsCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let foreignsCache: HashMap<String, Int64> = HashMap<String, Int64>()
    let importedCFuncsCache: HashMap<String, Int64> = HashMap<String, Int64>()
}

public class CHIRSplitter {
    private let cgPkgCtx: CGPkgContext
    private var splitNum: Int64 = 0
    private var index: Int64 = 0
    private let subCHIRPackagesCache: SubCHIRPackagesCache = SubCHIRPackagesCache()

    public init(cgPkgCtx: CGPkgContext) {
        this.cgPkgCtx = cgPkgCtx
    }

    public func SplitCHIRPackage(): ArrayList<SubCHIRPackage> {
        LoadSubCHIRPackagesInfo()
        CalcSplitsNum()
        index = 0
        let packages = ArrayList<SubCHIRPackage>()
        var idx: Int64 = 0
        while (idx < splitNum) {
            let subPackage = SubCHIRPackage(splitNum)
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
        SaveSubCHIRPackagesInfo()
        RegisterOwnedTypeTemplates(packages)
        return packages
    }

    private func CalcSplitsNum(): Unit {
        if (let Some(cachedSplitNum) <- subCHIRPackagesCache.splitNum) {
            splitNum = cachedSplitNum
            return
        }
        let options = cgPkgCtx.GetGlobalOptions()
        let chirPkg = cgPkgCtx.GetCHIRPackage()
        splitNum = if (options.aggressiveParallelCompile.hasValue) {
            Int64(options.aggressiveParallelCompile.value)
        } else {
            1
        }
        let bodyFuncCount = chirPkg.GetGlobalFuncsWithBody().size
        if (splitNum > bodyFuncCount) {
            splitNum = bodyFuncCount
        }
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

    private func FindIdxInCache(key: String): Int64 {
        if (subCHIRPackagesCache.classesCache.contains(key)) {
            return subCHIRPackagesCache.classesCache[key]
        }
        if (subCHIRPackagesCache.structsCache.contains(key)) {
            return subCHIRPackagesCache.structsCache[key]
        }
        if (subCHIRPackagesCache.enumsCache.contains(key)) {
            return subCHIRPackagesCache.enumsCache[key]
        }
        let idx = index % splitNum
        index++
        return idx
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
        let orderedPackages = ArrayList<SubCHIRPackage>()
        for (subPackage in packages) {
            orderedPackages.add(subPackage)
        }
        for (subPackage in packages) {
            orderedPackages[subPackage.subCHIRPackageIdx] = subPackage
        }
        var packageIdx: Int64 = 0
        while (packageIdx < packages.size) {
            packages[packageIdx] = orderedPackages[packageIdx]
            packageIdx++
        }
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
            let initName = initFn.GetIdentifierWithoutPrefix()
            let targetIndex = if (subCHIRPackagesCache.funcsCache.contains(initName)) {
                subCHIRPackagesCache.funcsCache[initName]
            } else {
                FindLightestPackage(packages)
            }
            packages[targetIndex].mainModule = true
            if (!subCHIRPackagesCache.funcsCache.contains(initName)) {
                subCHIRPackagesCache.funcsCache[initName] = targetIndex
            }
            if (packages[targetIndex].AddFunction(initFn)) {
                packages[targetIndex].exprNumInChirFuncs += FunctionExprNum(initFn)
            }
            if (let Some(literalFn) <- literalInitFunc) {
                let literalName = literalFn.GetIdentifierWithoutPrefix()
                if (!subCHIRPackagesCache.funcsCache.contains(literalName)) {
                    subCHIRPackagesCache.funcsCache[literalName] = targetIndex
                }
                if (packages[targetIndex].AddFunction(literalFn)) {
                    packages[targetIndex].exprNumInChirFuncs += FunctionExprNum(literalFn)
                }
            }
            for (toAnyFn in toAnyFuncs) {
                let toAnyName = toAnyFn.GetIdentifierWithoutPrefix()
                if (!subCHIRPackagesCache.funcsCache.contains(toAnyName)) {
                    subCHIRPackagesCache.funcsCache[toAnyName] = targetIndex
                }
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
            let targetIndex = if (subCHIRPackagesCache.funcsCache.contains(name)) {
                subCHIRPackagesCache.funcsCache[name]
            } else {
                FindLightestPackage(packages)
            }
            if (packages[targetIndex].AddFunction(item.fn)) {
                packages[targetIndex].exprNumInChirFuncs += item.exprNum
            }
            if (!subCHIRPackagesCache.funcsCache.contains(name)) {
                subCHIRPackagesCache.funcsCache[name] = targetIndex
            }
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
            let targetIndex = if (subCHIRPackagesCache.foreignsCache.contains(name)) {
                subCHIRPackagesCache.foreignsCache[name]
            } else {
                FindLightestPackage(packages)
            }
            if (packages[targetIndex].AddForeign(fn)) {
                packages[targetIndex].exprNumInChirFuncs += 1
            }
            if (!subCHIRPackagesCache.foreignsCache.contains(name)) {
                subCHIRPackagesCache.foreignsCache[name] = targetIndex
            }
        }
    }

    private func SplitCHIRGlobalVars(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (globalVar in cgPkgCtx.GetCHIRPackage().GetGlobalVarsWithInit()) {
            let name = globalVar.GetIdentifierWithoutPrefix()
            let targetIndex = if (subCHIRPackagesCache.gvsCache.contains(name)) {
                subCHIRPackagesCache.gvsCache[name]
            } else {
                NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddGlobalVar(globalVar)
            if (!subCHIRPackagesCache.gvsCache.contains(name)) {
                subCHIRPackagesCache.gvsCache[name] = targetIndex
            }
        }
    }

    private func SplitCHIRClasses(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetClasses()) {
            var targetIndex: Int64 = 0
            if (cgPkgCtx.GetGlobalOptions().enIncrementalCompilation) {
                let key = customDef.GetPackageName() + ":" + customDef.GetSrcCodeIdentifier()
                targetIndex = FindIdxInCache(key)
                if (!subCHIRPackagesCache.classesCache.contains(key)) {
                    subCHIRPackagesCache.classesCache[key] = targetIndex
                }
            } else {
                targetIndex = NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddCustomDef(customDef)
        }
    }

    private func SplitCHIREnums(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetEnums()) {
            var targetIndex: Int64 = 0
            if (cgPkgCtx.GetGlobalOptions().enIncrementalCompilation) {
                let key = customDef.GetPackageName() + ":" + customDef.GetSrcCodeIdentifier()
                targetIndex = FindIdxInCache(key)
                if (!subCHIRPackagesCache.enumsCache.contains(key)) {
                    subCHIRPackagesCache.enumsCache[key] = targetIndex
                }
            } else {
                targetIndex = NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddCustomDef(customDef)
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetImportedEnums()) {
            var targetIndex: Int64 = 0
            if (cgPkgCtx.GetGlobalOptions().enIncrementalCompilation) {
                let key = customDef.GetPackageName() + ":" + customDef.GetSrcCodeIdentifier()
                targetIndex = FindIdxInCache(key)
                if (!subCHIRPackagesCache.enumsCache.contains(key)) {
                    subCHIRPackagesCache.enumsCache[key] = targetIndex
                }
            } else {
                targetIndex = NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddCustomDef(customDef)
        }
    }

    private func SplitCHIRStructs(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetStructs()) {
            var targetIndex: Int64 = 0
            if (cgPkgCtx.GetGlobalOptions().enIncrementalCompilation) {
                let key = customDef.GetPackageName() + ":" + customDef.GetSrcCodeIdentifier()
                targetIndex = FindIdxInCache(key)
                if (!subCHIRPackagesCache.structsCache.contains(key)) {
                    subCHIRPackagesCache.structsCache[key] = targetIndex
                }
            } else {
                targetIndex = NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddCustomDef(customDef)
        }
    }

    private func SplitCHIRExtends(packages: ArrayList<SubCHIRPackage>): Unit {
        if (packages.isEmpty()) {
            return
        }
        for (customDef in cgPkgCtx.GetCHIRPackage().GetExtends()) {
            let key = customDef.GetIdentifierWithoutPrefix()
            let targetIndex = if (subCHIRPackagesCache.extendDefCache.contains(key)) {
                subCHIRPackagesCache.extendDefCache[key]
            } else {
                NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddCustomDef(customDef)
            if (!subCHIRPackagesCache.extendDefCache.contains(key)) {
                subCHIRPackagesCache.extendDefCache[key] = targetIndex
            }
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
            let targetIndex = if (subCHIRPackagesCache.importedCFuncsCache.contains(name)) {
                subCHIRPackagesCache.importedCFuncsCache[name]
            } else {
                NextRoundRobinIndex(packages)
            }
            let _ = packages[targetIndex].AddImportedCFunc(fn)
            if (!subCHIRPackagesCache.importedCFuncsCache.contains(name)) {
                subCHIRPackagesCache.importedCFuncsCache[name] = targetIndex
            }
        }
    }

    private func LoadSubCHIRPackagesInfo(): Unit {
        if (!cgPkgCtx.IsIncrementEnabled()) {
            return
        }

        let rawPath = cgPkgCtx.GetGlobalOptions().GenerateCachedPathNameForCodeGen(cgPkgCtx.GetCurrentPkgName(), ".cgCache")
        if (!FileUtil.FileExist(rawPath)) {
            return
        }
        @When[os == "Windows"]
        let tempPath = StringConvertor.NormalizeStringToUTF8(rawPath)
        @When[os == "Windows"]
        let path = if (let Some(value) <- tempPath) {
            value
        } else {
            CJC_ASSERT(false)
            rawPath
        }
        @When[os != "Windows"]
        let path = rawPath

        try (context = LLVMContextHandle.Create()) {
            var parseResult = LLVMParseIRFile(context, path, name: path)
            if (!parseResult.ok) {
                parseResult = LLVMParseBitcodeFile(context, path, name: path)
            }
            if (!parseResult.ok) {
                throw IllegalStateException(parseResult.message)
            }
            let module = parseResult.module

            CJC_ASSERT(!LLVMGetNamedMetadata(module, "splitNum").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "splitNum")) {
                let operands = LLVMGetMDNodeOperands(mdNode)
                subCHIRPackagesCache.splitNum = Int64(unsafe { LLVMConstIntGetZExtValue(operands[0]) })
            }

            let parseEntries = { mdNode: LLVMValueRef =>
                let operands = LLVMGetMDNodeOperands(mdNode)
                let name = if (let Some(value) <- LLVMGetMDStringValue(operands[0])) {
                    value
                } else {
                    CJC_ASSERT(false)
                    ""
                }
                let idx = Int64(unsafe { LLVMConstIntGetZExtValue(operands[1]) })
                (name, idx)
            }

            CJC_ASSERT(!LLVMGetNamedMetadata(module, "classes").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "classes")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.classesCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "enums").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "enums")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.enumsCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "structs").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "structs")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.structsCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "extends").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "extends")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.extendDefCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "gvs").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "gvs")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.gvsCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "funcs").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "funcs")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.funcsCache[name] = idx
            }
            CJC_ASSERT(!LLVMGetNamedMetadata(module, "foreigns").isNull())
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "foreigns")) {
                let (name, idx) = parseEntries(mdNode)
                subCHIRPackagesCache.foreignsCache[name] = idx
            }
            module.close()
        }
    }

    private func SaveSubCHIRPackagesInfo(): Unit {
        if (!cgPkgCtx.GetGlobalOptions().enIncrementalCompilation) {
            return
        }

        try (context = LLVMContextHandle.Create(), module = LLVMModuleHandle.Create(cgPkgCtx.GetCurrentPkgName(), context)) {
            LLVMGetOrInsertNamedMetadata(module, "splitNum")
            LLVMAddNamedMetadataOperand(module, "splitNum",
                LLVMCreateMDTuple(context, CreateUInt32Metadata(context, UInt64(splitNum))))

            LLVMGetOrInsertNamedMetadata(module, "classes")
            let classEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.classesCache) {
                classEntries.add((name, idx))
            }
            sort(classEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (klass in classEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, klass[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(klass[1])))
                LLVMAddNamedMetadataOperand(module, "classes", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "enums")
            let enumEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.enumsCache) {
                enumEntries.add((name, idx))
            }
            sort(enumEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (en in enumEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, en[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(en[1])))
                LLVMAddNamedMetadataOperand(module, "enums", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "structs")
            let structEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.structsCache) {
                structEntries.add((name, idx))
            }
            sort(structEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (st in structEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, st[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(st[1])))
                LLVMAddNamedMetadataOperand(module, "structs", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "extends")
            let extendEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.extendDefCache) {
                extendEntries.add((name, idx))
            }
            sort(extendEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (extendEntry in extendEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, extendEntry[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(extendEntry[1])))
                LLVMAddNamedMetadataOperand(module, "extends", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "gvs")
            let gvEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.gvsCache) {
                gvEntries.add((name, idx))
            }
            sort(gvEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (gv in gvEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, gv[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(gv[1])))
                LLVMAddNamedMetadataOperand(module, "gvs", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "funcs")
            let funcEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.funcsCache) {
                funcEntries.add((name, idx))
            }
            sort(funcEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (funcEntry in funcEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, funcEntry[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(funcEntry[1])))
                LLVMAddNamedMetadataOperand(module, "funcs", LLVMCreateMDTuple(context, operands))
            }

            LLVMGetOrInsertNamedMetadata(module, "foreigns")
            let foreignEntries = ArrayList<(String, Int64)>()
            for ((name, idx) in subCHIRPackagesCache.foreignsCache) {
                foreignEntries.add((name, idx))
            }
            sort(foreignEntries, by: { left: (String, Int64), right: (String, Int64) =>
                if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
            }, stable: true)
            for (foreignEntry in foreignEntries) {
                let operands = ArrayList<LLVMMetadataRef>()
                operands.add(LLVMCreateMDString(context, foreignEntry[0]))
                operands.add(CreateUInt32Metadata(context, UInt64(foreignEntry[1])))
                LLVMAddNamedMetadataOperand(module, "foreigns", LLVMCreateMDTuple(context, operands))
            }

            let rawPath = cgPkgCtx.GetGlobalOptions().GenerateCachedPathNameForCodeGen(cgPkgCtx.GetCurrentPkgName(), ".cgCache")
            @When[os == "Windows"]
            let tempPath = StringConvertor.NormalizeStringToUTF8(rawPath)
            @When[os == "Windows"]
            let path = if (let Some(value) <- tempPath) {
                value
            } else {
                CJC_ASSERT(false)
                rawPath
            }
            @When[os != "Windows"]
            let path = rawPath
            if (cgPkgCtx.GetGlobalOptions().NeedDumpIRToFile()) {
                DumpIR(module, path)
            } else {
                let _ = SaveToBitcodeFile(module, path)
            }
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
