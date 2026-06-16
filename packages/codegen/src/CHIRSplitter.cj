package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GlobalVar

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

    public init(splitNum: Int64) {
        this.splitNum = splitNum
    }

    public func Clear(): Unit {
        chirCustomDefs.clear()
        chirGVs.clear()
        chirFuncs.clear()
        chirForeigns.clear()
        chirImportedCFuncs.clear()
        exprNumInChirFuncs = 0
    }
}

public class CHIRSplitter {
    private let cgPkgCtx: CGPkgContext

    public init(cgPkgCtx: CGPkgContext) {
        this.cgPkgCtx = cgPkgCtx
    }

    public func SplitCHIRPackage(): ArrayList<SubCHIRPackage> {
        let splitCount = CalcSplitsNum()
        let packages = ArrayList<SubCHIRPackage>()
        var idx: Int64 = 0
        while (idx < splitCount) {
            let subPackage = SubCHIRPackage(splitCount)
            subPackage.subCHIRPackageIdx = idx
            packages.add(subPackage)
            idx++
        }
        if (packages.isEmpty()) {
            packages.add(SubCHIRPackage(1))
        }
        packages[0].mainModule = true
        SplitCHIRFunctions(packages)
        SplitCHIRGlobalVars(packages)
        SplitCHIRTypes(packages)
        return packages
    }

    private func CalcSplitsNum(): Int64 {
        let options = cgPkgCtx.GetGlobalOptions()
        if (options.aggressiveParallelCompile.hasValue && options.aggressiveParallelCompile.value > 1u64) {
            return Int64(options.aggressiveParallelCompile.value)
        }
        return 1
    }

    private func PickIndex(serial: Int64, packages: ArrayList<SubCHIRPackage>): Int64 {
        if (packages.isEmpty()) {
            return 0
        }
        return serial % packages.size
    }

    private func SplitCHIRFunctions(packages: ArrayList<SubCHIRPackage>): Unit {
        var serial: Int64 = 0
        for (fn in cgPkgCtx.GetCHIRPackage().GetGlobalFunctions(includePureAbstract: true)) {
            let targetIndex = PickIndex(serial, packages)
            if (fn.IsImportedFunc()) {
                packages[targetIndex].chirForeigns.add(fn)
            } else {
                packages[targetIndex].chirFuncs.add(fn)
            }
            serial++
        }
    }

    private func SplitCHIRGlobalVars(packages: ArrayList<SubCHIRPackage>): Unit {
        var serial: Int64 = 0
        for (globalVar in cgPkgCtx.GetCHIRPackage().GetGlobalVars()) {
            let targetIndex = PickIndex(serial, packages)
            packages[targetIndex].chirGVs.add(globalVar)
            serial++
        }
    }

    private func SplitCHIRTypes(packages: ArrayList<SubCHIRPackage>): Unit {
        var serial: Int64 = 0
        for (customDef in cgPkgCtx.GetCHIRPackage().GetAllCustomTypeDef()) {
            let targetIndex = PickIndex(serial, packages)
            packages[targetIndex].chirCustomDefs.add(customDef)
            serial++
        }
    }
}
