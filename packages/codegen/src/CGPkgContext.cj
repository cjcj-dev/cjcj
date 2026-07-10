package cjcj::codegen

import std.collection.*
import cjcj::chir.CHIRContext
import cjcj::chir.CHIRBuilder
import cjcj::chir.ClassType
import cjcj::chir.Function
import cjcj::chir.NoHeapAllocChecker
import cjcj::chir.NoWriteBarrierRecChecker
import cjcj::chir.Package
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::option.GlobalOptions

public class CachedMangleMap {
    public let importedInlineDecls: HashSet<String> = HashSet<String>()
    public let newExternalDecls: HashSet<String> = HashSet<String>()
    public let incrRemovedDecls: HashSet<String> = HashSet<String>()

    public init() {}

    public func Clear(): Unit {
        importedInlineDecls.clear()
        newExternalDecls.clear()
        incrRemovedDecls.clear()
    }
}

public class CHIRData {
    private let chirContext: CHIRContext
    private var currentPackage: Package
    private let implicitFuncs: HashMap<String, Function> = HashMap<String, Function>()

    public init(chirContext: CHIRContext, currentPackage: Package) {
        this.chirContext = chirContext
        this.currentPackage = currentPackage
    }

    public func GetCHIRContext(): CHIRContext {
        return chirContext
    }

    public func GetCurrentCHIRPackage(): Package {
        return currentPackage
    }

    public func SetCurrentCHIRPackage(pkg: Package): Unit {
        currentPackage = pkg
    }

    public func GetImplicitFuncs(): HashMap<String, Function> {
        return implicitFuncs
    }

    public func AddImplicitFunc(mangledName: String, fn: Function): Unit {
        implicitFuncs[mangledName] = fn
    }
}

public class CGPkgContext {
    private let chirData: CHIRData
    private let options: GlobalOptions
    private let chirBuilder: CHIRBuilder
    private let noHeapAllocChecker: NoHeapAllocChecker
    private let noWriteBarrierRecChecker: NoWriteBarrierRecChecker
    private let enableIncrement: Bool
    private let correctedCachedMangleMap: CachedMangleMap = CachedMangleMap()
    private let cgMods: ArrayList<CGModule> = ArrayList<CGModule>()
    private let subTypeMap: HashMap<Int64, HashMap<Int64, Type>> = HashMap<Int64, HashMap<Int64, Type>>()
    private let quickCHIRValues: HashMap<String, Value> = HashMap<String, Value>()
    private let localizedSymbols: HashSet<String> = HashSet<String>()

    public init(chirData: CHIRData, options: GlobalOptions, enableIncrement: Bool,
        noHeapAllocChecker: NoHeapAllocChecker, noWriteBarrierRecChecker: NoWriteBarrierRecChecker,
        cachedMangleMap: CachedMangleMap) {
        this.chirData = chirData
        this.options = options
        chirBuilder = CHIRBuilder(chirData.GetCHIRContext())
        this.noHeapAllocChecker = noHeapAllocChecker
        this.noWriteBarrierRecChecker = noWriteBarrierRecChecker
        this.enableIncrement = enableIncrement
        for (name in cachedMangleMap.importedInlineDecls) { correctedCachedMangleMap.importedInlineDecls.add(name) }
        for (name in cachedMangleMap.newExternalDecls) { correctedCachedMangleMap.newExternalDecls.add(name) }
        for (name in cachedMangleMap.incrRemovedDecls) {
            if (FindCHIRGlobalValue(name).isNone()) {
                correctedCachedMangleMap.incrRemovedDecls.add(name)
            }
        }
        CollectSubTypeMap()
    }

    public func Clear(): Unit {
        for (cgMod in cgMods) {
            cgMod.Clear()
        }
        subTypeMap.clear()
        correctedCachedMangleMap.Clear()
        quickCHIRValues.clear()
        localizedSymbols.clear()
        cgMods.clear()
    }

    public func GetCHIRBuilder(): CHIRBuilder {
        return chirBuilder
    }

    public func GetNoWriteBarrierRecChecker(): NoWriteBarrierRecChecker {
        return noWriteBarrierRecChecker
    }

    public func GetNoHeapAllocChecker(): NoHeapAllocChecker {
        return noHeapAllocChecker
    }

    public func GetCHIRPackage(): Package {
        return chirData.GetCurrentCHIRPackage()
    }

    public func GetCurrentPkgName(): String {
        return GetCHIRPackage().GetName()
    }

    public func GetGlobalOptions(): GlobalOptions {
        return options
    }

    public func GetImplicitUsedFunc(funcMangledName: String): Option<Function> {
        if (implicitFuncsContains(funcMangledName)) {
            return chirData.GetImplicitFuncs()[funcMangledName]
        }
        return None
    }

    public func GetCachedMangleMap(): CachedMangleMap {
        return correctedCachedMangleMap
    }

    public func IsIncrementEnabled(): Bool {
        return enableIncrement
    }

    public func IsCGParallelEnabled(): Bool {
        return cgMods.size > 1
    }

    public func IsLineInfoEnabled(): Bool {
        return options.enableCompileDebug || options.enableCoverage || options.displayLineInfo
    }

    public func AddCGModule(cgMod: CGModule): Unit {
        cgMods.add(cgMod)
    }

    public func GetCGModules(): ArrayList<CGModule> {
        let out = ArrayList<CGModule>()
        for (cgMod in cgMods) { out.add(cgMod) }
        return out
    }

    public func ReleaseLLVMModules(): ArrayList<LLVMModuleHandle> {
        let out = ArrayList<LLVMModuleHandle>()
        for (cgMod in cgMods) {
            if (let Some(moduleHandle) <- cgMod.ReleaseLLVMModule()) {
                out.add(moduleHandle)
            }
            cgMod.GetCGContext().Clear()
        }
        cgMods.clear()
        return out
    }

    public func AddLocalizedSymbol(symName: String): Unit {
        localizedSymbols.add(symName)
    }

    public func GetLocalizedSymbols(): HashSet<String> {
        let out = HashSet<String>()
        for (symbol in localizedSymbols) { out.add(symbol) }
        return out
    }

    public func CollectSubTypeMap(): Unit {
        if (!GetGlobalOptions().CompileExecutable()) {
            return
        }

        for (customTypeDef in GetCHIRPackage().GetAllCustomTypeDef()) {
            for (parentTy in customTypeDef.GetSuperTypesInCurDef()) {
                let customType = customTypeDef.GetType().getOrThrow()
                let subTypes = subTypeMap.get(parentTy.objectId) ?? HashMap<Int64, Type>()
                subTypes[customType.objectId] = customType
                subTypeMap[parentTy.objectId] = subTypes
            }
        }
    }

    public func NeedOuterTypeInfo(classType: ClassType): Bool {
        if (!GetGlobalOptions().CompileExecutable()) {
            return true
        }

        let `type` = (classType.GetClassDef().GetType().getOrThrow() as ClassType).getOrThrow()
        if (!`type`.GetGenericArgs().isEmpty()) {
            return true
        }

        let subTypes = subTypeMap.get(`type`.objectId) ?? return false
        for ((_, subTy) in subTypes) {
            if (!subTy.GetTypeArgs().isEmpty()) {
                return true
            }
            let subClassType = (subTy as ClassType) ?? continue
            if (NeedOuterTypeInfo(subClassType)) {
                return true
            }
        }
        return false
    }

    public func FindCHIRGlobalValue(mangledName: String): Option<Value> {
        PopulateQuickCHIRValues()
        if (quickCHIRValues.contains(mangledName)) {
            return quickCHIRValues[mangledName]
        }
        return None
    }

    private func implicitFuncsContains(name: String): Bool {
        return chirData.GetImplicitFuncs().contains(name)
    }

    private func PopulateQuickCHIRValues(): Unit {
        if (!quickCHIRValues.isEmpty()) {
            return
        }
        for (chirFunc in GetCHIRPackage().GetGlobalFunctions(includePureAbstract: true)) {
            quickCHIRValues[GetCodeGenGlobalName(chirFunc)] = chirFunc
        }
        for (chirGlobal in GetCHIRPackage().GetGlobalVars()) {
            quickCHIRValues[GetCodeGenGlobalName(chirGlobal)] = chirGlobal
        }
    }
}
