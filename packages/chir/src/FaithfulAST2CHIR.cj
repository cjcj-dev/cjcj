package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.SourceManager as BasicSourceManager
import cjcj::option.GlobalOptions
import cjcj::option.OSType
import cjcj::option.OutputMode
import std.collection.*
import std.convert.*
import std.core.Box as CoreBox
import std.sort.*

import cjcj::ast.ASTKind
import cjcj::ast.ASTKindIndex
import cjcj::ast.ASTKindName
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::ast.AccessLevel as AstAccessLevel
import cjcj::ast.ArrayExpr as AstArrayExpr
import cjcj::ast.AttributePack as AstAttributePack
import cjcj::ast.ArrayLit as AstArrayLit
import cjcj::ast.Attribute as AstAttribute
import cjcj::ast.CallExpr as AstCallExpr
import cjcj::ast.ClassDecl as AstClassDecl
import cjcj::ast.ClassLikeDecl as AstClassLikeDecl
import cjcj::ast.ClassLikeTy as AstClassLikeTy
import cjcj::ast.Decl as AstDecl
import cjcj::ast.EnumDecl as AstEnumDecl
import cjcj::ast.EnumTy as AstEnumTy
import cjcj::ast.EnumPattern as AstEnumPattern
import cjcj::ast.ExtendDecl as AstExtendDecl
import cjcj::ast.Expr as AstExpr
import cjcj::ast.File as AstFile
import cjcj::ast.FuncArg as AstFuncArg
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.FuncParam as AstFuncParam
import cjcj::ast.GenericsTy as AstGenericsTy
import cjcj::ast.IsPackageMemberAccess as AstIsPackageMemberAccess
import cjcj::ast.LitConstExpr as AstLitConstExpr
import cjcj::ast.LitConstKind as AstLitConstKind
import cjcj::ast.MemberAccess as AstMemberAccess
import cjcj::ast.Node as AstNode
import cjcj::ast.Package as AstPackage
import cjcj::ast.Pattern as AstPattern
import cjcj::ast.PropDecl as AstPropDecl
import cjcj::ast.RefExpr as AstRefExpr
import cjcj::ast.StructDecl as AstStructDecl
import cjcj::ast.StructTy as AstStructTy
import cjcj::ast.TuplePattern as AstTuplePattern
import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::ast.TypeKindInRange as AstTypeKindInRange
import cjcj::ast.VarDecl as AstVarDecl
import cjcj::ast.VarPattern as AstVarPattern
import cjcj::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cjcj::ast.VisitAction as AstVisitAction
import cjcj::ast.Walker as AstWalker
import cjcj::ast.WildcardPattern as AstWildcardPattern
import cjcj::ast.Position as AstPosition
import cjcj::ast.IsStaticInitializer as AstIsStaticInitializer
import cjcj::ast.IsImpl as AstIsImpl
import cjcj::ast.IsMirror as AstIsMirror
import cjcj::incremental_compilation.{CompilationCache, IncreKind, VirtualWrapperDepMap}
import cjcj::sema.GenericInstantiation.GenericInstantiationManager
import cjcj::utils.{CFFI_FUNC_SUFFIX, CJC_ABORT, CJC_ASSERT, CORE_PACKAGE_NAME, FileUtil, MAIN_INVOKE,
    ProfileRecorder, STATIC_INIT_FUNC, STATIC_INIT_VAR}

foreign {
    func CJSelfhostStrtoldToFloat32(value: CString): Float64
}

private let USER_MAIN_MANGLED_NAME: String = "user.main"

private class ImplicitImportedFunc {
    public let parentKind: ASTKind
    public let identifier: String
    public let parentName: String

    public init(parentKind: ASTKind, identifier: String, parentName!: String = "") {
        this.parentKind = parentKind
        this.identifier = identifier
        this.parentName = parentName
    }
}

private enum ImplicitImportedFuncMgrFuncKind {
    | GENERIC
    | NONE_GENERIC
}

private class ImplicitImportedFuncMgr {
    private static let instance: ImplicitImportedFuncMgr = ImplicitImportedFuncMgr()
    private let implicitImportedGenericFuncs: ArrayList<ImplicitImportedFunc> = ArrayList<ImplicitImportedFunc>()
    private let implicitImportedNonGenericFuncs: ArrayList<ImplicitImportedFunc> = ArrayList<ImplicitImportedFunc>()

    private init() {
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "init", parentName: "SpawnException"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "init", parentName: "Exception"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "init", parentName: "IndexOutOfBoundsException"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "init", parentName: "NegativeArraySizeException"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "init", parentName: "OutOfMemoryError"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "printStackTrace", parentName: "Exception"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "printStackTrace", parentName: "Error"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "getCommandLineArgs"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "createArithmeticExceptionMsg"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "createOverflowExceptionMsg"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "CJ_CORE_ExecAtexitCallbacks"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "handleException"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.INVALID_DECL, "eprintln"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "setRuntimeCJThreadHandle", parentName: "Thread"),
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "execute", parentName: "Future"),
            ImplicitImportedFuncMgrFuncKind.GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "executeClosure", parentName: "Future"),
            ImplicitImportedFuncMgrFuncKind.GENERIC)
        RegImplicitImportedFunc(ImplicitImportedFunc(ASTKind.CLASS_DECL, "get", parentName: "Future"),
            ImplicitImportedFuncMgrFuncKind.GENERIC)
    }

    public static func Instance(): ImplicitImportedFuncMgr { return instance }

    public func RegImplicitImportedFunc(funcInfo: ImplicitImportedFunc,
        funcKind: ImplicitImportedFuncMgrFuncKind): Unit {
        match (funcKind) {
            case ImplicitImportedFuncMgrFuncKind.GENERIC => implicitImportedGenericFuncs.add(funcInfo)
            case ImplicitImportedFuncMgrFuncKind.NONE_GENERIC => implicitImportedNonGenericFuncs.add(funcInfo)
            case _ => CJC_ASSERT(false)
        }
    }

    public func GetImplicitImportedFuncs(funcKind: ImplicitImportedFuncMgrFuncKind): ArrayList<ImplicitImportedFunc> {
        let funcs = match (funcKind) {
            case ImplicitImportedFuncMgrFuncKind.GENERIC => implicitImportedGenericFuncs
            case ImplicitImportedFuncMgrFuncKind.NONE_GENERIC => implicitImportedNonGenericFuncs
            case _ =>
                CJC_ASSERT(false)
                ArrayList<ImplicitImportedFunc>()
        }
        sort(funcs, by: { left: ImplicitImportedFunc, right: ImplicitImportedFunc =>
            let leftName = left.parentName + left.identifier
            let rightName = right.parentName + right.identifier
            if (leftName < rightName) {
                Ordering.LT
            } else if (leftName > rightName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        return funcs
    }
}

private class FaithfulInitFileVars {
    public let file: AstFile
    public let vars: ArrayList<AstDecl> = ArrayList<AstDecl>()

    public init(file: AstFile) {
        this.file = file
    }
}

public class ElementList {
    public let stableOrderValue: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let randomOrderValue: FaithfulInitDeclSet = FaithfulInitDeclSet()

    public init() {}

    public func AddElement(element: AstDecl): Unit {
        if (!randomOrderValue.Add(element)) {
            return
        }
        stableOrderValue.add(element)
    }

    public func AddElements(elements: ArrayList<AstDecl>): Unit {
        for (element in elements) {
            AddElement(element)
        }
    }

    public func HasElement(element: AstDecl): Bool {
        return randomOrderValue.Contains(element)
    }
}

private class StaticInitInfo {
    public let staticInitFunc: AstFuncDecl
    public let staticInitVar: Option<AstDecl>
    public let vars: ArrayList<AstDecl>

    public init(staticInitFunc: AstFuncDecl, staticInitVar: Option<AstDecl>, vars: ArrayList<AstDecl>) {
        this.staticInitFunc = staticInitFunc
        this.staticInitVar = staticInitVar
        this.vars = vars
    }
}

private class StaticInitInfoEntry {
    public let decl: AstDecl
    public let info: StaticInitInfo

    public init(decl: AstDecl, info: StaticInitInfo) {
        this.decl = decl
        this.info = info
    }
}

private class StaticInitInfoMap {
    private let buckets: HashMap<Int64, ArrayList<StaticInitInfoEntry>> =
        HashMap<Int64, ArrayList<StaticInitInfoEntry>>()

    public init() {}

    public func Set(decl: AstDecl, info: StaticInitInfo): Unit {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            var idx: Int64 = 0
            while (idx < bucket.size) {
                if (FaithfulInitSameDecl(bucket[idx].decl, decl)) {
                    bucket[idx] = StaticInitInfoEntry(decl, info)
                    return
                }
                idx++
            }
            bucket.add(StaticInitInfoEntry(decl, info))
            return
        }
        let bucket = ArrayList<StaticInitInfoEntry>()
        bucket.add(StaticInitInfoEntry(decl, info))
        buckets[key] = bucket
    }

    public func Get(decl: AstDecl): Option<StaticInitInfo> {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return entry.info
                }
            }
        }
        return None
    }
}

private class FaithfulInitDepsEntry {
    public let decl: AstDecl
    public let deps: ArrayList<AstDecl>

    public init(decl: AstDecl, deps: ArrayList<AstDecl>) {
        this.decl = decl
        this.deps = deps
    }
}

private class FaithfulInitDeclSet {
    private let buckets: HashMap<Int64, ArrayList<AstDecl>> = HashMap<Int64, ArrayList<AstDecl>>()

    public init() {}

    public func Add(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (item in bucket) {
                if (FaithfulInitSameDecl(item, decl)) {
                    return false
                }
            }
            bucket.add(decl)
            return true
        }
        let bucket = ArrayList<AstDecl>()
        bucket.add(decl)
        buckets[key] = bucket
        return true
    }

    public func Contains(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (item in bucket) {
                if (FaithfulInitSameDecl(item, decl)) {
                    return true
                }
            }
        }
        return false
    }

    public func Remove(decl: AstDecl): Bool {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            var idx: Int64 = 0
            while (idx < bucket.size) {
                if (FaithfulInitSameDecl(bucket[idx], decl)) {
                    bucket.remove(at: idx)
                    return true
                }
                idx++
            }
        }
        return false
    }
}

private class FaithfulInitDepsMap {
    private let buckets: HashMap<Int64, ArrayList<FaithfulInitDepsEntry>> =
        HashMap<Int64, ArrayList<FaithfulInitDepsEntry>>()

    public init() {}

    public func Add(decl: AstDecl, deps: ArrayList<AstDecl>): Unit {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            bucket.add(FaithfulInitDepsEntry(decl, deps))
            return
        }
        let bucket = ArrayList<FaithfulInitDepsEntry>()
        bucket.add(FaithfulInitDepsEntry(decl, deps))
        buckets[key] = bucket
    }

    public func Get(decl: AstDecl): Option<ArrayList<AstDecl>> {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return entry.deps
                }
            }
        }
        return None
    }
}

private class DeclDepMap {
    public let stableOrderValue: ArrayList<FaithfulInitDepsEntry> = ArrayList<FaithfulInitDepsEntry>()
    private let randomOrderValue: FaithfulInitDepsMap = FaithfulInitDepsMap()

    public init() {}

    public func AddDeps(root: AstDecl, deps: ArrayList<AstDecl>): Unit {
        if (randomOrderValue.Get(root).isSome()) {
            return
        }
        let copiedDeps = ArrayList<AstDecl>()
        for (dep in deps) {
            copiedDeps.add(dep)
        }
        randomOrderValue.Add(root, copiedDeps)
        stableOrderValue.add(FaithfulInitDepsEntry(root, copiedDeps))
    }

    public func AddDep(root: AstDecl, dep: AstDecl): Unit {
        let deps = if (let Some(existing) <- randomOrderValue.Get(root)) {
            existing
        } else {
            let createdDeps = ArrayList<AstDecl>()
            randomOrderValue.Add(root, createdDeps)
            stableOrderValue.add(FaithfulInitDepsEntry(root, createdDeps))
            createdDeps
        }
        for (existing in deps) {
            if (FaithfulInitSameDecl(existing, dep)) {
                return
            }
        }
        deps.add(dep)
    }

    public func GetDep(root: AstDecl): ArrayList<AstDecl> {
        return randomOrderValue.Get(root) ?? ArrayList<AstDecl>()
    }

    public func Contains(root: AstDecl): Bool {
        return randomOrderValue.Get(root).isSome()
    }
}

private class FileDepMapEntry {
    public let file: AstFile
    public let deps: ArrayList<AstFile>

    public init(file: AstFile, deps: ArrayList<AstFile>) {
        this.file = file
        this.deps = deps
    }
}

private class FileDepMap {
    public let stableOrderValue: ArrayList<FileDepMapEntry> = ArrayList<FileDepMapEntry>()
    private let randomOrderValue: HashMap<Int64, ArrayList<AstFile>> = HashMap<Int64, ArrayList<AstFile>>()

    public init() {}

    public func InitDeps(root: AstFile): Unit {
        if (Contains(root)) {
            return
        }
        let deps = ArrayList<AstFile>()
        randomOrderValue[root.objectId] = deps
        stableOrderValue.add(FileDepMapEntry(root, deps))
    }

    public func AddDep(root: AstFile, dep: AstFile): Unit {
        let deps = if (let Some(existing) <- randomOrderValue.get(root.objectId)) {
            existing
        } else {
            let createdDeps = ArrayList<AstFile>()
            randomOrderValue[root.objectId] = createdDeps
            createdDeps
        }
        for (existing in deps) {
            if (existing == dep) {
                return
            }
        }
        deps.add(dep)
        for (entry in stableOrderValue) {
            if (entry.file == root) {
                entry.deps.add(dep)
                return
            }
        }
    }

    public func GetDep(root: AstFile): ArrayList<AstFile> {
        return randomOrderValue.get(root.objectId) ?? ArrayList<AstFile>()
    }

    public func Contains(root: AstFile): Bool {
        return randomOrderValue.contains(root.objectId)
    }
}

private class DepsUnit<T> where T <: AstNode {
    public let element: T
    public let depsUnits: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    public let userUnits: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    public let circularDepElements: ArrayList<T> = ArrayList<T>()
    public var disc: Int64 = -1
    public var low: Int64 = -1
    public var stackMember: Bool = false

    public init(element: T) {
        this.element = element
    }

    public func AddDeps(unit: DepsUnit<T>): Unit {
        for (existing in depsUnits) {
            if (existing.element == unit.element) {
                return
            }
        }
        depsUnits.add(unit)
    }

    public func AddUsers(unit: DepsUnit<T>): Unit {
        for (existing in userUnits) {
            if (existing.element == unit.element) {
                return
            }
        }
        userUnits.add(unit)
    }
}

private abstract class TarjanSort<T> where T <: AstNode {
    protected let newSccUnits: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    protected let diagUnits: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    protected let units: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    private let visitedUnits: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()
    private let node2SccUnitMap: ArrayList<DepsUnit<T>> = ArrayList<DepsUnit<T>>()

    public init() {}

    public func InitDependency(rawElements: ArrayList<T>, dependencyMap: FileDepMap): Unit {
        for (element in rawElements) {
            let unit = DepsUnit<T>(element)
            units.add(unit)
        }
        for (element in rawElements) {
            let varUnit = GetUnit(element)
            for (dep in dependencyMap.GetDep((element as AstFile).getOrThrow())) {
                let tempUnit = GetUnit((dep as T).getOrThrow())
                varUnit.depsUnits.add(tempUnit)
                tempUnit.userUnits.add(varUnit)
            }
        }
    }

    public func InitDependency(rawElements: ArrayList<AstDecl>, dependencyMap: DeclDepMap): Unit {
        for (element in rawElements) {
            let unit = DepsUnit<T>((element as T).getOrThrow())
            units.add(unit)
        }
        for (element in rawElements) {
            let varUnit = GetUnit((element as T).getOrThrow())
            for (dep in dependencyMap.GetDep(element)) {
                let tempUnit = GetUnit((dep as T).getOrThrow())
                varUnit.depsUnits.add(tempUnit)
                tempUnit.userUnits.add(varUnit)
            }
        }
    }

    public func DoTarjanSort(): Unit {
        let stack = ArrayList<DepsUnit<T>>()
        var index: Int64 = 1
        for (unit in units) {
            if (!ContainsUnit(visitedUnits, unit)) {
                TarjanSortImpl(unit, index, stack)
            }
        }
    }

    public func TarjanSortImpl(unit: DepsUnit<T>, index: Int64, stack: ArrayList<DepsUnit<T>>): Int64 {
        var nextIndex = index
        unit.disc = nextIndex
        unit.low = nextIndex
        nextIndex++
        stack.add(unit)
        unit.stackMember = true
        visitedUnits.add(unit)

        for (dep in unit.depsUnits) {
            if (dep.disc == -1) {
                nextIndex = TarjanSortImpl(dep, nextIndex, stack)
                unit.low = MinInt64(unit.low, dep.low)
            } else {
                if (dep.stackMember) {
                    unit.low = MinInt64(unit.low, dep.disc)
                }
            }
        }

        if (unit.disc == unit.low) {
            diagUnits.add(unit)
            let newSccUnit = DepsUnit<T>(unit.element)
            SetSccUnit(unit.element, newSccUnit)
            newSccUnit.circularDepElements.add(unit.element)
            while (stack[stack.size - 1].element != unit.element) {
                let topUnit = stack[stack.size - 1]
                topUnit.stackMember = false
                diagUnits.add(topUnit)
                SetSccUnit(topUnit.element, newSccUnit)
                newSccUnit.circularDepElements.add(topUnit.element)
                stack.remove(at: stack.size - 1)
            }
            let topUnit = stack[stack.size - 1]
            topUnit.stackMember = false
            stack.remove(at: stack.size - 1)
            DetectCircularDep()
            newSccUnits.add(newSccUnit)
        }
        diagUnits.clear()
        return nextIndex
    }

    public func UpdateSccUnit(dependencyMap: FileDepMap): Unit {
        for (unit in newSccUnits) {
            UpdateSccUnitDeps(unit, dependencyMap)
        }
    }

    public func UpdateSccUnit(dependencyMap: DeclDepMap): Unit {
        for (unit in newSccUnits) {
            UpdateSccUnitDeps(unit, dependencyMap)
        }
    }

    public func UpdateSccUnitDeps(unit: DepsUnit<T>, dependencyMap: FileDepMap): Unit {
        let cirElements = unit.circularDepElements
        for (element in cirElements) {
            for (dep in dependencyMap.GetDep((element as AstFile).getOrThrow())) {
                let typedDep = (dep as T).getOrThrow()
                if (!ContainsElement(cirElements, typedDep)) {
                    let depScc = GetSccUnit(typedDep)
                    unit.AddDeps(depScc)
                    depScc.AddUsers(unit)
                }
            }
        }
    }

    public func UpdateSccUnitDeps(unit: DepsUnit<T>, dependencyMap: DeclDepMap): Unit {
        let cirElements = unit.circularDepElements
        for (element in cirElements) {
            for (dep in dependencyMap.GetDep((element as AstDecl).getOrThrow())) {
                let typedDep = (dep as T).getOrThrow()
                if (!ContainsElement(cirElements, typedDep)) {
                    let depScc = GetSccUnit(typedDep)
                    unit.AddDeps(depScc)
                    depScc.AddUsers(unit)
                }
            }
        }
    }

    public func GetOrderElement(): ArrayList<T> {
        let sortedNodes = ArrayList<T>()
        let freeNodes = ArrayList<DepsUnit<T>>()
        for (unit in newSccUnits) {
            if (unit.depsUnits.isEmpty()) {
                freeNodes.add(unit)
            }
        }
        while (!freeNodes.isEmpty()) {
            let curFreeUnit = freeNodes[freeNodes.size - 1]
            freeNodes.remove(at: freeNodes.size - 1)
            for (element in curFreeUnit.circularDepElements) {
                sortedNodes.add(element)
            }
            for (unit in curFreeUnit.userUnits) {
                var idx: Int64 = 0
                var erased = false
                while (idx < unit.depsUnits.size) {
                    if (unit.depsUnits[idx].element == curFreeUnit.element) {
                        unit.depsUnits.remove(at: idx)
                        erased = true
                        break
                    }
                    idx++
                }
                if (!erased) {
                    continue
                }
                if (unit.depsUnits.isEmpty()) {
                    freeNodes.add(unit)
                }
            }
        }
        visitedUnits.clear()
        node2SccUnitMap.clear()
        newSccUnits.clear()
        return sortedNodes
    }

    public func DetectCircularDep(): Unit
    public func GetEleStr(element: T): String

    private func GetUnit(element: T): DepsUnit<T> {
        for (unit in units) {
            if (unit.element == element) {
                return unit
            }
        }
        throw IllegalStateException("TarjanSort missing unit: " + GetEleStr(element))
    }

    private func SetSccUnit(element: T, unit: DepsUnit<T>): Unit {
        var idx: Int64 = 0
        while (idx < node2SccUnitMap.size) {
            if (node2SccUnitMap[idx].element == element) {
                node2SccUnitMap[idx] = unit
                return
            }
            idx++
        }
        node2SccUnitMap.add(unit)
    }

    private func GetSccUnit(element: T): DepsUnit<T> {
        for (unit in node2SccUnitMap) {
            for (item in unit.circularDepElements) {
                if (item == element) {
                    return unit
                }
            }
        }
        throw IllegalStateException("TarjanSort missing SCC unit: " + GetEleStr(element))
    }

    private func ContainsUnit(values: ArrayList<DepsUnit<T>>, unit: DepsUnit<T>): Bool {
        for (value in values) {
            if (value.element == unit.element) {
                return true
            }
        }
        return false
    }

    private func ContainsElement(values: ArrayList<T>, element: T): Bool {
        for (value in values) {
            if (value == element) {
                return true
            }
        }
        return false
    }
}

private class FileCirDepsChecker <: TarjanSort<AstFile> {
    public var hasCircularDependency: Bool = false
    private let diagLog: ArrayList<String>

    public init(diagLog: ArrayList<String>) {
        super()
        this.diagLog = diagLog
    }

    public func InitFileDep(depMap: FileDepMap): Unit {
        let files = ArrayList<AstFile>()
        for (dep in depMap.stableOrderValue) {
            files.add(dep.file)
        }
        InitDependency(files, depMap)
    }

    public override func DetectCircularDep(): Unit {
        if (diagUnits.size <= 1) {
            return
        }
        hasCircularDependency = true
    }

    public override func GetEleStr(node: AstFile): String {
        return node.fileName
    }
}

private class VarCirDepsChecker <: TarjanSort<AstDecl> {
    public var hasCircularDependency: Bool = false

    public init() {
        super()
    }

    public override func DetectCircularDep(): Unit {
        if (diagUnits.size <= 1) {
            return
        }
        var hasVar = false
        for (unit in diagUnits) {
            if (IsVar(unit.element)) {
                hasVar = true
                break
            }
        }
        if (!hasVar) {
            return
        }
        hasCircularDependency = true
    }

    public override func GetEleStr(decl: AstDecl): String {
        return decl.identifier.Val()
    }

    private func IsVar(decl: AstDecl): Bool {
        return decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL
    }
}

private func MinInt64(left: Int64, right: Int64): Int64 {
    return if (left < right) { left } else { right }
}

private class FaithfulInitDeclOwnerEntry {
    public let decl: AstDecl
    public let owner: AstDecl

    public init(decl: AstDecl, owner: AstDecl) {
        this.decl = decl
        this.owner = owner
    }
}

private class FaithfulInitDeclOwnerMap {
    private let buckets: HashMap<Int64, ArrayList<FaithfulInitDeclOwnerEntry>> =
        HashMap<Int64, ArrayList<FaithfulInitDeclOwnerEntry>>()

    public init() {}

    public func Add(decl: AstDecl, owner: AstDecl): Unit {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return
                }
            }
            bucket.add(FaithfulInitDeclOwnerEntry(decl, owner))
            return
        }
        let bucket = ArrayList<FaithfulInitDeclOwnerEntry>()
        bucket.add(FaithfulInitDeclOwnerEntry(decl, owner))
        buckets[key] = bucket
    }

    public func Get(decl: AstDecl): Option<AstDecl> {
        let key = FaithfulInitDeclHash(decl)
        if (let Some(bucket) <- buckets.get(key)) {
            for (entry in bucket) {
                if (FaithfulInitSameDecl(entry.decl, decl)) {
                    return entry.owner
                }
            }
        }
        return None
    }
}

private func FaithfulInitDeclHash(decl: AstDecl): Int64 {
    if (let Some(defaultKey) <- FaithfulInitDefaultParamDeclIdentity(decl)) {
        return defaultKey.hashCode()
    }
    return decl.hashCode()
}

private func FaithfulInitSameDecl(left: AstDecl, right: AstDecl): Bool {
    if (let Some(leftKey) <- FaithfulInitDefaultParamDeclIdentity(left)) {
        if (let Some(rightKey) <- FaithfulInitDefaultParamDeclIdentity(right)) {
            return leftKey == rightKey
        }
        return false
    }
    if (FaithfulInitDefaultParamDeclIdentity(right).isSome()) {
        return false
    }
    return left == right
}

private func FaithfulInitDefaultParamDeclIdentity(decl: AstDecl): Option<String> {
    if (!decl.TestAttr(AstAttribute.HAS_INITIAL)) {
        return None
    }
    if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
        if (let Some(owner) <- funcDecl.ownerFunc) {
            return Some(ASTKindIndex(owner.astKind).toString() + ":" + owner.fullPackageName + ":" +
                owner.identifier.Val() + ":" + owner.begin.hashCode().toString() + ":" +
                owner.end.hashCode().toString() + ":default-param:" + decl.identifier.Val())
        }
    }
    return None
}

private let FAITHFUL_MANGLE_CANGJIE_PREFIX: String = "_C"
private let FAITHFUL_MANGLE_SUFFIX: String = "E"
private let FAITHFUL_MANGLE_NESTED_PREFIX: String = "N"
private let FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX: String = "GP"
private let FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX: String = "GV"
// Mirrors include/cangjie/Mangle/MangleUtils.h:22-36 for CHIR-local faithful init names.
private let FAITHFUL_MANGLE_GLOBAL_FILE_INIT_PREFIX: String = "GF"
private let FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX: String = "PI"
private let FAITHFUL_MANGLE_FILE_ID_PREFIX: String = "U"
private let FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX: String = "H"
private let FAITHFUL_MANGLE_VOID_TY_SUFFIX: String = "v"
private let FAITHFUL_MANGLE_TYPE_STRUCT_PREFIX: String = "R"
private let FAITHFUL_MANGLE_TYPE_CLASS_PREFIX: String = "C"
private let FAITHFUL_MANGLE_TYPE_ENUM_PREFIX: String = "N"
private let FAITHFUL_MANGLE_TYPE_ARRAY_PREFIX: String = "A"
private let FAITHFUL_MANGLE_POINTER_PREFIX: String = "P"
private let FAITHFUL_MANGLE_VARRAY_PREFIX: String = "V"
private let FAITHFUL_MANGLE_TUPLE_PREFIX: String = "T"
private let FAITHFUL_MANGLE_GENERIC_TYPE_PREFIX: String = "G"
private let FAITHFUL_MANGLE_GENERAL_FUNC_PREFIX: String = "F0"
private let FAITHFUL_MANGLE_CFUNC_PREFIX: String = "FC"
private let FAITHFUL_MANGLE_DOT_PREFIX: String = "."
private let FAITHFUL_MANGLE_AT_PREFIX: String = "@"
private let FAITHFUL_MANGLE_WILDCARD_PREFIX: String = "_"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION: String = "ii"
private let FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION: String = "il"
private let FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION: String = "fi"
private let FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION: String = "fl"
private let FAITHFUL_GV_INIT_WILDCARD_PATTERN: String = "wildcard_pattern_"

private func FaithfulStartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

private func FaithfulEndsWith(value: String, suffix: String): Bool {
    return value.size >= suffix.size && value[value.size - suffix.size..] == suffix
}

private func FaithfulIsDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

private func FaithfulIsAlpha(ch: Byte): Bool {
    return (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z')
}

// Mirrors BaseMangler::HashToBase62/IsHashable/FileNameWithoutExtension
// in src/Mangle/BaseMangler.cpp:1210-1241.
private func FaithfulFnv1aHash(str: String): UInt64 {
    var hash: UInt64 = 2166136261u64
    for (ch in str.toArray()) {
        hash = ((hash ^ UInt64(ch)) * 16777619u64) & 0xffffffffu64
    }
    return hash
}

private func FaithfulToBase62(value: UInt64): String {
    let base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    var current = value
    var result = ""
    while (current > 0u64) {
        let idx = Int64(current % UInt64(base62Chars.size))
        result += base62Chars[idx..idx + 1]
        current /= UInt64(base62Chars.size)
    }
    let length: Int64 = 13
    while (result.size < length) {
        result += "0"
    }
    var reversed = ""
    var idx = result.size - 1
    while (idx >= 0) {
        reversed += result[idx..idx + 1]
        idx--
    }
    return if (reversed.size > length) { reversed[0..length] } else { reversed }
}

private func FaithfulHashToBase62(input: String): String {
    return FaithfulToBase62(FaithfulFnv1aHash(input))
}

private func FaithfulFileNameWithoutExtension(fileName: String): String {
    if (fileName.size > 3 && FaithfulEndsWith(fileName, ".cj")) {
        return fileName[0..fileName.size - 3]
    }
    return fileName
}

private func FaithfulIsHashableFileName(fileName: String): Bool {
    let nameWithoutExt = FaithfulFileNameWithoutExtension(fileName)
    if (nameWithoutExt.size > 12) {
        return true
    }
    for (ch in nameWithoutExt.toArray()) {
        if (!(FaithfulIsAlpha(ch) || FaithfulIsDigit(ch) || ch == b'.' || ch == b'_' || ch == b'-')) {
            return true
        }
    }
    return false
}

private func BuildAttr(attrs: AstAttributePack): AttributeInfo {
    let attrInfo = AttributeInfo()
    if (attrs.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) { attrInfo.Enable(Attribute.GENERIC_INSTANTIATED) }
    if (attrs.TestAttr(AstAttribute.STATIC)) { attrInfo.Enable(Attribute.STATIC) }
    if (attrs.TestAttr(AstAttribute.FOREIGN)) { attrInfo.Enable(Attribute.FOREIGN) }
    if (attrs.TestAttr(AstAttribute.MUT)) { attrInfo.Enable(Attribute.MUT) }
    if (attrs.TestAttr(AstAttribute.INTERNAL)) { attrInfo.Enable(Attribute.INTERNAL) }
    if (attrs.TestAttr(AstAttribute.PUBLIC)) { attrInfo.Enable(Attribute.PUBLIC) }
    if (attrs.TestAttr(AstAttribute.PRIVATE)) { attrInfo.Enable(Attribute.PRIVATE) }
    if (attrs.TestAttr(AstAttribute.PROTECTED)) { attrInfo.Enable(Attribute.PROTECTED) }
    if (attrs.TestAttr(AstAttribute.ABSTRACT)) { attrInfo.Enable(Attribute.ABSTRACT) }
    if (attrs.TestAttr(AstAttribute.OPEN)) { attrInfo.Enable(Attribute.VIRTUAL) }
    if (attrs.TestAttr(AstAttribute.OVERRIDE)) { attrInfo.Enable(Attribute.OVERRIDE) }
    if (attrs.TestAttr(AstAttribute.REDEF)) { attrInfo.Enable(Attribute.REDEF) }
    if (attrs.TestAttr(AstAttribute.SEALED)) { attrInfo.Enable(Attribute.SEALED) }
    if (attrs.TestAttr(AstAttribute.OPERATOR)) { attrInfo.Enable(Attribute.OPERATOR) }
    if (attrs.TestAttr(AstAttribute.COMPILER_ADD)) { attrInfo.Enable(Attribute.COMPILER_ADD) }
    if (attrs.TestAttr(AstAttribute.IMPLICIT_ADD)) { attrInfo.Enable(Attribute.NO_DEBUG_INFO) }
    if (attrs.TestAttr(AstAttribute.GENERIC)) { attrInfo.Enable(Attribute.GENERIC) }
    if (attrs.TestAttr(AstAttribute.IMPORTED)) { attrInfo.Enable(Attribute.IMPORTED) }
    if (attrs.TestAttr(AstAttribute.NO_REFLECT_INFO)) { attrInfo.Enable(Attribute.NO_REFLECT_INFO) }
    if (attrs.TestAttr(AstAttribute.COMMON)) { attrInfo.Enable(Attribute.COMMON) }
    if (attrs.TestAttr(AstAttribute.SPECIFIC)) { attrInfo.Enable(Attribute.SPECIFIC) }
    if (attrs.TestAttr(AstAttribute.JAVA_MIRROR)) { attrInfo.Enable(Attribute.JAVA_MIRROR) }
    if (attrs.TestAttr(AstAttribute.OBJ_C_MIRROR)) { attrInfo.Enable(Attribute.OBJ_C_MIRROR) }
    if (attrs.TestAttr(AstAttribute.HAS_INITED_FIELD)) { attrInfo.Enable(Attribute.HAS_INITED_FIELD) }
    if (attrs.TestAttr(AstAttribute.UNSAFE)) { attrInfo.Enable(Attribute.UNSAFE) }
    return attrInfo
}

func BuildVarDeclAttr(decl: AstVarDecl): AttributeInfo {
    let attrInfo = BuildAttr(decl.GetAttrs())
    if (!decl.isVar) {
        attrInfo.Enable(Attribute.READONLY)
    }
    if (decl.IsConst()) {
        attrInfo.Enable(Attribute.CONST)
    }
    return attrInfo
}

private func GetFuncLinkage(opts: GlobalOptions, funcDecl: AstFuncDecl): BasicLinkage {
    if (funcDecl.TestAttr(AstAttribute.IMPORTED)) {
        return funcDecl.linkage
    }
    if (funcDecl.linkage == BasicLinkage.EXTERNAL || funcDecl.linkage == BasicLinkage.WEAK_ODR) {
        if (funcDecl.TestAttr(AstAttribute.IMPORTED)) {
            return BasicLinkage.INTERNAL
        } else if (opts.target.IsMinGW()) {
            return BasicLinkage.EXTERNAL
        }
    }
    return funcDecl.linkage
}

private func IsStaticInit(funcDecl: AstFuncDecl): Bool {
    return funcDecl.TestAttr(AstAttribute.STATIC) && funcDecl.TestAttr(AstAttribute.CONSTRUCTOR) &&
        funcDecl.identifier.Val() == STATIC_INIT_FUNC
}

private func SetGlobalVarLinkageType(value: GlobalValue, decl: AstVarDecl, isLiftedLocalConst: Bool, isWin: Bool): Unit {
    if (isLiftedLocalConst) {
        value.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        return
    }
    if (decl.isConst && !isWin) {
        value.SetLinkTypeInfo(BasicLinkage.WEAK_ODR)
        return
    }
    value.SetLinkTypeInfo(decl.linkage)
}

private func BuildPackageAccessLevel(level: AstAccessLevel): AccessLevel {
    return match (level) {
        case AstAccessLevel.INTERNAL => AccessLevel.INTERNAL
        case AstAccessLevel.PROTECTED => AccessLevel.PROTECTED
        case AstAccessLevel.PUBLIC => AccessLevel.PUBLIC
        case AstAccessLevel.PRIVATE => throw IllegalArgumentException("invalid package access level")
    }
}

func GetDeclLoc(context: CHIRContext, decl: AstDecl): DebugLocation {
    let begin = decl.identifier.Begin()
    return TranslateLocationWithoutScope(context, begin, decl.identifier.End())
}

func TranslateLocationWithoutScope(context: CHIRContext, beginPos: AstPosition,
    endPos: AstPosition): DebugLocation {
    let fileId = UInt32(beginPos.fileID)
    return DebugLocation(context.GetSourceFileName(fileId), fileId,
        Position(UInt32(beginPos.line), UInt32(beginPos.column)),
        Position(UInt32(endPos.line), UInt32(endPos.column)), scopeInfo: ArrayList<Int64>([0]))
}

public class FaithfulAST2CHIRBuilder {
    private var builder: Option<CHIRBuilder> = None
    private var chirType: Option<CHIRType> = None
    private var sourceManager: Option<BasicSourceManager> = None
    private var gim: Option<GenericInstantiationManager> = None
    private var overrideSrcFuncResolver: Option<(AstFuncDecl) -> Option<AstFuncDecl>> = None

    public init() {}

    public func SetCHIRBuilder(value: CHIRBuilder): FaithfulAST2CHIRBuilder {
        builder = value
        return this
    }

    public func SetCHIRType(value: CHIRType): FaithfulAST2CHIRBuilder {
        chirType = value
        return this
    }

    public func SetSourceManager(value: BasicSourceManager): FaithfulAST2CHIRBuilder {
        sourceManager = value
        return this
    }

    public func SetGenericInstantiationManager(
        value: Option<GenericInstantiationManager>): FaithfulAST2CHIRBuilder {
        gim = value
        return this
    }

    public func SetOverrideSrcFuncResolver(
        resolver: (AstFuncDecl) -> Option<AstFuncDecl>): FaithfulAST2CHIRBuilder {
        overrideSrcFuncResolver = Some(resolver)
        return this
    }

    public func Build(): FaithfulAST2CHIR {
        return FaithfulAST2CHIR(
            builder ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRBuilder"),
            chirType ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRType"),
            sourceManager ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires SourceManager"),
            gim: gim,
            overrideSrcFuncResolver: overrideSrcFuncResolver)
    }
}

public class FaithfulAST2CHIR {
    private let builder: CHIRBuilder
    private let chirType: CHIRType
    private let sourceManager: BasicSourceManager
    private let importedPackages: ArrayList<AstPackage>
    private let directImportedPackages: ArrayList<AstPackage>
    private let gim: Option<GenericInstantiationManager>
    private let overrideSrcFuncResolver: Option<(AstFuncDecl) -> Option<AstFuncDecl>>
    private let opts: GlobalOptions
    private let kind: IncreKind
    private let chirWFC: Bool
    private let chirOptOverO2: Bool
    private let diag: Option<BasicDiagnosticEngine>
    private var outputPackage: Option<Package> = None
    private var failure: Bool = false
    private var failureReason: String = ""

    private let globalCache: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
    private let deserializedDefs: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    private let deserializedVals: HashMap<String, Value> = HashMap<String, Value>()
    private let noNeedToTranslateDecls: HashSet<AstDecl> = HashSet<AstDecl>()
    private let implicitDecls: HashSet<AstDecl> = HashSet<AstDecl>()
    private let implicitFuncs: HashMap<String, Function> = HashMap<String, Function>()
    private let allTopLevelNodes: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let allTopLevelNodeSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let pkgFiles: ArrayList<AstFile> = ArrayList<AstFile>()

    private let importedGlobalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGlobalAndStaticVarSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedGlobalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGlobalAndMemberFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let importedGenericInstantiatedNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let importedGenericInstantiatedNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()

    private let globalAndStaticVars: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let globalAndStaticVarSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let globalAndMemberFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let globalAndMemberFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let varsInitedByStaticInitFunc: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let staticInitFuncInfoMap: StaticInitInfoMap = StaticInitInfoMap()
    private let nominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let nominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let genericNominalDecls: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let genericNominalDeclSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private let foreignFuncs: ArrayList<AstDecl> = ArrayList<AstDecl>()
    private let foreignFuncSet: FaithfulInitDeclSet = FaithfulInitDeclSet()
    private var localConstVars: ElementList = ElementList()
    private let localConstFuncs: ElementList = ElementList()
    private var funcsAndVarsDepMap: DeclDepMap = DeclDepMap()
    private var localConstVarsDepMap: DeclDepMap = DeclDepMap()
    private let packageInitializerBlocks: HashMap<Int64, Block> = HashMap<Int64, Block>()
    private let initFuncsForConstVar: ArrayList<Function> = ArrayList<Function>()
    private let initFuncsForAnnoFactory: ArrayList<Function> = ArrayList<Function>()
    private let annoFactoryFuncs: ArrayList<(AstDecl, Function)> = ArrayList<(AstDecl, Function)>()
    private let maybeUnreachable: HashMap<Block, Terminator> = HashMap<Block, Terminator>()
    private let isComputingAnnos: Bool

    public init(builder: CHIRBuilder, chirType: CHIRType, sourceManager: BasicSourceManager,
        importedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        directImportedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        gim!: Option<GenericInstantiationManager> = None,
        overrideSrcFuncResolver!: Option<(AstFuncDecl) -> Option<AstFuncDecl>> = None,
        opts!: GlobalOptions = GlobalOptions(), kind!: IncreKind = IncreKind.INVALID,
        chirWFC!: Bool = false, chirOptOverO2!: Bool = false,
        diag!: Option<BasicDiagnosticEngine> = None, isComputingAnnos!: Bool = false) {
        this.builder = builder
        this.chirType = chirType
        this.sourceManager = sourceManager
        this.importedPackages = importedPkgs
        this.directImportedPackages = directImportedPkgs
        this.gim = gim
        this.overrideSrcFuncResolver = overrideSrcFuncResolver
        this.opts = opts
        this.kind = kind
        this.chirWFC = chirWFC
        this.chirOptOverO2 = chirOptOverO2
        this.diag = diag
        this.isComputingAnnos = isComputingAnnos
    }

    public func ToCHIRPackage(node: AstPackage): Bool {
        if (!opts.IsCompilingCJMPSpecific()) {
            outputPackage = builder.CreatePackage(node.fullPackageName)
        } else if (TryToDeserializeCHIR()) {
            outputPackage = builder.context.GetCurPackage()
            BuildDeserializedTable()
        } else {
            return false
        }
        CurrentPackage().SetPackageAccessLevel(BuildPackageAccessLevel(node.accessible))
        RegisterAllSources()
        CollectImplicitFuncs(node)
        CollectImportedDecls(node)
        CollectDeclsInCurPkg(node)
        let initOrder = GlobalDeclAnalysis(node)
        if (failure) {
            return false
        }
        CacheTopLevelDeclToGlobalSymbolTable()
        TranslateNominalDecls(node)
        TranslateInitOfGlobalVars(initOrder)
        TranslateOtherTopLevelDecls(node)
        FlatForInExpr(builder).RunOnPackage(CurrentPackage())
        try (recorder = ProfileRecorder("Canonicalization", "GenerateVTable")) {
            let allDefs = CurrentPackage().GetAllCustomTypeDef()
            let generator = GenerateVTable(CurrentPackage(), allDefs, builder, opts, "GenerateVTable")
            generator.CreateVTable()
            generator.UpdateOperatorVirFunc()
            generator.CreateVirtualFuncWrapper(IncreKind.INVALID, CompilationCache(), VirtualWrapperDepMap(),
                VirtualWrapperDepMap())
            generator.SetSrcFuncType()
            generator.CreateMutFuncWrapper()
            generator.UpdateFuncCall()
        }
        MarkClassHasInited(builder).RunOnPackage(CurrentPackage())
        UpdateMemberVarPath(builder).RunOnPackage(CurrentPackage())
        NoSideEffectMarker().RunOnPackage(CurrentPackage())
        BoxRecursionValueType(CurrentPackage(), builder).Run()
        if (chirWFC) {
            AST2CHIRCheck()
        }
        return !failure
    }

    private func RegisterAllSources(): Unit {
        let sources = sourceManager.GetSources()
        for ((_, source) in sources) {
            var filePath = source.path
            if (let Some(absPath) <- FileUtil.GetAbsPath(source.path)) {
                filePath = absPath
            } else {
                filePath = FileUtil.Normalize(filePath)
            }
            builder.context.RegisterSourceFileName(UInt32(source.fileID), filePath)
        }
    }

    public func HasFailed(): Bool {
        return failure
    }

    public func GetFailureReason(): String {
        return failureReason
    }

    public func GetPackage(): Option<Package> {
        return outputPackage
    }

    public func GetGlobalCache(): FaithfulAST2CHIRNodeMap {
        return globalCache
    }

    public func GetImplicitFuncs(): HashMap<String, Function> {
        return implicitFuncs
    }

    public func GetInitFuncsForConstVar(): ArrayList<Function> {
        for (fn in initFuncsForAnnoFactory) {
            initFuncsForConstVar.add(fn)
        }
        return initFuncsForConstVar
    }

    public func GetMaybeUnreachableBlocks(): HashMap<Block, Terminator> {
        return maybeUnreachable
    }

    public func GetSrcCodeImportedFuncs(): ArrayList<Function> {
        let funcs = ArrayList<Function>()
        for (decl in globalAndMemberFuncs) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            if (let Some(fn) <- (globalCache.Get(decl) as Function)) {
                if (!ContainsFunction(funcs, fn)) {
                    funcs.add(fn)
                }
            }
        }
        return funcs
    }

    public func GetSrcCodeImportedVars(): ArrayList<GlobalVar> {
        let vars = ArrayList<GlobalVar>()
        for (decl in globalAndStaticVars) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            if (let Some(globalVar) <- (globalCache.Get(decl) as GlobalVar)) {
                if (!ContainsGlobalVar(vars, globalVar)) {
                    vars.add(globalVar)
                }
            }
        }
        return vars
    }

    public func ReplaceSrcCodeImportedValAfterClosureConversion(pkg: Package, uselessClasses: ArrayList<ClassDef>,
        uselessLambda: ArrayList<Function>): Unit {
        let initFuncsToRemove = ArrayList<Function>()
        for (fn in GetSrcCodeImportedFuncs()) {
            fn.DestroyFuncBody()
        }
        for (globalVar in GetSrcCodeImportedVars()) {
            if (let Some(initFunc) <- globalVar.GetInitFunc()) {
                if (!ContainsFunction(initFuncsToRemove, initFunc)) {
                    initFuncsToRemove.add(initFunc)
                }
            }
            globalVar.DestroyInitializer()
        }
        let newFuncs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (!ContainsFunction(initFuncsToRemove, fn)) {
                newFuncs.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(newFuncs)
        RemoveUselessDefFromCC(pkg, uselessClasses, uselessLambda)
    }

    private func CurrentPackage(): Package {
        return outputPackage ?? throw IllegalStateException("faithful AST2CHIR package has not been created")
    }

    private func AddToImplicitFuncs(funcDecl: AstFuncDecl,
        registeredImplicitFuncs: ArrayList<ImplicitImportedFunc>): Unit {
        if (opts.sancovOption.IsSancovEnabled() &&
            (funcDecl.mangledName == FUNC_MANGLE_NAME_MALLOC_CSTRING ||
                funcDecl.mangledName == FUNC_MANGLE_NAME_CSTRING_SIZE)) {
            implicitDecls.add(funcDecl)
            return
        }
        for (funcInfo in registeredImplicitFuncs) {
            let parentDecl = funcDecl.outerDecl
            let parentMatches = if (funcInfo.parentName.isEmpty()) {
                parentDecl.isNone()
            } else if (let Some(parent) <- parentDecl) {
                parent.identifier.Val() == funcInfo.parentName && parent.astKind == funcInfo.parentKind
            } else {
                false
            }
            if (funcDecl.identifier.Val() == funcInfo.identifier && parentMatches) {
                implicitDecls.add(funcDecl)
                return
            }
        }
    }

    private func CollectImplicitFuncs(node: AstPackage): Unit {
        let genericFuncs = ImplicitImportedFuncMgr.Instance().GetImplicitImportedFuncs(
            ImplicitImportedFuncMgrFuncKind.GENERIC)
        let collectImplicitDecls = { astNode: AstNode =>
            if (let Some(funcDecl) <- (astNode as AstFuncDecl)) {
                AddToImplicitFuncs(funcDecl, genericFuncs)
                return AstVisitAction.SKIP_CHILDREN
            }
            return AstVisitAction.WALK_CHILDREN
        }
        for (importedPkg in importedPackages) {
            for (instantiatedDecl in importedPkg.genericInstantiatedDecls) {
                AstWalker(instantiatedDecl, visitPre: collectImplicitDecls).Walk()
            }
        }

        let nonGenericFuncs = ImplicitImportedFuncMgr.Instance().GetImplicitImportedFuncs(
            ImplicitImportedFuncMgrFuncKind.NONE_GENERIC)
        var stdCorePkg: Option<AstPackage> = None
        if (node.fullPackageName == CORE_PACKAGE_NAME) {
            stdCorePkg = Some(node)
        } else {
            for (importedPkg in importedPackages) {
                if (importedPkg.fullPackageName == CORE_PACKAGE_NAME) {
                    stdCorePkg = Some(importedPkg)
                    break
                }
            }
        }
        let corePkg = stdCorePkg ??
            throw IllegalStateException("faithful AST2CHIR cannot find imported std.core package")
        let collectNonGenericDecls = { astNode: AstNode =>
            if (let Some(funcDecl) <- (astNode as AstFuncDecl)) {
                AddToImplicitFuncs(funcDecl, nonGenericFuncs)
                return AstVisitAction.SKIP_CHILDREN
            }
            return AstVisitAction.WALK_CHILDREN
        }
        for (file in corePkg.files) {
            for (decl in file.decls) {
                AstWalker(decl, visitPre: collectNonGenericDecls).Walk()
            }
            for (decl in file.exportedInternalDecls) {
                AstWalker(decl, visitPre: collectNonGenericDecls).Walk()
            }
        }
        for (implicitDecl in implicitDecls) {
            CJC_ASSERT(implicitDecl.IsFunc())
        }
    }

    private func CollectImportedDecls(node: AstPackage): Unit {
        let mangledNameSet = HashSet<String>()
        for (decl in node.genericInstantiatedDecls) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (let Some(curFile) <- genericDecl.curFile) {
                    if (let Some(curPackage) <- curFile.curPackage) {
                        if (curPackage.fullPackageName == node.fullPackageName) {
                            continue
                        }
                    }
                }
                if (let Some(genericFunc) <- (genericDecl as AstFuncDecl)) {
                    if (let Some(outer) <- genericFunc.outerDecl) {
                        if ((outer as AstFuncDecl).isSome()) {
                            continue
                        }
                    }
                }
            }
            if (decl.astKind != ASTKind.EXTEND_DECL) {
                if (mangledNameSet.contains(decl.mangledName)) {
                    continue
                }
                mangledNameSet.add(decl.mangledName)
            }
            CollectDecls(decl, instantiated: true)
        }
        for (importedPackage in importedPackages) {
            if (importedPackage.fullPackageName == node.fullPackageName) {
                continue
            }
            for (file in importedPackage.files) {
                for (decl in file.decls) {
                    CollectImportedDeclUsedInCurPkg(decl)
                }
                for (decl in file.exportedInternalDecls) {
                    CollectImportedDeclUsedInCurPkg(decl)
                }
            }
        }
    }

    private func CollectDeclsInCurPkg(node: AstPackage): Unit {
        for (file in node.files) {
            pkgFiles.add(file)
            for (decl in file.decls) {
                CollectDecls(decl, instantiated: false)
            }
        }
    }

    private func CollectDeclToList(decl: AstDecl, astNodes: ArrayList<AstDecl>,
        astNodeSet: FaithfulInitDeclSet): Unit {
        if (allTopLevelNodeSet.Add(decl)) {
            allTopLevelNodes.add(decl)
        }
        if (astNodeSet.Add(decl)) {
            astNodes.add(decl)
        }
    }

    private func CollectImportedDeclUsedInCurPkg(decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.isUsedImports) {
            return
        }
        if (decl.TestAttr(AstAttribute.GENERIC) ||
            (decl.outerDecl.isSome() && decl.outerDecl.getOrThrow().TestAttr(AstAttribute.GENERIC))) {
            CollectImportedGenericDecl(decl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls, importedNominalDeclSet)
            for (member in decl.GetMemberDecls()) {
                CollectImportedDeclUsedInCurPkg(member)
            }
            return
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedGenericDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectImportedFuncDeclAndDesugarParams(funcDecl)
            return
        }
        if (decl.IsNominalDecl()) {
            CollectDeclToList(decl, importedNominalDecls, importedNominalDeclSet)
            for (member in decl.GetMemberDecls()) {
                CollectImportedGenericDecl(member)
            }
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            CollectImportedPropDecl(propDecl)
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectImportedGlobalOrStaticVarDecl(varDecl)
            }
        }
    }

    private func CollectImportedFuncDeclAndDesugarParams(funcDecl: AstFuncDecl): Unit {
        if (let Some(outer) <- funcDecl.outerDecl) {
            if (outer.IsNominalDecl()) {
                CollectDeclToList(outer, importedNominalDecls, importedNominalDeclSet)
            }
        }
        if (IsSrcCodeImportedGlobalDecl(funcDecl)) {
            CollectDeclToList(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
            CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
            return
        }
        CollectDeclToList(funcDecl, importedGlobalAndMemberFuncs, importedGlobalAndMemberFuncSet)
        CollectDesugaredDefaultParams(funcDecl, importedGlobalAndMemberFuncs, importedGlobalAndMemberFuncSet)
    }

    private func CollectImportedPropDecl(propDecl: AstPropDecl): Unit {
        for (getter in propDecl.getters) {
            CollectImportedFuncDeclAndDesugarParams(getter)
        }
        for (setter in propDecl.setters) {
            CollectImportedFuncDeclAndDesugarParams(setter)
        }
    }

    private func CollectImportedGlobalOrStaticVarDecl(varDecl: AstVarDecl): Unit {
        if (IsSrcCodeImportedGlobalDecl(varDecl)) {
            CollectDeclToList(varDecl, globalAndStaticVars, globalAndStaticVarSet)
            return
        }
        CollectDeclToList(varDecl, importedGlobalAndStaticVars, importedGlobalAndStaticVarSet)
    }

    private func CollectDecls(decl: AstDecl, instantiated!: Bool): Unit {
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                if (decl.TestAttr(AstAttribute.GENERIC)) {
                    CollectInstantiatedDecls(decl)
                }
                CollectDeclsFromStructDecl(RequireStructDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.CLASS_DECL =>
                if (decl.TestAttr(AstAttribute.GENERIC)) {
                    CollectInstantiatedDecls(decl)
                }
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.INTERFACE_DECL =>
                if (decl.TestAttr(AstAttribute.GENERIC)) {
                    CollectInstantiatedDecls(decl)
                }
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.ENUM_DECL =>
                if (decl.TestAttr(AstAttribute.GENERIC)) {
                    CollectInstantiatedDecls(decl)
                }
                CollectDeclsFromEnumDecl(RequireEnumDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.EXTEND_DECL =>
                if (decl.TestAttr(AstAttribute.GENERIC)) {
                    CollectInstantiatedDecls(decl)
                }
                CollectDeclsFromExtendDecl(RequireExtendDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.FUNC_DECL =>
                CollectFuncDecl(RequireFuncDecl(decl))
            case ASTKind.MAIN_DECL =>
                CollectDesugarDecl(decl)
            case ASTKind.MACRO_DECL =>
                CollectDesugarDecl(decl)
            case ASTKind.VAR_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                CollectVarandVarwithpatternDecl(decl)
            case _ => ()
        }
    }

    private func CollectNominalDecl(decl: AstDecl, instantiated: Bool): Unit {
        if (instantiated) {
            CollectDeclToList(decl, importedGenericInstantiatedNominalDecls,
                importedGenericInstantiatedNominalDeclSet)
            return
        }
        if (decl.TestAttr(AstAttribute.GENERIC)) {
            CollectDeclToList(decl, genericNominalDecls, genericNominalDeclSet)
            return
        }
        CollectDeclToList(decl, nominalDecls, nominalDeclSet)
    }

    private func CollectDeclsFromEnumDecl(enumDecl: AstEnumDecl): Unit {
        for (member in enumDecl.members) {
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromClassLikeDecl(classLikeDecl: AstClassLikeDecl): Unit {
        for (member in classLikeDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromStructDecl(structDecl: AstStructDecl): Unit {
        for (member in structDecl.GetMemberDecls()) {
            if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            CollectMemberDecl(member)
        }
    }

    private func CollectDeclsFromExtendDecl(extendDecl: AstExtendDecl): Unit {
        for (member in extendDecl.members) {
            CollectMemberDecl(member)
        }
    }

    private func CollectMemberDecl(decl: AstDecl): Unit {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            CollectFuncDecl(funcDecl)
            return
        }
        if (let Some(propDecl) <- (decl as AstPropDecl)) {
            for (getter in propDecl.getters) {
                CollectFuncDecl(getter)
            }
            for (setter in propDecl.setters) {
                CollectFuncDecl(setter)
            }
            return
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                CollectDeclToList(varDecl, globalAndStaticVars, globalAndStaticVarSet)
            }
        }
    }

    private func CollectInstantiatedDecls(decl: AstDecl): Unit {
        CJC_ASSERT(decl.TestAttr(AstAttribute.GENERIC))
        let curFile = decl.curFile.getOrThrow()
        let curPackage = curFile.curPackage.getOrThrow()
        if (curPackage.fullPackageName != CurrentPackage().GetName()) {
            return
        }
        let manager = match (gim) {
            case Some(value) => value
            case None => return
        }
        let instantiatedDecls = ArrayList<AstDecl>()
        let instantiatedDeclIds = HashSet<Int64>()
        for (instantiatedDecl in manager.GetInstantiatedDecls(decl)) {
            if (!instantiatedDeclIds.contains(instantiatedDecl.objectId)) {
                instantiatedDeclIds.add(instantiatedDecl.objectId)
                instantiatedDecls.add(instantiatedDecl)
            }
        }

        sort(instantiatedDecls, by: { left: AstDecl, right: AstDecl =>
            CJC_ASSERT(left.mangledName != right.mangledName)
            if (left.mangledName < right.mangledName) {
                Ordering.LT
            } else if (left.mangledName > right.mangledName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        for (instance in instantiatedDecls) {
            CollectDecls(instance, instantiated: false)
        }
    }

    private func CollectFuncDecl(funcDecl: AstFuncDecl): Unit {
        if (funcDecl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (funcDecl.TestAttr(AstAttribute.FOREIGN)) {
            CollectDeclToList(funcDecl, foreignFuncs, foreignFuncSet)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.GENERIC)) {
            CollectInstantiatedDecls(funcDecl)
        }
        CollectDeclToList(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
        CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
    }

    private func CollectDesugarDecl(decl: AstDecl): Unit {
        if (decl.astKind == ASTKind.MAIN_DECL) {
            // The desugarDecl has the attribute MAIN_ENTRY.
            if (let Some(desugared) <- decl.GetDesugarDecl()) {
                CollectFuncDecl(desugared)
            }
            return
        }
        if (decl.astKind == ASTKind.MACRO_DECL) {
            // The desugarDecl has the attribute MACRO_FUNC.
            if (let Some(desugared) <- decl.GetDesugarDecl()) {
                CollectFuncDecl(desugared)
            }
        }
    }

    private func CollectDesugaredDefaultParams(funcDecl: AstFuncDecl, list: ArrayList<AstDecl>,
        listSet: FaithfulInitDeclSet): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        CollectDeclToList(desugarDecl, list, listSet)
                    }
                }
            }
        }
    }

    private func CollectVarandVarwithpatternDecl(decl: AstDecl): Unit {
        CollectDeclToList(decl, globalAndStaticVars, globalAndStaticVarSet)
    }

    private func CacheTopLevelDeclToGlobalSymbolTable(): Unit {
        CacheCustomTypeDefToGlobalSymbolTable()
        TranslateAllCustomTypeTy()
        for (decl in foreignFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndMemberFuncs) {
            CreateImportedFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
        for (decl in importedGlobalAndStaticVars) {
            CreateImportedValueSignatureAndSetGlobalCache(RequireVarDecl(decl))
        }
        for (decl in globalAndMemberFuncs) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                CreateFuncSignatureAndSetGlobalCache(funcDecl)
            } else {
                throw IllegalArgumentException(
                    "faithful AST2CHIR expected function-like decl, got ${ASTKindName(decl.astKind)}")
            }
        }
        CreateGlobalVarSignature(globalAndStaticVars)
        CreateGlobalVarSignature(localConstVars.stableOrderValue, isLocalConst: true)
        for (decl in localConstFuncs.stableOrderValue) {
            CreateFuncSignatureAndSetGlobalCache(RequireFuncDecl(decl))
        }
    }

    private func CacheCustomTypeDefToGlobalSymbolTable(): Unit {
        for (decl in nominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in genericNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
        for (decl in importedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: true)
        }
        for (decl in importedGenericInstantiatedNominalDecls) {
            CreateCustomTypeDef(decl, isImported: false)
        }
    }

    private func CreateCustomTypeDef(decl: AstDecl, isImported!: Bool): Unit {
        let loc = TranslateLocationWithoutScope(builder.context, decl.begin, decl.end)
        let packageName = if (let Some(genericDecl) <- decl.genericDecl) {
            genericDecl.fullPackageName
        } else {
            decl.fullPackageName
        }
        let identifier = decl.mangledName
        let srcIdentifier = decl.identifier.Val()
        var uniqueDecl: Option<AstDecl> = None
        var customTypeDef = TryGetDeserialized<CustomTypeDef>(decl)
        if (let Some(def) <- customTypeDef) {
            def.SetDebugLocation(loc)
        }
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                if (customTypeDef.isNone()) {
                    customTypeDef = builder.CreateStruct(loc, srcIdentifier, identifier, packageName, isImported)
                }
                if (let Some(unique) <- (RequireAstTy(decl) as AstStructTy).getOrThrow().decl) {
                    uniqueDecl = unique as AstDecl
                }
            case ASTKind.CLASS_DECL | ASTKind.INTERFACE_DECL =>
                if (customTypeDef.isNone()) {
                    customTypeDef = builder.CreateClass(loc, srcIdentifier, identifier, packageName,
                        decl.astKind == ASTKind.CLASS_DECL, isImported)
                }
                if (let Some(unique) <- (RequireAstTy(decl) as AstClassLikeTy).getOrThrow().commonDecl) {
                    uniqueDecl = unique as AstDecl
                }
            case ASTKind.ENUM_DECL =>
                if (customTypeDef.isNone()) {
                    let enumDecl = (decl as AstEnumDecl).getOrThrow()
                    customTypeDef = builder.CreateEnum(loc, srcIdentifier, identifier, packageName, isImported,
                        enumDecl.hasEllipsis)
                }
                if (let Some(unique) <- (RequireAstTy(decl) as AstEnumTy).getOrThrow().decl) {
                    uniqueDecl = unique as AstDecl
                }
            case ASTKind.EXTEND_DECL =>
                if (customTypeDef.isNone()) {
                    customTypeDef = builder.CreateExtend(loc, identifier, packageName, isImported,
                        GetGenericParamType(decl))
                }
            case _ =>
                throw IllegalArgumentException(
                    "faithful AST2CHIR CreateCustomTypeDef expected nominal decl, got ${ASTKindName(decl.astKind)}")
        }
        let def = customTypeDef.getOrThrow()
        if (kind == IncreKind.INCR && decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED) &&
            !decl.toBeCompiled) {
            def.EnableAttr(Attribute.NON_RECOMPILE)
        }
        if (!def.TestAttr(Attribute.DESERIALIZED)) {
            ApplyDeclAttrs(def, decl)
        }
        MaybeSetCoreBuiltinClassTy(def)
        chirType.SetGlobalNominalCache(decl, def)
        if (let Some(unique) <- uniqueDecl) {
            if (unique != decl) {
                chirType.SetGlobalNominalCache(unique, def)
            }
        }
        if (decl.TestAttr(AstAttribute.COMMON) && !decl.TestAttr(AstAttribute.FROM_COMMON_PART)) {
            def.EnableAttr(Attribute.COMMON)
        }
        if (decl.TestAttr(AstAttribute.SPECIFIC)) {
            def.EnableAttr(Attribute.SPECIFIC)
            def.DisableAttr(Attribute.COMMON)
        }
    }

    private func MaybeSetCoreBuiltinClassTy(def: CustomTypeDef): Unit {
        if (let Some(classDef) <- (def as ClassDef)) {
            let ty = builder.context.GetClassTy(classDef, ArrayList<Type>())
            if (def.GetSrcCodeIdentifier() == "Object") {
                builder.context.SetObjectTy(ty)
            } else if (def.GetSrcCodeIdentifier() == "Any") {
                builder.context.SetAnyTy(ty)
            }
        }
    }

    private func TranslateAllCustomTypeTy(): Unit {
        let translatedGenericDecls = ArrayList<AstDecl>()
        let translatedGenericDeclSet = FaithfulInitDeclSet()
        for (decl in importedNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome() && decl.TestAttr(AstAttribute.GENERIC)) {
                CollectDeclToList(decl, translatedGenericDecls, translatedGenericDeclSet)
            }
        }
        for (decl in genericNominalDecls) {
            if (TranslateCustomTypeTyIfReady(decl).isSome()) {
                CollectDeclToList(decl, translatedGenericDecls, translatedGenericDeclSet)
            }
        }
        for (decl in nominalDecls) { let _ = TranslateCustomTypeTyIfReady(decl) }
        for (decl in translatedGenericDecls) {
            AttachCustomTypeGenericParams(decl)
            if (let Some(ty) <- decl.GetTy()) {
                for (arg in ty.typeArgs) {
                    if (let Some(genericTy) <- (arg as AstGenericsTy)) {
                        chirType.FillGenericArgType(genericTy)
                    }
                }
            }
        }
        for (decl in importedGenericInstantiatedNominalDecls) { TranslateCustomTypeTyIfReady(decl) }
    }

    private func CollectCommonMatchedDecls(declContainers: ArrayList<ArrayList<AstDecl>>): ArrayList<AstDecl> {
        let commonDecls = ArrayList<AstDecl>()
        for (container in declContainers) {
            for (decl in container) {
                if (decl.IsCommonMatchedWithSpecific() && decl.astKind == ASTKind.EXTEND_DECL) {
                    commonDecls.add(decl)
                }
            }
        }
        return commonDecls
    }

    private func BuildGenericTypeMapping(commonDecls: ArrayList<AstDecl>): HashMap<Int64, Type> {
        let commonGenericTy2specificGenericTy = HashMap<Int64, Type>()
        for (commonDecl in commonDecls) {
            if (commonDecl.TestAttr(AstAttribute.GENERIC)) {
                let commonGeneric = commonDecl.GetGeneric().getOrThrow()
                let specificGeneric = commonDecl.specificImplementation.getOrThrow().GetGeneric().getOrThrow()
                let commonTypeParameters = commonGeneric.typeParameters
                let specificTypeParameters = specificGeneric.typeParameters
                CJC_ASSERT(commonTypeParameters.size == specificTypeParameters.size &&
                    !commonTypeParameters.isEmpty())
                for (idx in 0..commonTypeParameters.size) {
                    let commonTypeArg = commonTypeParameters[idx].GetTy().getOrThrow()
                    let specificTypeArg = specificTypeParameters[idx].GetTy().getOrThrow()
                    if (commonTypeArg.IsGeneric() && specificTypeArg.IsGeneric()) {
                        let commonGenericTy =
                            (chirType.TranslateType(commonTypeArg) as GenericType).getOrThrow()
                        commonGenericTy2specificGenericTy[commonGenericTy.objectId] =
                            chirType.TranslateType(specificTypeArg)
                    }
                }
            }
        }
        return commonGenericTy2specificGenericTy
    }

    private func ConvertSpecificMemberMethods(chirPkg: Package, replaceGenericFunc: ConvertTypeFunc): Unit {
        let converter = PrivateTypeConverter(replaceGenericFunc, builder)
        let preVisit = { expr: Expression =>
            converter.VisitExpr(expr)
            VisitResult.CONTINUE
        }
        for (decl in chirPkg.GetExtends()) {
            if (!decl.TestAttr(Attribute.SPECIFIC)) {
                continue
            }
            for (funcDef in decl.GetMethods()) {
                if (!funcDef.TestAttr(Attribute.DESERIALIZED)) {
                    continue
                }
                if (!funcDef.IsFuncWithBody()) {
                    continue
                }
                if (funcDef.GetBody().isSome()) {
                    Visitor.Visit(funcDef, preVisit)
                }
                converter.VisitValue(funcDef)
            }
        }
    }

    private func CollectMethodNames(extendDef: ExtendDef): HashSet<String> {
        let names = HashSet<String>()
        for (method in extendDef.GetMethods()) {
            names.add(method.GetIdentifier())
        }
        return names
    }

    private func ProcessExtends(extends: ArrayList<ExtendDef>): ArrayList<ExtendDef> {
        let commonExtends = ArrayList<ExtendDef>()
        let specificExtends = ArrayList<ExtendDef>()
        for (ed in extends) {
            if (ed.TestAttr(Attribute.COMMON)) {
                commonExtends.add(ed)
            } else if (ed.TestAttr(Attribute.SPECIFIC)) {
                specificExtends.add(ed)
            }
        }

        let specificMethodNames = HashSet<String>()
        for (specificEd in specificExtends) {
            let names = CollectMethodNames(specificEd)
            for (name in names) {
                specificMethodNames.add(name)
            }
        }

        let commonToRemove = HashSet<Int64>()
        for (commonEd in commonExtends) {
            for (method in commonEd.GetMethods()) {
                if (specificMethodNames.contains(method.GetIdentifier())) {
                    commonToRemove.add(commonEd.nodeId)
                    break
                }
            }
        }

        var idx: Int64 = 0
        while (idx < extends.size) {
            if (commonToRemove.contains(extends[idx].nodeId)) {
                extends.remove(at: idx)
            } else {
                idx++
            }
        }
        return extends
    }

    private func ProcessExtendsByCommonDecl(extends: ArrayList<ExtendDef>,
        commonDecls: ArrayList<AstDecl>): ArrayList<ExtendDef> {
        let commonDeclMangledNames = HashSet<String>()
        for (commonDecl in commonDecls) {
            commonDeclMangledNames.add(commonDecl.mangledName)
        }

        var idx: Int64 = 0
        while (idx < extends.size) {
            let ed = extends[idx]
            if (ed.TestAttr(Attribute.COMMON) &&
                commonDeclMangledNames.contains(ed.GetIdentifierWithoutPrefix())) {
                extends.remove(at: idx)
            } else {
                idx++
            }
        }
        return extends
    }

    private func RemoveUnusedCJMPExtends(chirPkg: Package, commonDecls: ArrayList<AstDecl>): Unit {
        chirPkg.SetExtends(ProcessExtendsByCommonDecl(chirPkg.GetExtends(), commonDecls))
        chirPkg.SetImportedExtends(ProcessExtends(chirPkg.GetImportedExtends()))
    }

    private func ProcessCommonAndSpecificExtends(): Unit {
        if (!opts.IsCompilingCJMPSpecific()) {
            return
        }
        let commonDecls = CollectCommonMatchedDecls(ArrayList<ArrayList<AstDecl>>([
            importedNominalDecls, importedGenericInstantiatedNominalDecls, nominalDecls, genericNominalDecls]))
        let commonGenericTy2specificGenericTy = BuildGenericTypeMapping(commonDecls)
        if (!commonGenericTy2specificGenericTy.isEmpty()) {
            ConvertSpecificMemberMethods(CurrentPackage(), { ty: Type =>
                ReplaceRawGenericArgType(ty, commonGenericTy2specificGenericTy, builder)
            })
        }
        RemoveUnusedCJMPExtends(CurrentPackage(), commonDecls)
    }

    private func ProcessClassStructVarInits(trans: Translator): Unit {
        if (!opts.IsCompilingCJMP()) {
            return
        }
        let declContainers = ArrayList<ArrayList<AstDecl>>([
            importedNominalDecls, importedGenericInstantiatedNominalDecls, nominalDecls, genericNominalDecls])
        for (container in declContainers) {
            for (decl in container) {
                if (decl.TestAttr(AstAttribute.FROM_COMMON_PART)) {
                    continue
                }
                if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) {
                    trans.CreateClassStructDeclVarInit(decl)
                }
            }
        }
    }

    private func ParentIsOtherExtendGrandParent(parent: ClassType, curDef: ExtendDef): Bool {
        let extendDefs = curDef.GetExtendedType().getOrThrow().GetExtends(builder)
        let allGrandParents = HashMap<Int64, ClassType>()
        for (extendDef in extendDefs) {
            if (refEq(extendDef, curDef)) {
                continue
            }
            for (extendParent in extendDef.GetImplementedInterfaceTys()) {
                for (grandParent in extendParent.GetSuperTypesRecusively(builder)) {
                    allGrandParents[grandParent.objectId] = grandParent
                }
            }
        }
        if (allGrandParents.contains(parent.objectId)) {
            return true
        }
        let curParentTypeArgs = parent.GetGenericArgs()
        let curParentDef = parent.GetClassDef()
        for (grandParent in allGrandParents.values()) {
            if (!refEq(grandParent.GetClassDef(), curParentDef)) {
                continue
            }
            let grandParentTypeArgs = grandParent.GetGenericArgs()
            CJC_ASSERT(curParentTypeArgs.size == grandParentTypeArgs.size)
            for (idx in 0..curParentTypeArgs.size) {
                let typeArg1 = curParentTypeArgs[idx]
                let typeArg2 = grandParentTypeArgs[idx]
                if (!refEq(typeArg1, typeArg2) && !typeArg1.IsGeneric() && !typeArg2.IsGeneric()) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func UpdateExtendParent(): Unit {
        try (recorder = ProfileRecorder("TranslateNominalDecls", "UpdateExtendParent")) {
            for (customDef in CurrentPackage().GetAllCustomTypeDef()) {
                if (!customDef.IsExtend()) {
                    continue
                }
                let extendDef = (customDef as ExtendDef).getOrThrow()
                for (parent in extendDef.GetImplementedInterfaceTys()) {
                    if (ParentIsOtherExtendGrandParent(parent, extendDef)) {
                        extendDef.RemoveParent(parent)
                    }
                }
            }
        }
    }

    private func AttachCustomTypeGenericParams(decl: AstDecl): Unit {
        let def = chirType.GetGlobalNominalCache(decl)
        if (let Some(generic) <- decl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                            AddGenericTypeParamIfMissing(def, paramTy)
                        }
                    }
                }
            }
        }
    }

    private func AddGenericTypeParamIfMissing(def: CustomTypeDef, paramTy: GenericType): Unit {
        for (existing in def.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        def.AddGenericTypeParam(paramTy)
    }

    private func AddGenericTypeParamIfMissing(fn: Function, paramTy: GenericType): Unit {
        for (existing in fn.GetGenericTypeParams()) {
            if (existing.IsEqual(paramTy)) {
                return
            }
        }
        fn.AddGenericTypeParam(paramTy)
    }

    private func AttachFunctionGenericParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        if (let Some(generic) <- funcDecl.GetGeneric()) {
            let genericTys = ArrayList<AstGenericsTy>()
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        if (let Some(paramTy) <- (chirType.TranslateType(genericTy) as GenericType)) {
                            AddGenericTypeParamIfMissing(fn, paramTy)
                            genericTys.add(genericTy)
                        }
                    }
                }
            }
            for (genericTy in genericTys) {
                chirType.FillGenericArgType(genericTy)
            }
        }
    }

    private func TranslateCustomTypeTyIfReady(decl: AstDecl): Option<Type> {
        if (decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL || decl.astKind == ASTKind.ENUM_DECL) {
            if (let Some(ty) <- decl.GetTy()) {
                let translated = chirType.TranslateType(ty)
                let customType = (translated.StripAllRefs() as CustomType).getOrThrow()
                chirType.GetGlobalNominalCache(decl).SetType(customType)
                return Some(translated)
            }
        }
        return None
    }

    private func TranslateNominalDecls(node: AstPackage): Unit {
        let trans = CreateTranslator()
        try (recorder = ProfileRecorder("TranslateNominalDecls", "SetGenericFuncMap")) {
            let _ = recorder
            trans.SetGenericFuncMap(BuildGenericFuncMap(node))
        }
        TranslateVecDecl(importedNominalDecls, trans)
        TranslateVecDecl(importedGenericInstantiatedNominalDecls, trans)
        TranslateVecDecl(nominalDecls, trans)
        TranslateVecDecl(genericNominalDecls, trans)
        ProcessCommonAndSpecificExtends()
        SetExtendInfo()
        UpdateExtendParent()
        ProcessClassStructVarInits(trans)
    }

    private func BuildGenericFuncMap(pkg: AstPackage): GenericFuncMap {
        let genericFuncMap = GenericFuncMap()
        for (decl in pkg.genericInstantiatedDecls) {
            if (decl.astKind != ASTKind.FUNC_DECL || decl.outerDecl.isNone()) {
                continue
            }
            let funcDecl = (decl as AstFuncDecl).getOrThrow()
            let genericFunc = (funcDecl.genericDecl.getOrThrow() as AstFuncDecl).getOrThrow()
            genericFuncMap.Add(genericFunc, funcDecl)

            let funcBody = funcDecl.funcBody.getOrThrow()
            let genericFuncBody = genericFunc.funcBody.getOrThrow()
            CJC_ASSERT(!funcBody.paramLists.isEmpty())
            CJC_ASSERT(!genericFuncBody.paramLists.isEmpty())
            let funcParams = funcBody.paramLists[0].params
            let genericParams = genericFuncBody.paramLists[0].params
            CJC_ASSERT(funcParams.size == genericParams.size)
            var idx: Int64 = 0
            while (idx < funcParams.size) {
                if (funcParams[idx].desugarDecl.isNone() ||
                    funcParams[idx].desugarDecl.getOrThrow().astKind != ASTKind.FUNC_DECL) {
                    idx++
                    continue
                }
                let desugarDecl = (funcParams[idx].desugarDecl.getOrThrow() as AstFuncDecl).getOrThrow()
                // C++ can store a nullptr key here; objectId-keyed selfhost maps cannot.
                // Such an entry is never found by real FuncDecl lookups, so skipping preserves behavior.
                if (let Some(genericParamDesugarDecl) <- genericParams[idx].desugarDecl) {
                    genericFuncMap.Add((genericParamDesugarDecl as AstFuncDecl).getOrThrow(), desugarDecl)
                }
                idx++
            }
        }
        return genericFuncMap
    }

    private func SetExtendInfo(): Unit {
        try (recorder = ProfileRecorder("TranslateNominalDecls", "SetExtendInfo")) {
            for (customDef in CurrentPackage().GetAllCustomTypeDef()) {
                if (customDef.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                    continue
                }
                let extendDef = customDef as ExtendDef
                if (let None <- extendDef) {
                    continue
                }
                let ext = extendDef.getOrThrow()
                let extendedType = ext.GetExtendedType().getOrThrow()
                if (let Some(builtinType) <- (extendedType as BuiltinType)) {
                    GetBuiltinTypeWithVTable(builtinType, builder).AddExtend(ext)
                } else {
                    let customType = (extendedType as CustomType).getOrThrow()
                    let customTypeDef = customType.GetCustomTypeDef()
                    CJC_ASSERT(customTypeDef.GetCustomKind() != CustomDefKind.TYPE_EXTEND)
                    customTypeDef.AddExtend(ext)
                }
            }
        }
    }

    private func TranslateOtherTopLevelDecls(node: AstPackage): Unit {
        let _ = node
        for (decl in globalAndMemberFuncs) {
            if (!NeedTranslate(decl)) {
                continue
            }
            let trans = CreateTranslator()
            trans.SetTopLevel(decl)
            let _ = Translator.TranslateASTNode(decl, trans)
        }
        for (decl in localConstFuncs.stableOrderValue) {
            let trans = CreateTranslator()
            trans.SetTopLevel(decl)
            let _ = Translator.TranslateASTNode(decl, trans)
        }
        TranslateVecDecl(globalAndStaticVars, CreateTranslator())
        for ((decl, funcDef) in annoFactoryFuncs) {
            let trans = CreateTranslator()
            trans.SetTopLevel(decl)
            trans.TranslateAnnoFactoryFuncBody(decl, funcDef)
        }
        SetCompileTimeValueFlag()
    }

    private func NeedTranslate(decl: AstDecl): Bool {
        return !noNeedToTranslateDecls.contains(decl)
    }

    private func SetCompileTimeValueFlag(): Unit {
        for (fn in CurrentPackage().GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.CONST)) {
                SetCompileTimeValueFlagRecursively(fn)
            }
        }
    }

    private func SetCompileTimeValueFlagRecursively(initFunc: Function): Unit {
        if (let Some(body) <- initFunc.GetBody()) {
            SetCompileTimeValueFlagRecursively(body)
        }
    }

    private func SetCompileTimeValueFlagRecursively(body: BlockGroup): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambda) <- (expr as Lambda)) {
                    lambda.SetCompileTimeValue()
                    if (let Some(lambdaBody) <- lambda.GetBody()) {
                        SetCompileTimeValueFlagRecursively(lambdaBody)
                    }
                } else {
                    for (blockGroup in expr.GetBlockGroups()) {
                        SetCompileTimeValueFlagRecursively(blockGroup)
                    }
                }
            }
        }
    }

    private func TranslateInitOfGlobalVars(initOrder: ArrayList<FaithfulInitFileVars>): Unit {
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "")
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "_literal")
        SetInitFuncForStaticVar()
    }

    private func SetInitFuncForStaticVar(): Unit {
        for (skippedStaticVar in globalAndStaticVars) {
            if (!varsInitedByStaticInitFunc.Contains(skippedStaticVar)) {
                continue
            }
            let skippedStaticVarValue = globalCache.TryGet(skippedStaticVar)
            if (skippedStaticVarValue.isNone() || skippedStaticVar.specificImplementation.isSome()) {
                continue
            }
            CJC_ASSERT(skippedStaticVar.astKind == ASTKind.VAR_DECL)
            let skippedStaticVarInCHIR = (skippedStaticVarValue.getOrThrow() as GlobalVar).getOrThrow()
            let outerDecl = skippedStaticVar.outerDecl.getOrThrow()
            let staticInitInfo = staticInitFuncInfoMap.Get(outerDecl).getOrThrow()
            let staticInitFuncInCHIR = (globalCache.Get(staticInitInfo.staticInitFunc) as Function).getOrThrow()
            skippedStaticVarInCHIR.SetInitFunc(staticInitFuncInCHIR)
        }
    }

    private func AST2CHIRCheck(): Unit {
        try (recorder = ProfileRecorder("AST to CHIR Translation", "AST2CHIRCheck")) {
            for (entry in chirType.GetAllTypeDef()) {
                let astNode = entry.decl
                let chirNode = entry.def
                if (astNode.TestAttr(AstAttribute.GENERIC) && astNode.TestAttr(AstAttribute.IMPORTED)) {
                    continue
                }
                if (astNode.TestAttr(AstAttribute.IMPORTED) && chirNode.TestAttr(Attribute.DESERIALIZED)) {
                    continue
                }
                if (chirNode.TestAttr(Attribute.SKIP_ANALYSIS)) {
                    continue
                }
                if (!AST2CHIRCheckCustomTypeDef(astNode, chirNode, globalCache)) {
                    failure = true
                    failureReason = "ast2chir checker failed"
                    chirNode.Dump()
                }
            }
            for (entry in globalCache.Entries()) {
                if (entry.value.TestAttr(Attribute.SKIP_ANALYSIS)) {
                    continue
                }
                if (!AST2CHIRCheckValue(entry.decl, entry.value)) {
                    failure = true
                    failureReason = "ast2chir checker failed"
                    entry.value.Dump()
                }
            }
            let rules = ArrayList<CHIRCheckerRule>()
            rules.add(CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE)
            rules.add(CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER)
            if (opts.commonPartCjos.isEmpty()) {
                rules.add(CHIRCheckerRule.CHECK_FUNC_BODY)
            }
            if (!CHIRChecker(CurrentPackage(), opts, builder).CheckPackage(rules)) {
                failure = true
                failureReason = "chir checker failed"
            }
        }
    }

    private func TranslateVecDecl(decls: ArrayList<AstDecl>, trans: Translator): Unit {
        for (decl in decls) {
            if (noNeedToTranslateDecls.contains(decl)) {
                continue
            }
            let _ = Translator.TranslateASTNode(decl, trans)
        }
    }

    private func TryToDeserializeCHIR(): Bool {
        CJC_ASSERT(!opts.commonPartChirs.isEmpty())
        let phase = CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)
        var success = true
        for (chirFile in opts.commonPartChirs) {
            success = CHIRDeserializer.Deserialize(chirFile, builder, phase, compilePlatform: true) && success
        }
        return success
    }

    private func BuildDeserializedTable(): Unit {
        for (def in CurrentPackage().GetAllCustomTypeDef()) {
            let identifier = def.GetIdentifier()
            if (!deserializedDefs.contains(identifier)) {
                deserializedDefs.add(identifier, def)
            }
        }
        for (globalVar in CurrentPackage().GetGlobalVars()) {
            let identifier = globalVar.GetIdentifier()
            if (!deserializedVals.contains(identifier)) {
                deserializedVals.add(identifier, globalVar)
            }
        }
        for (fn in CurrentPackage().GetGlobalFunctions(includePureAbstract: true)) {
            let identifier = if (fn.TestAttr(Attribute.FOREIGN)) {
                fn.GetRawMangledName()
            } else {
                fn.GetIdentifier()
            }
            if (!deserializedVals.contains(identifier)) {
                deserializedVals.add(identifier, fn)
            }
        }
    }

    private func MaybeDeserialized(decl: AstDecl): Bool {
        if (opts.IsCompilingCJMPSpecific() &&
            (decl.TestAttr(AstAttribute.SPECIFIC) || decl.TestAttr(AstAttribute.FROM_COMMON_PART) ||
                decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED) || decl.TestAttr(AstAttribute.IMPORTED))) {
            return true
        }
        if (let Some(outerDecl) <- decl.outerDecl) {
            return outerDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)
        }
        return false
    }

    private func TryGetDeserialized<T>(decl: AstDecl): Option<T> where T <: Base {
        if (!MaybeDeserialized(decl)) {
            return None
        }
        let key = if (decl.TestAttr(AstAttribute.FOREIGN) && decl.IsFunc()) {
            decl.rawMangleName
        } else {
            GLOBAL_VALUE_PREFIX + decl.mangledName
        }
        var result: Option<T> = None
        if (let Some(def) <- deserializedDefs.get(key)) {
            result = def as T
        }
        if (result.isNone()) {
            if (let Some(value) <- deserializedVals.get(key)) {
                result = value as T
            }
        }
        if (result.isSome() && !decl.TestAttr(AstAttribute.SPECIFIC) &&
            !(decl.TestAttr(AstAttribute.COMMON) && decl.TestAttr(AstAttribute.IMPORTED))) {
            noNeedToTranslateDecls.add(decl)
        }
        return result
    }

    private func CreateTranslator(): Translator {
        return Translator(builder, chirType, globalCache, localConstVars: localConstVars, localConstFuncs: localConstFuncs,
            deserializedVals: deserializedVals, overrideSrcFuncResolver: overrideSrcFuncResolver, opts: opts,
            annoFactoryFuncs: annoFactoryFuncs, maybeUnreachable: maybeUnreachable,
            isComputingAnnos: isComputingAnnos,
            initFuncsForAnnoFactory: initFuncsForAnnoFactory)
    }

    private func GlobalDeclAnalysis(pkg: AstPackage): ArrayList<FaithfulInitFileVars> {
        let funcsAndVars = ElementList()
        let fileAndVarMap = ArrayList<FaithfulInitFileVars>()
        funcsAndVarsDepMap = DeclDepMap()
        localConstVarsDepMap = DeclDepMap()
        CollectStaticInitFuncInfo()
        CollectFuncsAndVars(funcsAndVars, fileAndVarMap)
        CollectLocalConstFuncAndVars(pkg)

        let nodesWithDeps = ElementList()
        for (element in funcsAndVars.stableOrderValue) {
            if (kind == IncreKind.INCR && !element.toBeCompiled && element.identifier.Val() != STATIC_INIT_VAR) {
                continue
            }
            nodesWithDeps.AddElement(element)
        }
        let initOrder = Run(nodesWithDeps, fileAndVarMap, funcsAndVars)
        FlatternLocalConstVars()
        return initOrder
    }

    private func CollectStaticInitFuncInfo(): Unit {
        for (funcDecl in globalAndMemberFuncs) {
            if (!AstIsStaticInitializer(funcDecl)) {
                continue
            }
            let staticVars = ArrayList<AstDecl>()
            var staticInitVar: Option<AstDecl> = None
            let outerDecl = funcDecl.outerDecl.getOrThrow()
            for (memberVar in GetStaticMemberVars(outerDecl)) {
                if (memberVar.identifier.Val() == STATIC_INIT_VAR) {
                    staticInitVar = memberVar
                    continue
                }
                if (memberVar.initializer.isSome()) {
                    continue
                }
                staticVars.add(memberVar)
                varsInitedByStaticInitFunc.Add(memberVar)
            }
            staticInitFuncInfoMap.Set(outerDecl, StaticInitInfo(RequireFuncDecl(funcDecl), staticInitVar, staticVars))
        }
    }

    private func CollectFuncsAndVars(funcsAndVars: ElementList,
        fileAndVarMap: ArrayList<FaithfulInitFileVars>): Unit {
        for (varDecl in globalAndStaticVars) {
            if (varDecl.TestAttr(AstAttribute.STATIC) && varDecl.identifier.Val() != STATIC_INIT_VAR) {
                let fromCommon = varDecl.TestAttr(AstAttribute.FROM_COMMON_PART)
                let initedInStaticInit = varsInitedByStaticInitFunc.Contains(varDecl)
                if (!fromCommon && initedInStaticInit) {
                    continue
                }
            }
            funcsAndVars.AddElement(varDecl)
            let file = varDecl.curFile.getOrThrow()
            let entry = if (let Some(existing) <- FindInitEntryForFile(fileAndVarMap, file)) {
                existing
            } else {
                let createdEntry = FaithfulInitFileVars(file)
                fileAndVarMap.add(createdEntry)
                createdEntry
            }
            entry.vars.add(varDecl)
        }
        for (funcDecl in globalAndMemberFuncs) {
            if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY) || funcDecl.identifier.Val() == MAIN_INVOKE) {
                continue
            }
            funcsAndVars.AddElement(funcDecl)
        }
    }

    private func ShouldSkipSelf(funcDecl: AstFuncDecl, funcStack: Int64): Bool {
        if (funcDecl.ownerFunc.isSome() && funcStack == 1) {
            return true
        }
        if (funcDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            let genericDecl = funcDecl.genericDecl ??
                throw IllegalStateException("faithful CollectLocalConstDecl generic instantiated func has no generic decl")
            let genericFunc = (genericDecl as AstFuncDecl) ??
                throw IllegalStateException("faithful CollectLocalConstDecl generic decl is not FuncDecl")
            if (!localConstFuncs.HasElement(genericFunc)) {
                return true
            }
        }
        return false
    }

    private func ShouldSkipChildren(funcDecl: AstFuncDecl): Bool {
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            if (outerDecl.IsNominalDecl()) {
                return true
            }
        }
        if (funcDecl.TestAttr(AstAttribute.GENERIC)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            if (outerDecl.TestAttr(AstAttribute.GENERIC)) {
                return true
            }
        }
        if (funcDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED) && IsLocalFunc(funcDecl)) {
            return true
        }
        return false
    }

    private func GetOuterDecl(decl: AstDecl): Option<AstDecl> {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (let Some(ownerFunc) <- funcDecl.ownerFunc) {
                return ownerFunc.outerDecl
            }
        }
        return decl.outerDecl
    }

    private func IsLocalFunc(funcDecl: AstFuncDecl): Bool {
        if (let Some(outerDecl) <- GetOuterDecl(funcDecl)) {
            return outerDecl.astKind == ASTKind.FUNC_DECL || outerDecl.astKind == ASTKind.VAR_DECL
        }
        return false
    }

    private func CollectLocalConstDecl(decls: ArrayList<AstDecl>, rootIsGlobalDecl: Bool): Unit {
        let funcStack = ArrayList<Int64>()
        funcStack.add(0)
        let preVisit = { node: AstNode =>
            if (let Some(funcDecl) <- (node as AstFuncDecl)) {
                if (ShouldSkipSelf(funcDecl, funcStack[0])) {
                    funcStack[0]++
                    return AstVisitAction.SKIP_CHILDREN
                }
            }
            if (funcStack[0] != 0) {
                if (let Some(varDecl) <- (node as AstVarDecl)) {
                    if (varDecl.IsConst()) {
                        localConstVars.AddElement(varDecl)
                    }
                } else if (let Some(funcDecl) <- (node as AstFuncDecl)) {
                    if (funcDecl.IsConst()) {
                        localConstFuncs.AddElement(funcDecl)
                        let funcBody = funcDecl.funcBody ??
                            throw IllegalStateException("faithful CollectLocalConstDecl const func has no FuncBody")
                        if (!funcBody.paramLists.isEmpty()) {
                            for (param in funcBody.paramLists[0].params) {
                                if (let Some(desugarDecl) <- param.desugarDecl) {
                                    localConstFuncs.AddElement(desugarDecl)
                                }
                            }
                        }
                    }
                }
            }
            if (node.astKind == ASTKind.LAMBDA_EXPR || node.astKind == ASTKind.MACRO_DECL ||
                node.astKind == ASTKind.FUNC_DECL) {
                funcStack[0]++
            }
            if (let Some(funcDecl) <- (node as AstFuncDecl)) {
                if (ShouldSkipChildren(funcDecl)) {
                    return AstVisitAction.SKIP_CHILDREN
                }
            }
            return AstVisitAction.WALK_CHILDREN
        }
        let postVisit = { node: AstNode =>
            if (node.astKind == ASTKind.LAMBDA_EXPR || node.astKind == ASTKind.MACRO_DECL ||
                node.astKind == ASTKind.FUNC_DECL) {
                funcStack[0]--
                CJC_ASSERT(funcStack[0] >= 0)
            }
            return AstVisitAction.WALK_CHILDREN
        }
        for (decl in decls) {
            funcStack[0] = if (rootIsGlobalDecl) { 0 } else { 1 }
            AstWalker(decl, visitPre: preVisit, visitPost: postVisit).Walk()
        }
    }

    private func CollectLocalConstFuncAndVars(pkg: AstPackage): Unit {
        CollectLocalConstDecl(globalAndStaticVars, true)
        CollectLocalConstDecl(globalAndMemberFuncs, true)

        let instanceMemberVars = ArrayList<AstDecl>()
        for (decl in nominalDecls) {
            for (member in decl.GetMemberDeclPtrs()) {
                if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(AstAttribute.STATIC)) {
                    instanceMemberVars.add(member)
                }
            }
        }
        CollectLocalConstDecl(instanceMemberVars, true)

        let instLocalconstFuncs = ArrayList<AstDecl>()
        for (decl in pkg.genericInstantiatedDecls) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                if (funcDecl.IsConst() && IsLocalFunc(funcDecl)) {
                    instLocalconstFuncs.add(funcDecl)
                }
            }
        }
        CollectLocalConstDecl(instLocalconstFuncs, false)
    }

    private func FlatternLocalConstVars(): Unit {
        let flatternedLocalConstVars = ElementList()
        for (element in localConstVars.stableOrderValue) {
            if (element.astKind == ASTKind.VAR_DECL) {
                element.toBeCompiled = true
                flatternedLocalConstVars.AddElement(element)
            } else if (let Some(varWithPattern) <- (element as AstVarWithPatternDecl)) {
                varWithPattern.toBeCompiled = true
                let allPatterns = ArrayList<AstVarDecl>()
                FlattenGlobalVarWithPatternDecl(RequirePattern(varWithPattern.irrefutablePattern,
                    "local const var-with-pattern pattern"), allPatterns)
                for (varDecl in allPatterns) {
                    varDecl.toBeCompiled = true
                    flatternedLocalConstVars.AddElement(varDecl)
                }
            }
        }
        localConstVars = flatternedLocalConstVars
    }

    private func Run(nodesWithDeps: ElementList, fileAndVarMap: ArrayList<FaithfulInitFileVars>,
        funcsAndVars: ElementList): ArrayList<FaithfulInitFileVars> {
        let orderedFiles = SortGlobalVarDep(nodesWithDeps, fileAndVarMap, funcsAndVars)
        if (failure) {
            return ArrayList<FaithfulInitFileVars>()
        }
        let initOrder = ArrayList<FaithfulInitFileVars>()
        for (file in orderedFiles) {
            let entry = FaithfulInitFileVars(file)
            if (let Some(varsInFile) <- FindInitEntryForFile(fileAndVarMap, file)) {
                for (varDecl in varsInFile.vars) {
                    entry.vars.add(varDecl)
                }
            }
            initOrder.add(entry)
        }
        funcsAndVars.AddElements(localConstVars.stableOrderValue)
        return SortLocalConstVarDep(initOrder, funcsAndVars)
    }

    private func SortGlobalVarDep(nodesWithDeps: ElementList, fileAndVarMap: ArrayList<FaithfulInitFileVars>,
        funcsAndVars: ElementList): ArrayList<AstFile> {
        AnalysisDependency(nodesWithDeps, funcsAndVars)
        // GAP_TODO(sortglobalvardep-cache-merge): needs CompilationCache.h:149 varAndFuncDep over AST Decl identity.
        // Resume at GlobalDeclAnalysis.cpp:484-490 after the AST Decl identity carrier exists in selfhost.

        let fileDependencyMap = FileDepMap()
        for (decl in funcsAndVars.stableOrderValue) {
            let file = decl.curFile.getOrThrow()
            if (!fileDependencyMap.Contains(file)) {
                fileDependencyMap.InitDeps(file)
            }
        }
        let var2varDepsInFile = DeclDepMap()
        AnalysisFileDependency(funcsAndVarsDepMap, fileDependencyMap, var2varDepsInFile)

        let fileChecker = FileCirDepsChecker(ArrayList<String>())
        fileChecker.InitFileDep(fileDependencyMap)
        fileChecker.DoTarjanSort()
        fileChecker.UpdateSccUnit(fileDependencyMap)
        let sortedFiles = fileChecker.GetOrderElement()
        if (fileChecker.hasCircularDependency) {
            failure = true
            failureReason = "chir file might circular dependency"
            return ArrayList<AstFile>()
        }
        if (kind == IncreKind.INCR) {
            for (fileVars in fileAndVarMap) {
                CheckUseBeforeInit(fileVars.vars, var2varDepsInFile)
            }
        }
        return sortedFiles
    }

    private func AnalysisDependency(nodesWithDeps: ElementList, funcsAndVars: ElementList): Unit {
        let globalVarSet = BuildDeclSet(globalAndStaticVars)
        let candidateSet = BuildDeclSet(funcsAndVars.stableOrderValue)
        for (localConstVar in localConstVars.stableOrderValue) {
            candidateSet.Add(localConstVar)
        }
        let patternOwnerMap = BuildPatternDependencyOwnerMap()
        for (node in nodesWithDeps.stableOrderValue) {
            if (let Some(varWithPattern) <- (node as AstVarWithPatternDecl)) {
                ParseVarWithPatternDecl(varWithPattern, patternOwnerMap)
            }
        }
        for (node in nodesWithDeps.stableOrderValue) {
            if (let Some(varDecl) <- (node as AstVarDecl)) {
                if (varDecl.TestAttr(AstAttribute.STATIC) && !varDecl.TestAttr(AstAttribute.DEFAULT)) {
                    continue
                }
            }
            let (dependencies, localConstVarDeps) =
                CollectDirectDependencies(node, candidateSet, globalVarSet, patternOwnerMap)
            if (MergingSpecific()) {
                ReplaceCommonDependenciesWithSpecific(dependencies)
                RestoreCJMPDependencies(node, dependencies)
            }
            if (OutputCHIR()) {
                SaveCJMPDependencies(node, dependencies)
            }
            funcsAndVarsDepMap.AddDeps(node, dependencies)
            localConstVarsDepMap.AddDeps(node, localConstVarDeps)
        }
    }

    private func AnalysisFileDependency(funcsAndVarsDepMap: DeclDepMap, fileDependencyMap: FileDepMap,
        var2varDepsInFile: DeclDepMap): Unit {
        for (element in funcsAndVarsDepMap.stableOrderValue) {
            let srcDecl = element.decl
            if (srcDecl.astKind != ASTKind.VAR_DECL && srcDecl.astKind != ASTKind.VAR_WITH_PATTERN_DECL) {
                continue
            }
            let visited = FaithfulInitDeclSet()
            AnalysisFileDependencyImpl(srcDecl, srcDecl, visited, funcsAndVarsDepMap, fileDependencyMap,
                var2varDepsInFile)
        }
    }

    private func AnalysisFileDependencyImpl(rootDecl: AstDecl, curDecl: AstDecl, visited: FaithfulInitDeclSet,
        funcsAndVarsDepMap: DeclDepMap, fileDependencyMap: FileDepMap, var2varDepsInFile: DeclDepMap): Unit {
        if (!funcsAndVarsDepMap.Contains(curDecl)) {
            if (!curDecl.TestAttr(AstAttribute.SRC_IMPORTED)) {
                throw IllegalStateException("faithful GlobalDeclAnalysis expected source imported decl")
            }
            return
        }
        let directDepsOfCurDecl = funcsAndVarsDepMap.GetDep(curDecl)
        for (dep in directDepsOfCurDecl) {
            if (visited.Contains(dep)) {
                continue
            }
            visited.Add(dep)
            if (dep.astKind == ASTKind.VAR_DECL || dep.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                let rootFile = rootDecl.curFile.getOrThrow()
                let depFile = dep.curFile.getOrThrow()
                if (rootFile == depFile) {
                    var2varDepsInFile.AddDep(rootDecl, dep)
                } else {
                    fileDependencyMap.AddDep(rootFile, depFile)
                }
            } else {
                AnalysisFileDependencyImpl(rootDecl, dep, visited, funcsAndVarsDepMap, fileDependencyMap,
                    var2varDepsInFile)
            }
        }
    }

    private func CheckUseBeforeInit(vars: ArrayList<AstDecl>, var2varDepsInFile: DeclDepMap): Unit {
        let alreadyInited = FaithfulInitDeclSet()
        for (varDecl in vars) {
            alreadyInited.Add(varDecl)
            if (varDecl.identifier.Val() == STATIC_INIT_VAR) {
                continue
            }
            for (dep in var2varDepsInFile.GetDep(varDecl)) {
                if (!alreadyInited.Contains(dep)) {
                    if (let Some(diagValue) <- diag) {
                        diagValue.Diagnose(BasicDiagKind.chir_used_before_initialization,
                            args: [BasicDiagArgument(dep.identifier.Val())]).Emit()
                    } else {
                        failure = true
                        failureReason = "variable '${dep.identifier.Val()}' is used before initialization"
                    }
                }
            }
        }
    }

    private func SortLocalConstVarDep(initOrder: ArrayList<FaithfulInitFileVars>,
        funcsAndVars: ElementList): ArrayList<FaithfulInitFileVars> {
        let globalVarsAndLocalConstVars = ArrayList<AstDecl>()
        for (element in funcsAndVars.stableOrderValue) {
            if (element.astKind == ASTKind.VAR_DECL || element.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                globalVarsAndLocalConstVars.add(element)
            }
        }
        if (globalVarsAndLocalConstVars.isEmpty()) {
            return initOrder
        }

        AnalysisDependency(localConstVars, funcsAndVars)
        for (element in localConstVarsDepMap.stableOrderValue) {
            for (dep in element.deps) {
                funcsAndVarsDepMap.AddDep(element.decl, dep)
            }
        }
        let globalVarsAndLocalConstVarsDepMap = DeclDepMap()
        AnalysisGlobalVarsAndLocalConstVarsDependency(initOrder, globalVarsAndLocalConstVarsDepMap)

        let varDepsChecker = VarCirDepsChecker()
        varDepsChecker.InitDependency(globalVarsAndLocalConstVars, globalVarsAndLocalConstVarsDepMap)
        varDepsChecker.DoTarjanSort()
        varDepsChecker.UpdateSccUnit(globalVarsAndLocalConstVarsDepMap)
        let sortedVars = varDepsChecker.GetOrderElement()
        if (varDepsChecker.hasCircularDependency) {
            return initOrder
        }
        return MergeLocalConstVarInitOrder(initOrder, sortedVars)
    }

    private func AnalysisGlobalVarsAndLocalConstVarsDependency(initOrder: ArrayList<FaithfulInitFileVars>,
        globalVarsAndLocalConstVarsDepMap: DeclDepMap): Unit {
        var previous: Option<AstDecl> = None
        for (element in initOrder) {
            for (globalVar in element.vars) {
                if (let Some(previousVar) <- previous) {
                    globalVarsAndLocalConstVarsDepMap.AddDep(globalVar, previousVar)
                }
                previous = globalVar
            }
        }
        for (localConstVar in localConstVars.stableOrderValue) {
            let visited = FaithfulInitDeclSet()
            AnalysisGlocalVarsAndLocalConstVarsDependencyImpl(localConstVar, localConstVar, visited,
                globalVarsAndLocalConstVarsDepMap)
        }
    }

    private func AnalysisGlocalVarsAndLocalConstVarsDependencyImpl(rootDecl: AstDecl, curDecl: AstDecl,
        visited: FaithfulInitDeclSet, globalVarsAndLocalConstVarsDepMap: DeclDepMap): Unit {
        CJC_ASSERT(funcsAndVarsDepMap.Contains(curDecl))
        let directDepsOfCurDecl = funcsAndVarsDepMap.GetDep(curDecl)
        for (dep in directDepsOfCurDecl) {
            if (visited.Contains(dep)) {
                continue
            }
            visited.Add(dep)
            if (dep.astKind == ASTKind.VAR_DECL || dep.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                globalVarsAndLocalConstVarsDepMap.AddDep(rootDecl, dep)
            } else {
                AnalysisGlocalVarsAndLocalConstVarsDependencyImpl(rootDecl, dep, visited,
                    globalVarsAndLocalConstVarsDepMap)
            }
        }
    }

    private func MergeLocalConstVarInitOrder(initOrder: ArrayList<FaithfulInitFileVars>,
        sortedVars: ArrayList<AstDecl>): ArrayList<FaithfulInitFileVars> {
        let finalInitOrder = ArrayList<FaithfulInitFileVars>()
        var sortedIdx: Int64 = 0
        for (pair in initOrder) {
            let fileEntry = FaithfulInitFileVars(pair.file)
            if (pair.vars.isEmpty()) {
                finalInitOrder.add(fileEntry)
                continue
            }

            var originalIdx: Int64 = 0
            while (sortedIdx < sortedVars.size) {
                if (FaithfulInitSameDecl(pair.vars[originalIdx], sortedVars[sortedIdx])) {
                    originalIdx++
                }
                fileEntry.vars.add(sortedVars[sortedIdx])
                sortedIdx++
                if (originalIdx == pair.vars.size) {
                    break
                }
            }
            while (originalIdx < pair.vars.size) {
                fileEntry.vars.add(pair.vars[originalIdx])
                originalIdx++
            }
            finalInitOrder.add(fileEntry)
        }
        if (sortedIdx < sortedVars.size) {
            if (finalInitOrder.isEmpty()) {
                let fileEntry = FaithfulInitFileVars(sortedVars[sortedIdx].curFile.getOrThrow())
                while (sortedIdx < sortedVars.size) {
                    fileEntry.vars.add(sortedVars[sortedIdx])
                    sortedIdx++
                }
                finalInitOrder.add(fileEntry)
            } else {
                let fileEntry = finalInitOrder[finalInitOrder.size - 1]
                while (sortedIdx < sortedVars.size) {
                    fileEntry.vars.add(sortedVars[sortedIdx])
                    sortedIdx++
                }
            }
        }
        return finalInitOrder
    }

    private func CollectDirectDependencies(root: AstDecl, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet, patternOwnerMap: FaithfulInitDeclOwnerMap):
        (ArrayList<AstDecl>, ArrayList<AstDecl>) {
        let dependencies = ArrayList<AstDecl>()
        let localConstVarDeps = ArrayList<AstDecl>()
        let dependencySet = FaithfulInitDeclSet()
        let localConstVarDepSet = FaithfulInitDeclSet()
        AnalysisDepOf(root, dependencies, localConstVarDeps, dependencySet, localConstVarDepSet, candidateSet,
            globalVarSet, patternOwnerMap)
        return (dependencies, localConstVarDeps)
    }

    private func WalkAndCollectDep(root: AstNode, dependencies: ArrayList<AstDecl>,
        localConstVarDeps: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        localConstVarDepSet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet, patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        let visitor = { node: AstNode =>
            if (let Some(expr) <- (node as AstExpr)) {
                if (expr.desugarExpr.isSome()) {
                    var realExpr = expr
                    while (realExpr.desugarExpr.isSome()) {
                        realExpr = realExpr.desugarExpr.getOrThrow()
                    }
                    WalkAndCollectDep(realExpr, dependencies, localConstVarDeps, dependencySet, localConstVarDepSet,
                        candidateSet, globalVarSet, patternOwnerMap)
                    return AstVisitAction.SKIP_CHILDREN
                }
                return VisitExprAction(expr, dependencies, localConstVarDeps, dependencySet, localConstVarDepSet,
                    candidateSet, globalVarSet, patternOwnerMap)
            }
            if (let Some(param) <- (node as AstFuncParam)) {
                if (param.assignment.isSome()) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        WalkAndCollectDep(desugarDecl, dependencies, localConstVarDeps, dependencySet,
                            localConstVarDepSet, candidateSet, globalVarSet, patternOwnerMap)
                    }
                    return AstVisitAction.SKIP_CHILDREN
                }
                return AstVisitAction.WALK_CHILDREN
            }
            if (let Some(arg) <- (node as AstFuncArg)) {
                if (arg.TestAttr(AstAttribute.HAS_INITIAL)) {
                    return AstVisitAction.SKIP_CHILDREN
                }
                return AstVisitAction.WALK_CHILDREN
            }
            if (let Some(funcDecl) <- (node as AstFuncDecl)) {
                if (let Some(manager) <- gim && funcDecl.TestAttr(AstAttribute.GENERIC)) {
                    for (instance in manager.GetInstantiatedDecls(funcDecl)) {
                        WalkAndCollectDep(instance, dependencies, localConstVarDeps, dependencySet,
                            localConstVarDepSet, candidateSet, globalVarSet, patternOwnerMap)
                    }
                }
                return AstVisitAction.WALK_CHILDREN
            }
            return AstVisitAction.WALK_CHILDREN
        }
        AstWalker(root, visitPre: visitor).Walk()
    }

    private func BuildPatternDependencyOwnerMap(): FaithfulInitDeclOwnerMap {
        let out = FaithfulInitDeclOwnerMap()
        for (candidate in globalAndStaticVars) {
            if (let Some(varWithPattern) <- (candidate as AstVarWithPatternDecl)) {
                ParseVarWithPatternDecl(varWithPattern, out)
            }
        }
        return out
    }

    private func ParseVarWithPatternDecl(root: AstVarWithPatternDecl, out: FaithfulInitDeclOwnerMap): Unit {
        ParsePattern(root, RequirePattern(root.irrefutablePattern, "global var-with-pattern pattern"), out)
    }

    private func ParsePattern(rootDecl: AstVarWithPatternDecl, pattern: AstPattern,
        out: FaithfulInitDeclOwnerMap): Unit {
        AddPatternDependencyOwners(pattern, rootDecl, out)
    }

    private func AddPatternDependencyOwners(pattern: AstPattern, owner: AstDecl,
        out: FaithfulInitDeclOwnerMap): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                out.Add(varDecl, owner)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                AddPatternDependencyOwners(subPattern, owner, out)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                AddPatternDependencyOwners(subPattern, owner, out)
            }
        }
    }

    private func BuildDeclSet(decls: ArrayList<AstDecl>): FaithfulInitDeclSet {
        let out = FaithfulInitDeclSet()
        for (decl in decls) {
            out.Add(decl)
        }
        return out
    }

    private func VisitExprAction(expr: AstExpr, dependencies: ArrayList<AstDecl>,
        localConstVarDeps: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        localConstVarDepSet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): AstVisitAction {
        if (let Some(callExpr) <- (expr as AstCallExpr)) {
            return CollectDepInCallExpr(callExpr, dependencies, dependencySet, candidateSet, globalVarSet,
                patternOwnerMap)
        }
        if (let Some(member) <- (expr as AstMemberAccess)) {
            if (let Some(target) <- member.target) {
                if (target.astKind == ASTKind.FUNC_DECL) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
                if (target.astKind == ASTKind.VAR_DECL && target.TestAttr(AstAttribute.STATIC)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
                if (AstIsPackageMemberAccess(member) && target.astKind == ASTKind.VAR_DECL) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
            return AstVisitAction.WALK_CHILDREN
        }
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                let hasRefTarget = target.astKind == ASTKind.FUNC_DECL || target.astKind == ASTKind.VAR_DECL
                if (hasRefTarget && target.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                } else if (hasRefTarget && target.IsConst()) {
                    AddDependency(target, localConstVarDeps, localConstVarDepSet, candidateSet, globalVarSet,
                        patternOwnerMap)
                }
            }
            return AstVisitAction.SKIP_CHILDREN
        }
        if (let Some(arrayExpr) <- (expr as AstArrayExpr)) {
            if (let Some(initFunc) <- arrayExpr.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return AstVisitAction.WALK_CHILDREN
        }
        if (let Some(arrayLit) <- (expr as AstArrayLit)) {
            if (let Some(initFunc) <- arrayLit.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return AstVisitAction.WALK_CHILDREN
        }
        if (let Some(litConstExpr) <- (expr as AstLitConstExpr)) {
            return CollectDepInLitConstExpr(litConstExpr, dependencies, dependencySet, candidateSet, globalVarSet,
                patternOwnerMap)
        }
        return AstVisitAction.WALK_CHILDREN
    }

    private func CollectDepInCallExpr(callExpr: AstCallExpr, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): AstVisitAction {
        if (let Some(callee) <- callExpr.resolvedFunction) {
            AddDependency(callee, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
        }
        if (let None <- callExpr.desugarArgs) {
            return AstVisitAction.WALK_CHILDREN
        }
        let argExprs = callExpr.desugarArgs.getOrThrow()
        var argIndex: Int64 = 0
        while (argIndex < argExprs.size) {
            if (argExprs[argIndex].TestAttr(AstAttribute.HAS_INITIAL)) {
                let resolved = callExpr.resolvedFunction ??
                    throw IllegalStateException("faithful GlobalDeclAnalysis default arg call has no resolved function")
                let funcBody = resolved.funcBody ??
                    throw IllegalStateException("faithful GlobalDeclAnalysis default arg function has no body")
                let param = funcBody.paramLists[0].params[argIndex]
                let desugarDecl = param.desugarDecl ??
                    throw IllegalStateException("faithful GlobalDeclAnalysis default arg has no desugar decl")
                AddDependency(desugarDecl, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            argIndex++
        }
        return AstVisitAction.WALK_CHILDREN
    }

    private func CollectDepInLitConstExpr(litConstExpr: AstLitConstExpr, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): AstVisitAction {
        if (litConstExpr.kind == AstLitConstKind.JSTRING || litConstExpr.ref.isNone()) {
            return AstVisitAction.WALK_CHILDREN
        }
        let target = litConstExpr.ref.getOrThrow().ref.target ?? return AstVisitAction.WALK_CHILDREN
        let structDecl = (target as AstStructDecl) ?? return AstVisitAction.WALK_CHILDREN
        if (!litConstExpr.stringValue.isEmpty()) {
            return AstVisitAction.WALK_CHILDREN
        }
        let body = structDecl.body ?? return AstVisitAction.WALK_CHILDREN
        for (decl in body.decls) {
            if (decl.astKind == ASTKind.VAR_DECL && decl.identifier.Val() == "empty" &&
                decl.TestAttr(AstAttribute.STATIC)) {
                AddDependency(decl, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
        }
        return AstVisitAction.WALK_CHILDREN
    }

    private func AnalysisDepOf(rootDecl: AstDecl, dependencies: ArrayList<AstDecl>,
        localConstVarDeps: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        localConstVarDepSet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        WalkAndCollectDep(rootDecl, dependencies, localConstVarDeps, dependencySet, localConstVarDepSet, candidateSet,
            globalVarSet, patternOwnerMap)
        if (let Some(funcDecl) <- (rootDecl as AstFuncDecl)) {
            if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
                if (funcDecl.TestAttr(AstAttribute.STATIC)) {
                    AdditionalAnalysisDepOfStaticInit(funcDecl, dependencies, dependencySet)
                } else {
                    AdditionalAnalysisDepOfNonStaticCtor(funcDecl, dependencies, localConstVarDeps, dependencySet,
                        localConstVarDepSet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
        }
    }

    private func AdditionalAnalysisDepOfNonStaticCtor(funcDecl: AstFuncDecl, dependencies: ArrayList<AstDecl>,
        localConstVarDeps: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        localConstVarDepSet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet,
        globalVarSet: FaithfulInitDeclSet, patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        let funcBody = funcDecl.funcBody ??
            throw IllegalStateException("faithful GlobalDeclAnalysis constructor has no body")
        let parentDecl: AstDecl = if (let Some(parentClassLike) <- funcBody.parentClassLike) {
            parentClassLike
        } else {
            funcBody.parentStruct.getOrThrow()
        }
        for (memberVar in GetNonStaticMemberVars(parentDecl)) {
            if (memberVar.initializer.isSome()) {
                WalkAndCollectDep(memberVar, dependencies, localConstVarDeps, dependencySet, localConstVarDepSet,
                    candidateSet, globalVarSet, patternOwnerMap)
            }
        }
    }

    private func AdditionalAnalysisDepOfStaticInit(staticInit: AstFuncDecl, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet): Unit {
        let parentDecl = staticInit.outerDecl ??
            throw IllegalStateException("faithful GlobalDeclAnalysis static init has no outer decl")
        let staticVars = GetStaticMemberVars(parentDecl)
        let filteredDependencies = ArrayList<AstDecl>()
        let filteredSet = FaithfulInitDeclSet()
        for (dep in dependencies) {
            if (ContainsDecl(staticVars, dep)) {
                continue
            }
            if (filteredSet.Add(dep)) {
                filteredDependencies.add(dep)
            }
        }
        for (staticVar in staticVars) {
            if (DoesStaticInitDependOnStaticVar(staticInit, staticVar) && filteredSet.Add(staticVar)) {
                filteredDependencies.add(staticVar)
            }
        }
        dependencies.clear()
        for (dep in filteredDependencies) {
            dependencies.add(dep)
            dependencySet.Add(dep)
        }
    }

    private func DoesStaticInitDependOnStaticVar(staticInit: AstFuncDecl, staticVar: AstVarDecl): Bool {
        var staticVarInitializerFileId: Option<UInt64> = None
        if (let Some(specific) <- staticVar.specificImplementation) {
            if (let Some(specificStaticVar) <- (specific as AstVarDecl)) {
                if (let Some(initializer) <- specificStaticVar.initializer) {
                    staticVarInitializerFileId = UInt64(initializer.begin.fileID)
                }
            }
        } else if (let Some(initializer) <- staticVar.initializer) {
            staticVarInitializerFileId = UInt64(initializer.begin.fileID)
        }
        let staticInitFileId = UInt64(staticInit.begin.fileID)
        if (let Some(initializerFileId) <- staticVarInitializerFileId) {
            return staticInitFileId != initializerFileId
        }
        return true
    }

    private func GetStaticMemberVars(decl: AstDecl): ArrayList<AstVarDecl> {
        let out = ArrayList<AstVarDecl>()
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL) {
                let varDecl = (member as AstVarDecl).getOrThrow()
                if (varDecl.TestAttr(AstAttribute.STATIC)) {
                    out.add(varDecl)
                }
            }
        }
        return out
    }

    private func GetNonStaticMemberVars(decl: AstDecl): ArrayList<AstVarDecl> {
        let out = ArrayList<AstVarDecl>()
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL) {
                let varDecl = (member as AstVarDecl).getOrThrow()
                if (!varDecl.TestAttr(AstAttribute.STATIC)) {
                    out.add(varDecl)
                }
            }
        }
        return out
    }

    private func ContainsDecl(decls: ArrayList<AstVarDecl>, target: AstDecl): Bool {
        for (decl in decls) {
            if (FaithfulInitSameDecl(decl, target)) {
                return true
            }
        }
        return false
    }

    private func ReplaceCommonDependenciesWithSpecific(dependencies: ArrayList<AstDecl>): Unit {
        var idx: Int64 = 0
        while (idx < dependencies.size) {
            if (let Some(specific) <- dependencies[idx].specificImplementation) {
                dependencies[idx] = specific
            }
            idx++
        }
    }

    private func SaveCJMPDependencies(decl: AstDecl, dependencies: ArrayList<AstDecl>): Unit {
        for (dependency in dependencies) {
            decl.dependencies.add(dependency)
        }
    }

    private func RestoreCJMPDependencies(decl: AstDecl, dependencies: ArrayList<AstDecl>): Unit {
        for (dependencyOpt in decl.dependencies) {
            if (let Some(dependency) <- dependencyOpt) {
                dependencies.add(dependency)
                if (let Some(specific) <- dependency.specificImplementation) {
                    dependencies.add(specific)
                }
            }
        }
    }

    private func MergingSpecific(): Bool {
        return opts.IsCompilingCJMPSpecific()
    }

    private func OutputCHIR(): Bool {
        return opts.outputMode == OutputMode.CHIR
    }

    private func AddDependency(dep: AstDecl, dependencies: ArrayList<AstDecl>, dependencySet: FaithfulInitDeclSet,
        candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        if (let Some(varDecl) <- (dep as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC) && varDecl.initializer.isNone()) {
                if (let Some(outerDecl) <- varDecl.outerDecl) {
                    if (let Some(info) <- staticInitFuncInfoMap.Get(outerDecl)) {
                        let staticInitVar = info.staticInitVar ??
                            throw IllegalStateException("faithful GlobalDeclAnalysis missing static init var")
                        AddDependencyImpl(staticInitVar, dependencies, dependencySet)
                        return
                    }
                }
            }
        }
        let resolvedDep = ResolveVarWithPatternDependency(dep, globalVarSet, patternOwnerMap)
        if (!IsFuncOrVarCandidate(resolvedDep, candidateSet)) {
            return
        }
        AddDependencyImpl(resolvedDep, dependencies, dependencySet)
    }

    private func AddDependencyImpl(depDecl: AstDecl, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet): Unit {
        if (dependencySet.Add(depDecl)) {
            dependencies.add(depDecl)
        }
    }

    private func ResolveVarWithPatternDependency(dep: AstDecl, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): AstDecl {
        if (globalVarSet.Contains(dep)) {
            return dep
        }
        if ((dep as AstVarDecl).isSome()) {
            if (let Some(owner) <- patternOwnerMap.Get(dep)) {
                return owner
            }
        }
        return dep
    }

    private func IsFuncOrVarCandidate(decl: AstDecl, candidateSet: FaithfulInitDeclSet): Bool {
        if (decl.TestAnyAttr(AstAttribute.FOREIGN, AstAttribute.INTRINSIC, AstAttribute.ENUM_CONSTRUCTOR)) {
            return false
        }
        if (decl.TestAttr(AstAttribute.IMPORTED) && !decl.TestAttr(AstAttribute.SRC_IMPORTED)) {
            return false
        }
        return candidateSet.Contains(decl)
    }

    private func IsSrcCodeImportedGlobalDecl(decl: AstDecl): Bool {
        return IsSrcImportedDecl(decl) && !IsLocalVarDecl(decl)
    }

    private func IsSymbolImportedDecl(decl: AstDecl): Bool {
        return decl.TestAttr(AstAttribute.IMPORTED) && !IsSrcImportedDecl(decl)
    }

    private func IsSrcImportedDecl(decl: AstDecl): Bool {
        if (!decl.TestAttr(AstAttribute.IMPORTED)) {
            return false
        }
        if (decl.IsConst()) {
            return true
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (chirOptOverO2 && funcDecl.isFrozen && !funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
                return true
            }
        }
        if (let Some(varDecl) <- (decl as AstVarDecl)) {
            if (varDecl.TestAttr(AstAttribute.STATIC)) {
                if (let Some(outer) <- varDecl.outerDecl) {
                    if (outer.IsNominalDecl()) {
                        for (member in outer.GetMemberDecls()) {
                            if (member.TestAttr(AstAttribute.CONSTRUCTOR) && member.TestAttr(AstAttribute.STATIC) &&
                                IsSrcCodeImportedGlobalDecl(member)) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private func IsLocalVarDecl(decl: AstDecl): Bool {
        return decl.astKind == ASTKind.VAR_DECL && !decl.TestAttr(AstAttribute.STATIC) &&
            !decl.TestAttr(AstAttribute.GLOBAL)
    }

    private func RemoveUselessDefFromCC(pkg: Package, uselessClasses: ArrayList<ClassDef>,
        uselessLambda: ArrayList<Function>): Unit {
        let funcsToRemove = ArrayList<Function>()
        for (lambda in uselessLambda) {
            for (user in lambda.GetUsers()) {
                user.RemoveSelfFromBlock()
            }
            lambda.DestroySelf()
            AddFunctionNoDup(funcsToRemove, lambda)
        }
        for (def in uselessClasses) {
            for (method in def.GetMethods()) {
                for (user in method.GetUsers()) {
                    user.RemoveSelfFromBlock()
                }
                method.DestroySelf()
                AddFunctionNoDup(funcsToRemove, method)
            }
        }
        let newClasses = ArrayList<ClassDef>()
        for (def in pkg.GetClasses()) {
            if (!ContainsClassDef(uselessClasses, def)) {
                newClasses.add(def)
            }
        }
        pkg.SetClasses(newClasses)
        let globalFuncs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (!ContainsFunction(funcsToRemove, fn)) {
                globalFuncs.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(globalFuncs)
    }

    private func ContainsFunction(functions: ArrayList<Function>, target: Function): Bool {
        for (fn in functions) {
            if (fn.nodeId == target.nodeId) {
                return true
            }
        }
        return false
    }

    private func AddFunctionNoDup(functions: ArrayList<Function>, target: Function): Unit {
        if (!ContainsFunction(functions, target)) {
            functions.add(target)
        }
    }

    private func ContainsGlobalVar(vars: ArrayList<GlobalVar>, target: GlobalVar): Bool {
        for (globalVar in vars) {
            if (globalVar.nodeId == target.nodeId) {
                return true
            }
        }
        return false
    }

    private func ContainsClassDef(classes: ArrayList<ClassDef>, target: ClassDef): Bool {
        for (classDef in classes) {
            if (classDef.nodeId == target.nodeId) {
                return true
            }
        }
        return false
    }

    private func CreatePackageInit(nodeInitOrder!: ArrayList<FaithfulInitFileVars>, suffix!: String): Unit {
        let (packageInit, initBlock, createdPackageInit) = if (suffix == "_literal") {
            PreparePackageLiteralInit()
        } else {
            PreparePackageInit()
        }
        packageInit.EnableAttr(Attribute.PUBLIC)
        if (createdPackageInit && suffix != "_literal") {
            AddGenericInstantiatedInit(initBlock)
        }
        for (fileVars in nodeInitOrder) {
            if (suffix == "_literal") {
                if (fileVars.vars.isEmpty()) {
                    continue
                }
                if (IsImportedInitEntry(fileVars)) {
                    TranslateImportedFileLiteralInitializer(fileVars, initBlock)
                    continue
                }
                if (IsSymbolImportedDecl(fileVars.vars[0])) {
                    continue
                }
                if (let Some(fileLiteralInit) <- TranslateFileLiteralInitializer(fileVars)) {
                    InsertInitializerIntoPackageInitializer(fileLiteralInit, packageInit)
                }
            } else {
                if (!fileVars.vars.isEmpty() || kind == IncreKind.INCR) {
                    if (!fileVars.vars.isEmpty() && IsSymbolImportedDecl(fileVars.vars[0])) {
                        continue
                    }
                    if (let Some(fileInit) <- TranslateFileInitializer(fileVars)) {
                        InsertInitializerIntoPackageInitializer(fileInit, packageInit)
                    }
                }
            }
        }
        if (initBlock.GetTerminator().isNone()) {
            builder.CreateExit(None, initBlock)
        }
    }

    private func PreparePackageInit(): (Function, Block, Bool) {
        let pkg = CurrentPackage()
        if (let Some(packageInit) <- pkg.GetPackageInitFunc()) {
            let curBlock = DropExitNodeOfInitializer(packageInit)
            let importsInitFunc = GetImportsInitFunc("")
            UpdateImportsInit(importsInitFunc, "")
            return (packageInit, curBlock, false)
        }
        let packageInit = GeneratePackageInitBase("")
        pkg.SetPackageInitFunc(packageInit)
        let curBlock = GetBlockWithInitializers(packageInit)
        let importsInitFunc = CreateImportsInitFunc("")
        InsertInitializerIntoPackageInitializer(importsInitFunc, packageInit)
        UpdateImportsInit(importsInitFunc, "")
        return (packageInit, curBlock, true)
    }

    private func PreparePackageLiteralInit(): (Function, Block, Bool) {
        let pkg = CurrentPackage()
        if (let Some(packageLiteralInit) <- pkg.GetPackageLiteralInitFunc()) {
            let curBlock = DropExitNodeOfInitializer(packageLiteralInit)
            let importsInitFunc = GetImportsInitFunc("_literal")
            UpdateImportsInit(importsInitFunc, "_literal")
            return (packageLiteralInit, curBlock, false)
        }
        let packageLiteralInit = GeneratePackageInitBase("_literal")
        pkg.SetPackageLiteralInitFunc(packageLiteralInit)
        let curBlock = GetBlockWithInitializers(packageLiteralInit)
        let importsInitFunc = CreateImportsInitFunc("_literal")
        InsertInitializerIntoPackageInitializer(importsInitFunc, packageLiteralInit)
        UpdateImportsInit(importsInitFunc, "_literal")
        return (packageLiteralInit, curBlock, true)
    }

    private func GeneratePackageInitBase(suffix: String): Function {
        let pkg = CurrentPackage()
        let packageInit = CreateTranslator().CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix),
            PackageInitFuncName(pkg.GetName(), suffix), "", pkg.GetName(), BasicLinkage.EXTERNAL,
            INVALID_LOCATION, false)
        let boolTy = builder.context.GetBoolTy()
        let entry = RequireEntryBlock(packageInit)
        let initFlag = CreatePackageInitOnceFlag(if (suffix.isEmpty()) {
            "$has_applied_pkg_init_func"
        } else {
            "has_invoked_pkg_init_literal"
        })
        let flagRef = RequireResult(builder.CreateLoad(boolTy, initFlag, entry))
        let body = packageInit.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR package init function has no body")
        let returnBlock = builder.CreateBlock(body)
        let applyInitFuncBlock = builder.CreateBlock(body)
        builder.CreateBranch(flagRef, returnBlock, applyInitFuncBlock, entry)
        builder.CreateExit(None, returnBlock)
        applyInitFuncBlock.EnableAttr(Attribute.INITIALIZER)
        let trueLit = RequireResult(builder.CreateConstant(boolTy, BoolLiteral(true), applyInitFuncBlock))
        builder.CreateStore(trueLit, initFlag, applyInitFuncBlock)
        packageInitializerBlocks[packageInit.nodeId] = applyInitFuncBlock
        return packageInit
    }

    private func CreatePackageInitOnceFlag(name: String): GlobalVar {
        let pkg = CurrentPackage()
        if (let Some(existing) <- pkg.TryGetGlobalVar(GLOBAL_VALUE_PREFIX + name)) {
            return existing
        }
        let boolTy = builder.context.GetBoolTy()
        let initFlag = builder.CreateGlobalVar(builder.context.GetRefTy(boolTy), name,
            srcCodeIdentifier: name, rawMangledName: "", packageName: pkg.GetName())
        initFlag.EnableAttr(Attribute.NO_REFLECT_INFO)
        initFlag.EnableAttr(Attribute.COMPILER_ADD)
        initFlag.EnableAttr(Attribute.INITIALIZER)
        initFlag.EnableAttr(Attribute.NO_DEBUG_INFO)
        initFlag.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        initFlag.SetInitializer(builder.CreateLiteralValue(BoolLiteral(false), boolTy))
        return initFlag
    }

    private func CreateImportsInitFunc(suffix: String): Function {
        let pkg = CurrentPackage()
        let importsInit = CreateTranslator().CreateEmptyGVInitFunc(
            PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"),
            PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"), "", pkg.GetName(), BasicLinkage.EXTERNAL,
            INVALID_LOCATION, false)
        importsInit.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        let entry = RequireEntryBlock(importsInit)
        entry.EnableAttr(Attribute.INITIALIZER)
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return importsInit
    }

    private func GetImportsInitFunc(suffix: String): Function {
        let pkg = CurrentPackage()
        let initializerName = PackageInitFuncName(pkg.GetName(), suffix + "_importsInit")
        return pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + initializerName) ??
            throw IllegalStateException("faithful AST2CHIR missing imports init func: " + initializerName)
    }

    private func UpdateImportsInit(importsInitFunc: Function, suffix: String): Unit {
        let block = DropExitNodeOfInitializer(importsInitFunc)
        for (importedPackage in DirectImportedPackages()) {
            if (importedPackage.isMacroPackage) {
                continue
            }
            let pkgName = importedPackage.fullPackageName
            let initFuncName = PackageInitFuncName(pkgName, suffix)
            if (let Some(existing) <- CurrentPackage().TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + initFuncName)) {
                if (existing.TestAttr(Attribute.DESERIALIZED) ||
                    existing.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                    continue
                }
            }
            let initFuncTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy())
            let attrs = AttributeInfo()
            attrs.Enable(Attribute.INITIALIZER)
            let fn = builder.CreateFunction(initFuncTy, initFuncName,
                srcCodeIdentifier: initFuncName, rawMangledName: "", packageName: pkgName)
            fn.EnableAttr(Attribute.IMPORTED)
            fn.AppendAttributeInfo(attrs)
            fn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
            fn.EnableAttr(Attribute.PUBLIC)
            InsertInitializerIntoPackageInitializer(fn, importsInitFunc)
        }
        if (block.GetTerminator().isNone()) {
            builder.CreateExit(None, block)
        }
    }

    private func InsertInitializerIntoPackageInitializer(initFn: Function, packageInit: Function): Unit {
        let block = GetBlockWithInitializers(packageInit)
        if (initFn.TestAttr(Attribute.DESERIALIZED) && packageInit.TestAttr(Attribute.DESERIALIZED)) {
            if (let Some(initCallExpr) <- FindApplyIn(block, initFn)) {
                let expressions = block.GetExpressions()
                if (!expressions.isEmpty()) {
                    let lastExpr = expressions[expressions.size - 1]
                    if (initCallExpr.nodeId != lastExpr.nodeId) {
                        initCallExpr.MoveAfter(lastExpr)
                    }
                }
            } else {
                let trans = CreateTranslator()
                trans.SetCurrentBlock(block)
                let _ = trans.CreateAndAppendGVInitFuncCall(initFn)
            }
            return
        }
        let trans = CreateTranslator()
        trans.SetCurrentBlock(block)
        let _ = trans.CreateAndAppendGVInitFuncCall(initFn)
    }

    private func FindApplyIn(block: Block, applyCallee: Function): Option<Apply> {
        for (expression in block.GetExpressions()) {
            if (let Some(apply) <- (expression as Apply)) {
                if (apply.GetCallee().nodeId == applyCallee.nodeId) {
                    return apply
                }
            }
        }
        return None
    }

    private func AddGenericInstantiatedInit(block: Block): Unit {
        let callContext = IntrisicCallContext(kind: IntrinsicKind.PREINITIALIZE)
        builder.CreateIntrinsic(builder.context.GetUnitTy(), callContext, block)
    }

    private func DropExitNodeOfInitializer(fn: Function): Block {
        let block = GetBlockWithInitializers(fn)
        if (let Some(term) <- block.GetTerminator()) {
            term.RemoveSelfFromBlock()
        }
        return block
    }

    private func GetBlockWithInitializers(fn: Function): Block {
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocks()) {
                if (block.TestAttr(Attribute.INITIALIZER)) {
                    return block
                }
            }
        }
        if (let Some(block) <- packageInitializerBlocks.get(fn.nodeId)) {
            return block
        }
        return RequireEntryBlock(fn)
    }

    private func TryGetFileInitializer(file: AstFile, suffix: String): Option<Function> {
        let initializerName = FileInitFuncName(file, suffix)
        return CurrentPackage().TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + initializerName)
    }

    private func RemoveInitializerForVarDecl(varDecl: AstVarDecl, fileInit: Function): Unit {
        let declInitName = GLOBAL_VALUE_PREFIX + GlobalVarInitFuncName(varDecl)
        let body = fileInit.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR file init has no body")
        let blocks = body.GetBlocks()
        if (blocks.isEmpty()) {
            return
        }
        let blockWithInitializers = blocks[blocks.size - 1]
        for (expr in blockWithInitializers.GetExpressions()) {
            if (let Some(apply) <- (expr as Apply)) {
                let initFunc = apply.GetCallee()
                CJC_ASSERT(initFunc.TestAttr(Attribute.INITIALIZER))
                if (initFunc.GetIdentifier() == declInitName) {
                    expr.RemoveSelfFromBlock()
                    return
                }
            }
        }
    }

    private func RemoveCommonInitializersReplacedWithSpecific(fileInit: Function,
        decls: ArrayList<AstDecl>): Unit {
        for (decl in decls) {
            if (decl.IsCommonMatchedWithSpecific()) {
                RemoveInitializerForVarDecl(RequireVarDecl(decl), fileInit)
            }
        }
    }

    private func TranslateFileInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        if (let Some(fileInit) <- TryGetFileInitializer(fileVars.file, "")) {
            CJC_ASSERT(fileInit.TestAttr(Attribute.INITIALIZER))
            RemoveCommonInitializersReplacedWithSpecific(fileInit, fileVars.vars)
            return fileInit
        }
        if (!fileVars.vars.isEmpty() && IsSymbolImportedDecl(fileVars.vars[0])) {
            return None
        }
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (let Some(initFunc) <- TranslateSingleInitializer(varDecl)) {
                    initFunc.SetFeatures(fileVars.file.GetFeatures())
                    initFuncs.add(initFunc)
                }
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                if (let Some(initFunc) <- TranslateVarWithPatternInitializer(varWithPattern)) {
                    initFunc.SetFeatures(fileVars.file.GetFeatures())
                    initFuncs.add(initFunc)
                }
            }
        }
        let trans = CreateTranslator()
        let fileInit = trans.CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, ""),
            FileInitFuncName(fileVars.file, ""), "", FileOwnerPackageName(fileVars.file), BasicLinkage.INTERNAL,
            trans.TranslateFileLocation(fileVars.file.begin.fileID), false)
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            let _ = trans.CreateAndAppendGVInitFuncCall(initFunc)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        if (initFuncs.isEmpty()) {
            fileInit.DisableAttr(Attribute.NO_INLINE)
        }
        return fileInit
    }

    private func IsImportedInitEntry(fileVars: FaithfulInitFileVars): Bool {
        if (fileVars.vars.isEmpty()) {
            return false
        }
        return fileVars.vars[0].TestAttr(AstAttribute.IMPORTED)
    }

    private func TranslateImportedFileLiteralInitializer(fileVars: FaithfulInitFileVars, block: Block): Unit {
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (varDecl.IsCommonOrSpecific()) {
                    continue
                }
                if (NeedVarLiteralInitFunc(varDecl)) {
                    StoreLiteralInitializerInBlock(varDecl, block)
                }
            }
        }
    }

    private func StoreLiteralInitializerInBlock(varDecl: AstVarDecl, block: Block): Unit {
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        let literal = TranslateLiteralValue(litExpr)
        let value = RequireResult(builder.CreateConstant(chirType.TranslateType(RequireAstTy(varDecl)), literal, block))
        builder.CreateStore(value, globalVar, block)
    }

    private func TranslateFileLiteralInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        let varsToGenInit = ArrayList<AstVarDecl>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (NeedVarLiteralInitFunc(varDecl)) {
                    varsToGenInit.add(varDecl)
                }
            }
        }
        if (varsToGenInit.isEmpty()) {
            return None
        }
        let trans = CreateTranslator()
        let fileInit = trans.CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, "_literal"),
            FileInitFuncName(fileVars.file, "_literal"), "", FileOwnerPackageName(fileVars.file),
            BasicLinkage.INTERNAL, trans.TranslateFileLocation(fileVars.file.begin.fileID), false)
        fileInit.DisableAttr(Attribute.NO_INLINE)
        fileInit.SetDebugLocation(INVALID_LOCATION)
        let entry = RequireEntryBlock(fileInit)
        for (varDecl in varsToGenInit) {
            StoreLiteralInitializerInBlock(varDecl, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func TranslateSingleInitializer(varDecl: AstVarDecl): Option<Function> {
        if (!CanInitBeGenerated(varDecl)) {
            return None
        }
        if (varDecl.specificImplementation.isSome()) {
            return None
        }
        if (let Some(initFunc) <- CurrentPackage().TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + GlobalVarInitFuncName(varDecl))) {
            if (!varDecl.TestAttr(AstAttribute.SPECIFIC)) {
                return initFunc
            }
        }
        if (!NeedInitGlobalVarByInitFunc(varDecl)) {
            SetLiteralInitializer(varDecl)
            return None
        }
        if (IsIncrementalNoChange(varDecl) && !IsSrcCodeImportedGlobalDecl(varDecl)) {
            if (varDecl.identifier.Val() == STATIC_INIT_VAR) {
                return TranslateInitializerToFunction(varDecl, suffix: "")
            }
            return TranslateIncrementalNoChangeVar(varDecl)
        }
        return TranslateInitializerToFunction(varDecl, suffix: "")
    }

    private func CanInitBeGenerated(varDecl: AstVarDecl): Bool {
        return varDecl.initializer.isSome()
    }

    private func IsIncrementalNoChange(varDecl: AstVarDecl): Bool {
        return kind == IncreKind.INCR && !varDecl.toBeCompiled
    }

    private func TranslateIncrementalNoChangeVar(varDecl: AstVarDecl): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy())
        let initFn = builder.CreateFunction(funcTy, GlobalVarInitFuncName(varDecl),
            srcCodeIdentifier: "gv$_" + varDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(varDecl),
            packageName: EffectivePackageName(varDecl))
        initFn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        initFn.EnableAttr(Attribute.IMPORTED)
        initFn.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
        }
        return initFn
    }

    private func SetLiteralInitializer(varDecl: AstVarDecl): Unit {
        let _ = NeedVarLiteralInitFunc(varDecl)
    }

    private func NeedVarLiteralInitFunc(varDecl: AstVarDecl): Bool {
        if (varDecl.initializer.isNone() || NeedInitGlobalVarByInitFunc(varDecl)) {
            return false
        }
        if (varDecl.TestAttr(AstAttribute.COMMON) && varDecl.specificImplementation.isSome()) {
            return false
        }
        if (IsIncrementalNoChange(varDecl)) {
            return false
        }
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        globalVar.SetInitializer(TranslateLitConstant(litExpr, RequireAstTy(litExpr)))
        if (!varDecl.isVar) {
            return false
        }
        return true
    }

    private func TranslateVarWithPatternInitializer(decl: AstVarWithPatternDecl): Option<Function> {
        if (decl.initializer.isNone()) {
            return None
        }
        let pattern = RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern")
        if ((pattern as AstTuplePattern).isSome() || (pattern as AstEnumPattern).isSome() ||
            (pattern as AstWildcardPattern).isSome()) {
            return Some(CreateGlobalVarWithPatternInitFunc(decl))
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func TranslateInitializerToFunction(varDecl: AstVarDecl, suffix!: String): Function {
        let trans = CreateTranslator()
        let loc = if (varDecl.IsConst()) { INVALID_LOCATION } else { trans.TranslateLocation(varDecl) }
        let initFn = trans.CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl),
            "gv$_" + varDecl.identifier.Val() + suffix, EffectiveRawMangledName(varDecl),
            EffectivePackageName(varDecl), BasicLinkage.INTERNAL, loc, varDecl.IsConst())
        if (varDecl.IsConst()) {
            if (suffix != "$literal") {
                initFuncsForConstVar.add(initFn)
            }
        }
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        if (suffix != "$literal") {
            globalVar.SetInitFunc(initFn)
        }
        trans.TranslateInitializerToFunctionImpl(initFn, varDecl, globalVar)
        return initFn
    }

    private func CreateGlobalVarWithPatternInitFunc(decl: AstVarWithPatternDecl): Function {
        let trans = CreateTranslator()
        let initFn = trans.CreateEmptyGVInitFunc(GlobalVarWithPatternInitFuncName(decl),
            GlobalVarWithPatternInitSrcName(decl), EffectiveRawMangledName(decl), EffectivePackageName(decl),
            BasicLinkage.INTERNAL, trans.TranslateLocation(decl), decl.IsConst())
        if (decl.IsConst()) {
            initFuncsForConstVar.add(initFn)
        }
        let varDecls = ArrayList<AstVarDecl>()
        FlattenGlobalVarWithPatternDecl(RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern"),
            varDecls)
        for (varDecl in varDecls) {
            RequireGlobalVar(globalCache.Get(varDecl)).SetInitFunc(initFn)
        }
        trans.TranslateGlobalVarWithPatternInitializer(initFn, decl)
        return initFn
    }

    private func NeedInitGlobalVarByInitFunc(varDecl: AstVarDecl): Bool {
        if (let None <- varDecl.initializer) {
            return false
        }
        if (varDecl.IsCommonOrSpecific()) {
            return true
        }
        let initExpr = RequireExpr(varDecl.initializer, "global variable initializer")
        if (IsSimpleLiteralValue(initExpr)) {
            if (let Some(litExpr) <- (Translator.GetDesugaredExpr(initExpr) as AstLitConstExpr)) {
                let declTy = chirType.TranslateType(RequireAstTy(varDecl))
                let initTy = chirType.TranslateType(RequireAstTy(initExpr))
                return !declTy.IsEqual(initTy)
            }
        }
        return true
    }

    private func IsSimpleLiteralValue(node: AstExpr): Bool {
        let realNode = Translator.GetDesugaredExpr(node)
        if (realNode.astKind != ASTKind.LIT_CONST_EXPR) {
            return false
        }
        let realExpr = (realNode as AstExpr) ??
            throw IllegalStateException("faithful AST2CHIR simple literal expected expr")
        let realTy = RequireAstTy(realExpr)
        return match (realTy.kind) {
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT64 | AstTypeKind.TYPE_IDEAL_FLOAT |
                AstTypeKind.TYPE_FLOAT32 | AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 |
                AstTypeKind.TYPE_UINT32 | AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE |
                AstTypeKind.TYPE_INT8 | AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 |
                AstTypeKind.TYPE_INT64 | AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT |
                AstTypeKind.TYPE_RUNE | AstTypeKind.TYPE_BOOLEAN => true
            case AstTypeKind.TYPE_STRUCT => RequireAstTy(node).IsString()
            case _ => false
        }
    }

    private func TranslateLiteralValue(expr: AstLitConstExpr): LiteralValue {
        let kind = RequireAstTy(expr).kind
        return match (kind) {
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT64 | AstTypeKind.TYPE_IDEAL_FLOAT =>
                FloatLiteral(expr.constNumValue.asFloat.value)
            case AstTypeKind.TYPE_FLOAT32 =>
                let stringVal = expr.stringValue.replace("_", "")
                var value = 0.0
                try (cStringVal = unsafe { LibC.mallocCString(stringVal) }.asResource()) {
                    value = unsafe { CJSelfhostStrtoldToFloat32(cStringVal.value) }
                }
                FloatLiteral(value)
            case AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 | AstTypeKind.TYPE_UINT32 |
                AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE =>
                IntLiteral(expr.constNumValue.asInt.Uint64())
            case AstTypeKind.TYPE_INT8 | AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 |
                AstTypeKind.TYPE_INT64 | AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT =>
                IntLiteral(expr.constNumValue.asInt.`Int64`())
            case AstTypeKind.TYPE_RUNE => RuneLiteral(Rune(expr.codepoint[0]))
            case AstTypeKind.TYPE_BOOLEAN => BoolLiteral(expr.stringValue == "true")
            case AstTypeKind.TYPE_STRUCT =>
                CJC_ASSERT(expr.kind == AstLitConstKind.STRING)
                StringLiteral(expr.stringValue)
            case AstTypeKind.TYPE_UNIT =>
                CJC_ABORT()
                UnitLiteral()
            case _ =>
                CJC_ABORT()
                UnitLiteral()
        }
    }

    private func TranslateLitConstant(expr: AstLitConstExpr, realTy: AstTy): LiteralValue {
        let chirTyToTrans = chirType.TranslateType(realTy)
        return match (realTy.kind) {
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT64 | AstTypeKind.TYPE_IDEAL_FLOAT =>
                builder.CreateLiteralValue(FloatLiteral(expr.constNumValue.asFloat.value), chirTyToTrans)
            case AstTypeKind.TYPE_FLOAT32 =>
                let stringVal = expr.stringValue.replace("_", "")
                var value = 0.0
                try (cStringVal = unsafe { LibC.mallocCString(stringVal) }.asResource()) {
                    value = unsafe { CJSelfhostStrtoldToFloat32(cStringVal.value) }
                }
                builder.CreateLiteralValue(FloatLiteral(value), chirTyToTrans)
            case AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 | AstTypeKind.TYPE_UINT32 |
                AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE =>
                builder.CreateLiteralValue(
                    IntLiteral(UInt64LiteralBitsToInt64(expr.constNumValue.asInt.Uint64())), chirTyToTrans)
            case AstTypeKind.TYPE_INT8 | AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 |
                AstTypeKind.TYPE_INT64 | AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT =>
                builder.CreateLiteralValue(IntLiteral(expr.constNumValue.asInt.`Int64`()), chirTyToTrans)
            case AstTypeKind.TYPE_RUNE =>
                builder.CreateLiteralValue(RuneLiteral(Rune(expr.codepoint[0])), chirTyToTrans)
            case AstTypeKind.TYPE_BOOLEAN =>
                builder.CreateLiteralValue(BoolLiteral(expr.stringValue == "true"), chirTyToTrans)
            case AstTypeKind.TYPE_STRUCT =>
                CJC_ASSERT(expr.kind == AstLitConstKind.STRING)
                builder.CreateLiteralValue(StringLiteral(expr.stringValue), chirTyToTrans)
            case AstTypeKind.TYPE_UNIT =>
                CJC_ABORT()
                builder.CreateLiteralValue(UnitLiteral(), chirTyToTrans)
            case _ =>
                CJC_ABORT()
                builder.CreateLiteralValue(UnitLiteral(), chirTyToTrans)
        }
    }

    private func TranslateIntegerLiteralValue(expr: AstLitConstExpr): IntLiteral {
        let astTy = RequireAstTy(expr)
        let kind = astTy.kind
        if (AstTypeKindInRange(kind, AstTypeKind.TYPE_UINT8, AstTypeKind.TYPE_UINT64) ||
            kind == AstTypeKind.TYPE_UINT_NATIVE) {
            return IntLiteral(UInt64LiteralBitsToInt64(expr.constNumValue.asInt.Uint64()))
        }
        return IntLiteral(expr.constNumValue.asInt.`Int64`())
    }

    private func UInt64LiteralBitsToInt64(value: UInt64): Int64 {
        if (value <= UInt64(Int64.Max)) {
            return Int64(value)
        }
        return -Int64(UInt64.Max - value) - 1
    }

    private func RequireResult(expr: Expression): LocalVar {
        return expr.GetResult() ??
            throw IllegalStateException("faithful AST2CHIR expected expression result")
    }

    private func DirectImportedPackages(): ArrayList<AstPackage> {
        return directImportedPackages
    }

    private func PackageInitFuncName(pkgName: String, suffix: String): String {
        let specialName = if (suffix == "_literal") {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
        } else if (suffix == "_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION
        } else if (suffix == "_literal_importsInit") {
            FAITHFUL_SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION
        } else {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_PACKAGE_INIT_PREFIX +
            FaithfulOptPackageName(pkgName) + specialName + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX +
            FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FaithfulOptPackageName(pkgName: String): String {
        if (let Some(shortName) <- FaithfulStdPackageMangle(pkgName)) {
            return shortName
        }
        return "${pkgName.size}${pkgName}"
    }

    // CHIR cannot import the mangle package here because mangle already depends on CHIR.
    private func FaithfulStdPackageMangle(pkgName: String): Option<String> {
        return match (pkgName) {
            case "std.ad" => "aa"
            case "std.sync" => "ab"
            case "std.collection" => "ac"
            case "std.deriving" => "ad"
            case "std.database" => "ae"
            case "std.net" => "af"
            case "std.chirad" => "ag"
            case "std.io" => "ah"
            case "std.convert" => "ai"
            case "std.ffi" => "aj"
            case "std.argopt" => "ak"
            case "std.objectpool" => "al"
            case "std.reflect" => "am"
            case "std.fs" => "an"
            case "std.runtime" => "ao"
            case "std.overflow" => "ap"
            case "std.unittest" => "aq"
            case "std.binary" => "ar"
            case "std.unicode" => "as"
            case "std.core" => "at"
            case "std.console" => "au"
            case "std.random" => "av"
            case "std.sort" => "aw"
            case "std.ast" => "ax"
            case "std.env" => "ay"
            case "std.process" => "ba"
            case "std.time" => "bb"
            case "std.regex" => "bc"
            case "std.posix" => "bd"
            case "std.crypto" => "be"
            case "std.ref" => "bf"
            case "std.math" => "bg"
            case "std.collection.concurrent" => "bh"
            case "std.collection.concurrent.native" => "bi"
            case "std.deriving.impl" => "bj"
            case "std.deriving.builtins" => "bk"
            case "std.deriving.api" => "bl"
            case "std.deriving.resolve" => "bm"
            case "std.database.sql" => "bn"
            case "std.net.native" => "bo"
            case "std.convert.native" => "bq"
            case "std.objectpool.native" => "bs"
            case "std.fs.native" => "bt"
            case "std.runtime.native" => "bu"
            case "std.unittest.mock" => "bv"
            case "std.unittest.testmacro" => "bw"
            case "std.unittest.prop_test" => "bx"
            case "std.unittest.common" => "by"
            case "std.unittest.native" => "ca"
            case "std.unittest.diff" => "cb"
            case "std.unittest.mock.mockmacro" => "cc"
            case "std.unittest.mock.internal" => "cd"
            case "std.core.native" => "ce"
            case "std.random.native" => "cf"
            case "std.ast.native" => "cg"
            case "std.env.native" => "ch"
            case "std.process.native" => "ci"
            case "std.time.native" => "cj"
            case "std.regex.native" => "ck"
            case "std.posix.native" => "cl"
            case "std.crypto.digest" => "cm"
            case "std.crypto.cipher" => "cn"
            case "std.math.numeric" => "co"
            case "std.math.native" => "cp"
            case "std.math.numeric.native" => "cq"
            case _ => None
        }
    }

    private func FileInitFuncName(file: AstFile, suffix: String): String {
        let specialName = if (suffix.isEmpty()) {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_FUNCTION
        } else {
            FAITHFUL_SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
        }
        let fileId = if (FaithfulIsHashableFileName(file.fileName)) {
            FaithfulHashToBase62(file.fileName)
        } else {
            FaithfulFileNameWithoutExtension(file.fileName) + "$"
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_FILE_INIT_PREFIX +
            FaithfulOptPackageName(FileOwnerPackageName(file)) + FAITHFUL_MANGLE_FILE_ID_PREFIX + fileId +
            specialName + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FileOwnerPackageName(file: AstFile): String {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
        return CurrentPackage().GetName()
    }

    private func GlobalVarInitFuncName(varDecl: AstVarDecl): String {
        return GlobalVarInitFuncNameFromMangledName(varDecl.mangledName)
    }

    private func GlobalVarWithPatternInitFuncName(decl: AstVarWithPatternDecl): String {
        return GlobalVarInitFuncNameFromMangledName(decl.mangledName)
    }

    private func GlobalVarInitFuncNameFromMangledName(mangledName: String): String {
        let prefix = FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_NESTED_PREFIX
        if (!FaithfulStartsWith(mangledName, prefix) || !FaithfulEndsWith(mangledName, FAITHFUL_MANGLE_SUFFIX) ||
            mangledName.size <= prefix.size + FAITHFUL_MANGLE_SUFFIX.size) {
            throw IllegalArgumentException("faithful AST2CHIR global var init requires nested mangled name: " +
                mangledName)
        }
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX +
            mangledName[prefix.size..mangledName.size - FAITHFUL_MANGLE_SUFFIX.size] +
            FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func GlobalVarWithPatternInitSrcName(decl: AstVarWithPatternDecl): String {
        let pattern = RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern")
        if ((pattern as AstTuplePattern).isSome()) {
            return GVInitFuncNameForName("tuple_pattern", EffectivePackageName(decl)) + FlattenPatternName(pattern)
        }
        if ((pattern as AstEnumPattern).isSome()) {
            return GVInitFuncNameForName("enum_pattern", EffectivePackageName(decl)) + FlattenPatternName(pattern)
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return GVInitFuncNameForName(FAITHFUL_GV_INIT_WILDCARD_PATTERN + pattern.begin.line.toString() + "_" +
                pattern.begin.column.toString(), EffectivePackageName(decl))
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func GVInitFuncNameForName(gvName: String, pkgName: String): String {
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_GLOBAL_VARIABLE_INIT_PREFIX +
            FaithfulOptPackageName(pkgName) + FaithfulMangleName(gvName) + FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX +
            FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func FlattenPatternName(pattern: AstPattern): String {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            let varDecl = varPattern.varDecl ??
                throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
            return ":" + varDecl.identifier.Val()
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            var out = ""
            for (subPattern in tuplePattern.patterns) {
                out += FlattenPatternName(subPattern)
            }
            return out
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            var out = ""
            for (subPattern in enumPattern.patterns) {
                out += FlattenPatternName(subPattern)
            }
            return out
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return ":_"
        }
        return ""
    }

    private func RequireEntryBlock(fn: Function): Block {
        return fn.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR initializer function has no entry block")
    }

    private func IsLocalConstFuncInStaticMember(funcDecl: AstFuncDecl): Bool {
        if (!funcDecl.isConst || !IsLocalFunc(funcDecl)) {
            return false
        }
        let outerDecl = GetOuterDecl(funcDecl) ??
            throw IllegalStateException("faithful local const function has no outer declaration")
        return outerDecl.TestAttr(AstAttribute.STATIC)
    }

    private func TranslateFunctionGenericUpperBounds(funcDecl: AstFuncDecl): Unit {
        let funcBody = funcDecl.funcBody ??
            throw IllegalStateException("faithful generic function has no body")
        if (let Some(generic) <- funcBody.generic) {
            for (typeParam in generic.typeParameters) {
                let _ = chirType.TranslateType(RequireAstTy(typeParam))
            }
            for (typeParam in generic.typeParameters) {
                chirType.FillGenericArgType((RequireAstTy(typeParam) as AstGenericsTy).getOrThrow())
            }
        }
    }

    private func SetFuncAttributeAndLinkageType(funcDecl: AstFuncDecl, fn: Function): Unit {
        fn.AppendAttributeInfo(BuildAttr(funcDecl.GetAttrs()))
        if (funcDecl.HasAnno(AstAnnotationKind.NO_HEAP_ALLOC)) { fn.EnableAttr(Attribute.NO_HEAP_ALLOC) }
        if (funcDecl.HasAnno(AstAnnotationKind.NO_WRITE_BARRIER)) { fn.EnableAttr(Attribute.NO_WRITE_BARRIER) }
        if (funcDecl.HasAnno(AstAnnotationKind.NO_WRITE_BARRIER_REC)) {
            fn.EnableAttr(Attribute.NO_WRITE_BARRIER_REC)
        }
        if (funcDecl.HasAnno(AstAnnotationKind.NO_STACK_GROW)) { fn.EnableAttr(Attribute.NO_STACK_GROW) }
        if (funcDecl.HasAnno(AstAnnotationKind.SYSTEM_STACK)) { fn.EnableAttr(Attribute.SYSTEM_STACK) }
        if (funcDecl.isConst) {
            fn.EnableAttr(Attribute.CONST)
        }
        if (IsLocalConstFuncInStaticMember(funcDecl)) {
            fn.DisableAttr(Attribute.STATIC)
        }
        if (IsStaticInit(funcDecl)) {
            fn.DisableAttr(Attribute.STATIC)
            fn.DisableAttr(Attribute.PRIVATE)
            fn.EnableAttr(Attribute.INTERNAL)
        }
        if (kind == IncreKind.INCR && !funcDecl.toBeCompiled) {
            fn.EnableAttr(Attribute.NON_RECOMPILE)
            fn.EnableAttr(Attribute.IMPORTED)
        }
        if (funcDecl.TestAttr(AstAttribute.IN_EXTEND) || funcDecl.TestAttr(AstAttribute.UNSAFE) ||
            funcDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED) || !funcDecl.TestAttr(AstAttribute.PUBLIC)) {
            fn.EnableAttr(Attribute.NO_REFLECT_INFO)
        }
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY) || funcDecl.mangledName == USER_MAIN_MANGLED_NAME ||
            FaithfulStartsWith(funcDecl.mangledName, "rt$")) {
            fn.EnableAttr(Attribute.NO_INLINE)
        }
        if (funcDecl.TestAttr(AstAttribute.FOREIGN)) {
            fn.EnableAttr(Attribute.IMPORTED)
        }
        fn.SetLinkTypeInfo(GetFuncLinkage(opts, funcDecl))
        fn.SetFuncKind(GetFuncKindFromAST(funcDecl))
        if (fn.GetFuncKind() == FuncKind.DEFAULT_PARAMETER_FUNC) {
            let ownerFunc = funcDecl.ownerFunc ??
                throw IllegalStateException("faithful default parameter function has no owner")
            fn.SetParamDftValHostFunc((globalCache.Get(ownerFunc) as Function).getOrThrow())
        }
        fn.SetFastNative(funcDecl.isFastNative)
    }

    private func CreateFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        if (funcDecl.TestAttr(AstAttribute.GENERIC)) {
            TranslateFunctionGenericUpperBounds(funcDecl)
        }
        if (kind == IncreKind.INCR && !funcDecl.toBeCompiled && !IsSrcCodeImportedGlobalDecl(funcDecl)) {
            CreatePseudoImportedFuncSignatureAndSetGlobalCache(funcDecl)
            return
        }
        if (let Some(fn) <- TryGetDeserialized<Function>(funcDecl)) {
            if (funcDecl.TestAttr(AstAttribute.SPECIFIC)) {
                ResetSpecificFunc(funcDecl, fn)
            }
            globalCache.Set(funcDecl, fn)
            if (implicitDecls.contains(funcDecl)) {
                implicitFuncs[fn.GetIdentifierWithoutPrefix()] = fn
            }
            if (let Some(file) <- funcDecl.curFile) {
                fn.SetFeatures(file.GetFeatures())
            }
            return
        }
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        var mangledName = EffectiveFunctionIdentifier(funcDecl)
        if (funcDecl.TestAttr(AstAttribute.NO_MANGLE) && funcTy.IsCFunc()) {
            mangledName += CFFI_FUNC_SUFFIX
        }
        let fn = builder.CreateFunction(funcTy, mangledName,
            srcCodeIdentifier: EffectiveFunctionSrcIdentifier(funcDecl), rawMangledName: EffectiveFunctionRawName(funcDecl),
            packageName: GetNameOfDefinedPackage(funcDecl))
        fn.SetDebugLocation(TranslateLocationWithoutScope(builder.context, funcDecl.begin, funcDecl.end))
        AttachFunctionGenericParams(funcDecl, fn)
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
        }
        SetFuncAttributeAndLinkageType(funcDecl, fn)
        TranslateFuncParams(funcDecl, fn)
        if (implicitDecls.contains(funcDecl)) {
            implicitFuncs[fn.GetIdentifierWithoutPrefix()] = fn
        }
        globalCache.Set(funcDecl, fn)
        if (funcDecl.TestAttr(AstAttribute.GLOBAL) &&
            !funcDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            let translator = CreateTranslator()
            translator.CreateAnnoFactoryFuncsForFuncDecl(funcDecl, None)
        }
    }

    private func CreatePseudoImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, funcDecl.mangledName, srcCodeIdentifier: funcDecl.identifier.Val(),
            rawMangledName: funcDecl.rawMangleName, packageName: funcDecl.fullPackageName)
        AttachFunctionGenericParams(funcDecl, fn)
        fn.EnableAttr(Attribute.IMPORTED)
        SetFuncAttributeAndLinkageType(funcDecl, fn)
        if (HasImplicitThisParam(funcDecl)) {
            let thisParam = builder.CreateParameter(funcTy.GetParamTypes()[0], INVALID_LOCATION, fn)
            thisParam.SetSrcCodeIdentifier("this")
        }
        let body = funcDecl.funcBody ??
            throw IllegalStateException("faithful pseudo imported function has no body")
        CJC_ASSERT(body.paramLists.size == 1)
        for (param in body.paramLists[0].params) {
            let paramTy = chirType.TranslateType(RequireAstTy(param))
            let paramLoc = TranslateLocationWithoutScope(builder.context, param.begin, param.end)
            let chirParam = builder.CreateParameter(paramTy, paramLoc, fn)
            chirParam.SetSrcCodeIdentifier(param.identifier.GetRawText())
        }
        if (implicitDecls.contains(funcDecl)) {
            implicitFuncs[fn.GetIdentifierWithoutPrefix()] = fn
        }
        globalCache.Set(funcDecl, fn)
    }

    private func CreatePseudoDefForAnnoOnlyDecl(decl: AstDecl): Unit {
        if (chirType.Has(decl) || globalCache.TryGet(decl).isSome()) {
            return
        }
        let loc = TranslateLocationWithoutScope(builder.context, decl.begin, decl.end)
        var symbol: Option<CustomTypeDef> = None
        if (let Some(classLikeDecl) <- (decl as AstClassLikeDecl)) {
            let classDef = builder.CreateClassDef(decl.fullPackageName, decl.mangledName, decl.identifier.Val(),
                isClass: (classLikeDecl as AstClassDecl).isSome())
            CurrentPackage().AddClass(classDef)
            classDef.SetDebugLocation(loc)
            symbol = classDef
        }
        if ((decl as AstStructDecl).isSome()) {
            let structDef = builder.CreateStructDef(decl.fullPackageName, decl.mangledName)
            CurrentPackage().AddStruct(structDef)
            structDef.SetSrcCodeIdentifier(decl.identifier.Val())
            structDef.SetDebugLocation(loc)
            symbol = structDef
        }
        if (let Some(enumDecl) <- (decl as AstEnumDecl)) {
            let enumDef = builder.CreateEnumDef(decl.fullPackageName, decl.mangledName)
            CurrentPackage().AddEnum(enumDef)
            enumDef.SetSrcCodeIdentifier(decl.identifier.Val())
            enumDef.SetNonExhaustive(enumDecl.hasEllipsis)
            enumDef.SetDebugLocation(loc)
            symbol = enumDef
        }
        if ((decl as AstExtendDecl).isSome()) {
            let extendDef = builder.CreateExtendDef(decl.fullPackageName, decl.mangledName)
            CurrentPackage().AddExtend(extendDef)
            extendDef.SetDebugLocation(loc)
            symbol = extendDef
        }
        if (let Some(customTypeDef) <- symbol) {
            customTypeDef.EnableAttr(Attribute.SKIP_ANALYSIS)
            chirType.SetGlobalNominalCache(decl, customTypeDef)
            return
        }
        var value: Option<Value> = None
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            let funcBody = funcDecl.funcBody.getOrThrow()
            let params = funcBody.paramLists[0].params
            let paramTypes = ArrayList<Type>()
            for (_ in params) {
                paramTypes.add(builder.context.GetInt64Ty())
            }
            let funcType = builder.context.GetFuncTy(paramTypes, builder.context.GetUnitTy())
            let funcDef = builder.CreateFunction(funcType, decl.mangledName, srcCodeIdentifier: decl.mangledName,
                rawMangledName: decl.rawMangleName, packageName: decl.fullPackageName)
            for (param in params) {
                let paramLoc = TranslateLocationWithoutScope(builder.context, param.begin, param.end)
                let _ = builder.CreateParameter(builder.context.GetInt64Ty(), paramLoc, funcDef)
            }
            value = funcDef
        }
        if ((decl as AstVarDecl).isSome()) {
            let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(builder.context.GetInt64Ty()),
                decl.mangledName, srcCodeIdentifier: decl.identifier.Val(), rawMangledName: decl.rawMangleName,
                packageName: decl.fullPackageName)
            globalVar.SetDebugLocation(loc)
            value = globalVar
        }
        let pseudoValue = value.getOrThrow()
        pseudoValue.EnableAttr(Attribute.SKIP_ANALYSIS)
        globalCache.Set(decl, pseudoValue)
    }

    private func CreateImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        if (let Some(fn) <- TryGetDeserialized<Function>(funcDecl)) {
            ConvertImportedFunctionType(fn, funcDecl)
            globalCache.Set(funcDecl, fn)
            if (implicitDecls.contains(funcDecl)) {
                implicitFuncs[fn.GetIdentifierWithoutPrefix()] = fn
            }
            fn.SetDebugLocation(GetDeclLoc(builder.context, funcDecl))
            return
        }
        if (funcDecl.TestAttr(AstAttribute.GENERIC)) {
            TranslateFunctionGenericUpperBounds(funcDecl)
        }
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        fn.SetDebugLocation(TranslateLocationWithoutScope(builder.context, funcDecl.begin, funcDecl.end))
        AttachFunctionGenericParams(funcDecl, fn)
        fn.EnableAttr(Attribute.IMPORTED)
        SetFuncAttributeAndLinkageType(funcDecl, fn)
        if (implicitDecls.contains(funcDecl)) {
            implicitFuncs[fn.GetIdentifierWithoutPrefix()] = fn
        }
        if (HasImplicitThisParam(funcDecl)) {
            let thisParam = builder.CreateParameter(funcTy.GetParamTypes()[0], INVALID_LOCATION, fn)
            thisParam.SetSrcCodeIdentifier("this")
        }
        let body = funcDecl.funcBody ??
            throw IllegalStateException("faithful imported function has no body")
        CJC_ASSERT(!body.paramLists.isEmpty())
        for (param in body.paramLists[0].params) {
            let paramTy = chirType.TranslateType(RequireAstTy(param))
            let paramLoc = TranslateLocationWithoutScope(builder.context, param.begin, param.end)
            let chirParam = builder.CreateParameter(paramTy, paramLoc, fn)
            chirParam.SetSrcCodeIdentifier(param.identifier.GetRawText())
        }
        globalCache.Set(funcDecl, fn)
    }

    private func ConvertImportedFunctionType(fn: Function, funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        if (fn.GetFuncType().getOrThrow() == funcTy) {
            return
        }
        let replaceTable = fn.GetFuncType().getOrThrow().CalculateGenericTyMapping(funcTy)[1]
        let converter = PrivateTypeConverter({ ty: Type => ReplaceRawGenericArgType(ty, replaceTable, builder) }, builder)
        converter.VisitSubValue(fn)
    }

    private func ResetSpecificFunc(funcDecl: AstFuncDecl, fn: Function): Unit {
        fn.DestroyFuncBody()
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            fn.DisableAttr(Attribute.ABSTRACT)
        }
        fn.SetDebugLocation(TranslateLocationWithoutScope(builder.context, funcDecl.begin, funcDecl.end))
        SetFuncAttributeAndLinkageType(funcDecl, fn)
        fn.EnableAttr(Attribute.SPECIFIC)
        fn.DisableAttr(Attribute.COMMON)
        fn.DisableAttr(Attribute.SKIP_ANALYSIS)

        let newGenericParamTys = GetGenericParamType(funcDecl)
        let oldGenericParamTys = fn.GetGenericTypeParams()
        if (oldGenericParamTys.isEmpty()) {
            return
        }
        CJC_ASSERT(newGenericParamTys.size == oldGenericParamTys.size)
        let replaceTable = HashMap<GenericType, Type>()
        var idx: Int64 = 0
        while (idx < oldGenericParamTys.size) {
            if (oldGenericParamTys[idx] != newGenericParamTys[idx]) {
                replaceTable[oldGenericParamTys[idx]] = newGenericParamTys[idx]
            }
            idx++
        }
        if (replaceTable.isEmpty()) {
            return
        }
        let converter = PrivateTypeConverter({ ty: Type => ReplaceRawGenericArgType(ty, replaceTable, builder) }, builder)
        converter.VisitSubValue(fn)
    }

    private func GetGenericParamType(funcDecl: AstFuncDecl): ArrayList<GenericType> {
        let genericParamTys = ArrayList<GenericType>()
        if (!funcDecl.TestAttr(AstAttribute.GENERIC)) {
            return genericParamTys
        }
        let funcBody = funcDecl.funcBody ??
            throw IllegalStateException("faithful generic function has no body")
        let generic = funcBody.generic ??
            throw IllegalStateException("faithful generic function has no generic parameters")
        for (genericTy in generic.typeParameters) {
            genericParamTys.add((chirType.TranslateType(RequireAstTy(genericTy)) as GenericType).getOrThrow())
        }
        return genericParamTys
    }

    private func GetGenericParamType(decl: AstDecl): ArrayList<GenericType> {
        let genericParamTys = ArrayList<GenericType>()
        if (!decl.TestAttr(AstAttribute.GENERIC)) {
            return genericParamTys
        }
        let generic = decl.GetGeneric().getOrThrow()
        for (genericTy in generic.typeParameters) {
            genericParamTys.add((chirType.TranslateType(RequireAstTy(genericTy)) as GenericType).getOrThrow())
        }
        return genericParamTys
    }

    private func CreateImportedValueSignatureAndSetGlobalCache(varDecl: AstVarDecl): Unit {
        if (let Some(globalVar) <- TryGetDeserialized<GlobalVar>(varDecl)) {
            globalCache.Set(varDecl, globalVar)
            return
        }
        let varTy = chirType.TranslateType(RequireAstTy(varDecl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(varDecl),
            srcCodeIdentifier: varDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(varDecl),
            packageName: EffectivePackageName(varDecl))
        globalVar.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(globalVar, varDecl)
        if (varDecl.IsConst()) {
            globalVar.EnableAttr(Attribute.CONST)
        }
        globalCache.Set(varDecl, globalVar)
    }

    private func CreateGlobalVarSignature(decls: ArrayList<AstDecl>, isLocalConst!: Bool = false): Unit {
        let translator = CreateTranslator()
        for (decl in decls) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                let globalVar = CreateAndCacheGlobalVar(varDecl, isLocalConst: isLocalConst)
                if (globalVar.TestAttr(Attribute.STATIC)) {
                    continue
                }
                let annoInfo = translator.CreateAnnoFactoryFuncSig(decl, None)
                if (annoInfo.IsAvailable()) {
                    globalVar.SetAnnoInfo(annoInfo)
                }
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                let varDecls = ArrayList<AstVarDecl>()
                FlattenGlobalVarWithPatternDecl(RequirePattern(varWithPattern.irrefutablePattern,
                    "global var-with-pattern pattern"), varDecls)
                for (varDecl in varDecls) {
                    let globalVar = CreateAndCacheGlobalVar(varDecl, isLocalConst: isLocalConst)
                    let annoInfo = translator.CreateAnnoFactoryFuncSig(decl, None)
                    if (annoInfo.IsAvailable()) {
                        CJC_ASSERT(!globalVar.TestAttr(Attribute.STATIC))
                        globalVar.SetAnnoInfo(annoInfo)
                    }
                }
            }
        }
    }

    private func FlattenGlobalVarWithPatternDecl(pattern: AstPattern, varDecls: ArrayList<AstVarDecl>): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            let varDecl = varPattern.varDecl ??
                throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
            varDecls.add(varDecl)
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            for (subPattern in tuplePattern.patterns) {
                FlattenGlobalVarWithPatternDecl(subPattern, varDecls)
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            for (subPattern in enumPattern.patterns) {
                FlattenGlobalVarWithPatternDecl(subPattern, varDecls)
            }
            return
        }
        if ((pattern as AstWildcardPattern).isSome()) {
            return
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported global var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func CreateAndCacheGlobalVar(decl: AstVarDecl, isLocalConst!: Bool = false): GlobalVar {
        if (let Some(globalVar) <- TryGetDeserialized<GlobalVar>(decl)) {
            globalCache.Set(decl, globalVar)
            globalVar.SetDebugLocation(GetDeclLoc(builder.context, decl))
            return globalVar
        }
        let varTy = chirType.TranslateType(RequireAstTy(decl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(decl),
            srcCodeIdentifier: decl.identifier.Val(), rawMangledName: EffectiveRawMangledName(decl),
            packageName: EffectivePackageName(decl))
        globalVar.SetDebugLocation(TranslateLocationWithoutScope(builder.context, decl.begin, decl.end))
        globalVar.SetDebugLocationInfoForWarning(GetDeclLoc(builder.context, decl))
        globalVar.AppendAttributeInfo(BuildVarDeclAttr(decl))
        SetGlobalVarLinkageType(globalVar, decl, isLocalConst, opts.target.os == OSType.WINDOWS)
        if (isLocalConst) {
            globalVar.EnableAttr(Attribute.COMPILER_ADD)
        }
        if (decl.IsConst()) {
            globalVar.EnableAttr(Attribute.CONST)
        }
        if (decl.TestAttr(AstAttribute.COMMON)) {
            globalVar.EnableAttr(Attribute.COMMON)
        }
        globalCache.Set(decl, globalVar)
        return globalVar
    }

    private func TranslateFuncParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        let funcTy = fn.GetFuncType() ??
            throw IllegalStateException("faithful AST2CHIR function has no FuncType: ${fn.GetIdentifier()}")
        let paramTys = funcTy.GetParamTypes()
        let paramLoc = ArrayList<DebugLocation>()
        let paramSrcCodeIdentifiers = ArrayList<String>()
        if (HasImplicitThisParam(funcDecl)) {
            paramLoc.add(INVALID_LOCATION)
            paramSrcCodeIdentifiers.add("this")
        }
        let body = funcDecl.funcBody ??
            throw IllegalStateException("faithful AST2CHIR function has no body: ${fn.GetIdentifier()}")
        if (body.paramLists.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR function has no parameter list: ${fn.GetIdentifier()}")
        }
        for (param in body.paramLists[0].params) {
            paramLoc.add(TranslateLocationWithoutScope(builder.context, param.begin, param.end))
            paramSrcCodeIdentifiers.add(param.identifier.GetRawText())
        }
        if (paramTys.size != paramLoc.size || paramTys.size != paramSrcCodeIdentifiers.size) {
            throw IllegalStateException("faithful AST2CHIR function parameter count mismatch: ${fn.GetIdentifier()}")
        }
        var paramIndex: Int64 = 0
        while (paramIndex < paramTys.size) {
            let parameter = builder.CreateParameter(paramTys[paramIndex], paramLoc[paramIndex], fn)
            parameter.SetSrcCodeIdentifier(paramSrcCodeIdentifiers[paramIndex])
            paramIndex++
        }
        let offset: Int64 = if (HasImplicitThisParam(funcDecl)) { 1 } else { 0 }
        var explicitIndex: Int64 = 0
        for (param in body.paramLists[0].params) {
            globalCache.Set(param, fn.GetParam(explicitIndex + offset))
            explicitIndex++
        }
    }

    private func AdjustFuncType(funcDecl: AstFuncDecl, funcTy: FuncType): FuncType {
        if (!HasImplicitThisParam(funcDecl)) {
            return funcTy
        }
        let outerDecl = funcDecl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR instance member function has no owner decl")
        let baseParams = funcTy.GetParamTypes()
        let explicitParamCount = GetExplicitParamCount(funcDecl)
        let astTypeAlreadyHasThis = baseParams.size > explicitParamCount
        let params = ArrayList<Type>()
        params.add(AddRefIfFuncIsMutOrClass(chirType.TranslateType(RequireAstTy(outerDecl)), funcDecl))
        var paramIndex: Int64 = if (astTypeAlreadyHasThis) { 1 } else { 0 }
        while (paramIndex < baseParams.size) {
            params.add(baseParams[paramIndex])
            paramIndex++
        }
        let retTy = if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            builder.context.GetUnitTy()
        } else {
            funcTy.GetReturnType()
        }
        return builder.context.GetFuncTy(params, retTy)
    }

    private func HasImplicitThisParam(funcDecl: AstFuncDecl): Bool {
        return funcDecl.IsMemberDecl() && !funcDecl.TestAttr(AstAttribute.STATIC)
    }

    private func GetExplicitParamCount(funcDecl: AstFuncDecl): Int64 {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return body.paramLists[0].params.size
            }
        }
        return 0
    }

    private func AddRefIfFuncIsMutOrClass(thisTy: Type, funcDecl: AstFuncDecl): Type {
        if (thisTy.IsRef()) {
            return thisTy
        }
        if (thisTy.IsClassOrArray() || funcDecl.TestAnyAttr(AstAttribute.MUT, AstAttribute.CONSTRUCTOR)) {
            return builder.context.GetRefTy(thisTy)
        }
        return thisTy
    }

    private func GetFuncKindFromAST(funcDecl: AstFuncDecl): FuncKind {
        if (funcDecl.isGetter) {
            return FuncKind.GETTER
        }
        if (funcDecl.isSetter) {
            return FuncKind.SETTER
        }
        if (funcDecl.IsFinalizer()) {
            return FuncKind.FINALIZER
        }
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            return FuncKind.MAIN_ENTRY
        }
        if (funcDecl.TestAttr(AstAttribute.MACRO_FUNC)) {
            return FuncKind.MACRO_FUNC
        }
        if (funcDecl.TestAttr(AstAttribute.PRIMARY_CONSTRUCTOR)) {
            if (funcDecl.TestAttr(AstAttribute.IN_STRUCT)) {
                return FuncKind.PRIMAL_STRUCT_CONSTRUCTOR
            } else if (funcDecl.TestAttr(AstAttribute.IN_CLASSLIKE)) {
                return FuncKind.PRIMAL_CLASS_CONSTRUCTOR
            } else {
                CJC_ABORT()
            }
        } else if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            if (funcDecl.TestAttr(AstAttribute.IN_STRUCT)) {
                return FuncKind.STRUCT_CONSTRUCTOR
            } else if (funcDecl.TestAttr(AstAttribute.IN_CLASSLIKE)) {
                return FuncKind.CLASS_CONSTRUCTOR
            } else {
                CJC_ABORT()
            }
        }
        if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
            return FuncKind.DEFAULT_PARAMETER_FUNC
        }
        return FuncKind.DEFAULT
    }

    private func ApplyDeclAttrs(target: Base, decl: AstDecl): Unit {
        target.AppendAttributeInfo(BuildAttr(decl.GetAttrs()))
        if (decl.TestAttr(AstAttribute.C)) {
            if (let Some(structDef) <- (target as StructDef)) {
                structDef.SetCStruct(true)
            }
        }
        if (let Some(customTypeDef) <- (target as CustomTypeDef)) {
            if (AstIsImpl(decl)) {
                customTypeDef.EnableAttr(Attribute.JAVA_IMPL)
            } else if (AstIsMirror(decl)) {
                customTypeDef.EnableAttr(Attribute.JAVA_MIRROR)
            }
        }
    }

    private func EffectiveMangledName(decl: AstDecl): String {
        if (let Some(name) <- EffectiveDefaultParamMangledName(decl)) {
            return name
        }
        if (!decl.mangledName.isEmpty()) {
            return decl.mangledName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        if (decl.IsMemberDecl() && !decl.TestAttr(AstAttribute.IMPORTED)) {
            return EffectiveMemberMangledName(decl)
        }
        return decl.identifier.Val()
    }

    private func EffectiveMemberMangledName(decl: AstDecl): String {
        let outerDecl = decl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR member declaration has no owner")
        return EffectiveMangledName(outerDecl) + "." + decl.identifier.Val()
    }

    private func EffectiveRawMangledName(decl: AstDecl): String {
        if (let Some(rawName) <- EffectiveDefaultParamRawName(decl)) {
            return rawName
        }
        if (!decl.rawMangleName.isEmpty()) {
            return decl.rawMangleName
        }
        return EffectiveMangledName(decl)
    }

    private func EffectiveDefaultParamMangledName(decl: AstDecl): Option<String> {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL) && funcDecl.ownerFunc.isSome()) {
                if (FaithfulStartsWith(funcDecl.mangledName,
                    FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX)) {
                    return Some(funcDecl.mangledName)
                }
                return Some(MangleDefaultParamFunction(funcDecl))
            }
        }
        return None
    }

    private func EffectiveDefaultParamRawName(decl: AstDecl): Option<String> {
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
                if (let Some(owner) <- funcDecl.ownerFunc) {
                    if (!owner.rawMangleName.isEmpty()) {
                        return Some(owner.rawMangleName)
                    }
                    if (!owner.mangledName.isEmpty()) {
                        return Some(owner.mangledName)
                    }
                }
                return EffectiveDefaultParamMangledName(decl)
            }
        }
        return None
    }

    private func MangleDefaultParamFunction(funcDecl: AstFuncDecl): String {
        let owner = funcDecl.ownerFunc ??
            throw IllegalStateException("faithful AST2CHIR default parameter function has no owner")
        return FAITHFUL_MANGLE_CANGJIE_PREFIX + FAITHFUL_MANGLE_FUNC_PARA_INIT_PREFIX +
            MangleDefaultParamOwner(owner) + FAITHFUL_MANGLE_SUFFIX + MangleDefaultParamName(funcDecl.identifier.Val()) +
            FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncDeclParamTypes(funcDecl)
    }

    private func MangleDefaultParamOwner(owner: AstFuncDecl): String {
        let parts = ArrayList<AstDecl>()
        var outerDecl = owner.outerDecl
        while (let Some(outer) <- outerDecl) {
            parts.add(outer)
            outerDecl = outer.outerDecl
        }
        var idx = parts.size - 1
        var out = FaithfulMangleName(EffectivePackageName(owner))
        while (idx >= 0) {
            out += FaithfulMangleName(parts[idx].identifier.Val())
            idx--
        }
        out += FaithfulMangleName(owner.identifier.Val())
        out += FAITHFUL_MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncDeclParamTypes(owner)
        return out
    }

    private func MangleDefaultParamName(identifier: String): String {
        var name = identifier
        if (let Some(pos) <- identifier.indexOf(FAITHFUL_MANGLE_DOT_PREFIX)) {
            name = identifier[0..pos]
        }
        return FaithfulMangleName(name)
    }

    private func MangleFuncDeclParamTypes(funcDecl: AstFuncDecl): String {
        let genericsTypeStack = MangleFuncDeclGenericsTypeStack(funcDecl)
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                return MangleFuncParamList(body.paramLists[0].params, genericsTypeStack)
            }
        }
        return FAITHFUL_MANGLE_VOID_TY_SUFFIX
    }

    private func MangleFuncDeclGenericsTypeStack(funcDecl: AstFuncDecl): ArrayList<String> {
        let out = ArrayList<String>()
        if (let Some(generic) <- funcDecl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramAstTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramAstTy as AstGenericsTy)) {
                        out.add(genericTy.name)
                    }
                }
            }
        }
        return out
    }

    private func MangleFuncParamList(params: ArrayList<AstFuncParam>, genericsTypeStack: ArrayList<String>): String {
        if (params.isEmpty()) {
            return FAITHFUL_MANGLE_VOID_TY_SUFFIX
        }
        var out = ""
        for (param in params) {
            out += FaithfulMangleType(chirType.TranslateType(RequireAstTy(param)), genericsTypeStack)
        }
        return out
    }

    private func FaithfulMangleName(value: String): String {
        return value.size.toString() + value
    }

    private func FaithfulStripCangjiePrefix(value: String): String {
        if (FaithfulStartsWith(value, FAITHFUL_MANGLE_CANGJIE_PREFIX)) {
            return value[FAITHFUL_MANGLE_CANGJIE_PREFIX.size..]
        }
        return value
    }

    private func FaithfulCustomTypeIdentifier(def: CustomTypeDef): String {
        let identifier = def.GetIdentifier()
        if (FaithfulStartsWith(identifier, FAITHFUL_MANGLE_AT_PREFIX)) {
            return identifier[FAITHFUL_MANGLE_AT_PREFIX.size..]
        }
        return FaithfulStripCangjiePrefix(identifier)
    }

    private func FaithfulDecimalToManglingNumber(decimal: String): String {
        let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        var parsed: Int64 = 0
        var decimalIdx: Int64 = 0
        while (decimalIdx < decimal.size) {
            let byte = decimal[decimalIdx]
            if (byte < b'0' || byte > b'9') {
                return ""
            }
            parsed = parsed * 10 + Int64(byte - b'0')
            decimalIdx++
        }
        var num = parsed - 1
        if (num < 0) {
            return FAITHFUL_MANGLE_WILDCARD_PREFIX
        }
        var out = if (num > 0) { "" } else { "0" }
        while (num > 0) {
            let idx = num % base62Chars.size
            out += base62Chars[idx..idx + 1]
            num /= base62Chars.size
        }
        return out + FAITHFUL_MANGLE_WILDCARD_PREFIX
    }

    private func FaithfulPrimitiveTypeMangle(kind: TypeKind): String {
        return match (kind) {
            case TypeKind.TYPE_INT8 => "a"
            case TypeKind.TYPE_INT16 => "s"
            case TypeKind.TYPE_INT32 => "i"
            case TypeKind.TYPE_INT64 => "l"
            case TypeKind.TYPE_INT_NATIVE => "q"
            case TypeKind.TYPE_UINT8 => "h"
            case TypeKind.TYPE_UINT16 => "t"
            case TypeKind.TYPE_UINT32 => "j"
            case TypeKind.TYPE_UINT64 => "m"
            case TypeKind.TYPE_UINT_NATIVE => "r"
            case TypeKind.TYPE_FLOAT16 => "Dh"
            case TypeKind.TYPE_FLOAT32 => "f"
            case TypeKind.TYPE_FLOAT64 => "d"
            case TypeKind.TYPE_RUNE => "c"
            case TypeKind.TYPE_BOOLEAN => "b"
            case TypeKind.TYPE_UNIT => "u"
            case TypeKind.TYPE_NOTHING => "n"
            case TypeKind.TYPE_CSTRING => "k"
            case TypeKind.TYPE_VOID => "u"
            case _ => ""
        }
    }

    private func FaithfulMangleGenericType(genericTy: GenericType, genericsTypeStack: ArrayList<String>): String {
        var idx = genericsTypeStack.size - 1
        while (idx >= 0) {
            if (genericsTypeStack[idx] == genericTy.GetSrcCodeIdentifier()) {
                return FAITHFUL_MANGLE_GENERIC_TYPE_PREFIX + FaithfulDecimalToManglingNumber(idx.toString())
            }
            idx--
        }
        throw IllegalArgumentException("Using undeclared generic type: " + genericTy.GetSrcCodeIdentifier())
    }

    private func FaithfulMangleType(ty: Type, genericsTypeStack: ArrayList<String>): String {
        let primitive = FaithfulPrimitiveTypeMangle(ty.GetTypeKind())
        if (!primitive.isEmpty()) {
            return primitive
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            let items = tupleTy.GetTypeArgs()
            var out = FAITHFUL_MANGLE_TUPLE_PREFIX + FaithfulDecimalToManglingNumber(items.size.toString())
            for (item in items) {
                out += FaithfulMangleType(item, genericsTypeStack)
            }
            return out + FAITHFUL_MANGLE_SUFFIX
        }
        if (let Some(structTy) <- (ty as StructType)) {
            var out = FAITHFUL_MANGLE_TYPE_STRUCT_PREFIX + FaithfulCustomTypeIdentifier(structTy.GetCustomTypeDef())
            for (arg in structTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            var out = FAITHFUL_MANGLE_TYPE_ENUM_PREFIX + FaithfulCustomTypeIdentifier(enumTy.GetCustomTypeDef())
            for (arg in enumTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            var out = FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulCustomTypeIdentifier(classTy.GetCustomTypeDef())
            for (arg in classTy.GetGenericArgs()) {
                out += FaithfulMangleType(arg, genericsTypeStack)
            }
            return out
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            var out = if (funcTy.IsCFunc()) { FAITHFUL_MANGLE_CFUNC_PREFIX } else {
                FAITHFUL_MANGLE_GENERAL_FUNC_PREFIX
            }
            out += FaithfulMangleType(funcTy.GetReturnType(), genericsTypeStack)
            let params = funcTy.GetParamTypes()
            if (params.isEmpty()) {
                return out + FAITHFUL_MANGLE_VOID_TY_SUFFIX + FAITHFUL_MANGLE_SUFFIX
            }
            for (param in params) {
                out += FaithfulMangleType(param, genericsTypeStack)
            }
            return out + FAITHFUL_MANGLE_SUFFIX
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return FAITHFUL_MANGLE_TYPE_ARRAY_PREFIX + FaithfulDecimalToManglingNumber(rawArrayTy.GetDims().toString()) +
                FaithfulMangleType(rawArrayTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return FaithfulMangleType(refTy.GetBaseType(), genericsTypeStack)
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return FAITHFUL_MANGLE_VARRAY_PREFIX + FaithfulDecimalToManglingNumber(varrayTy.size.toString()) +
                FaithfulMangleType(varrayTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return FAITHFUL_MANGLE_POINTER_PREFIX + FaithfulMangleType(pointerTy.GetElementType(), genericsTypeStack)
        }
        if (let Some(genericTy) <- (ty as GenericType)) {
            return FaithfulMangleGenericType(genericTy, genericsTypeStack)
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulMangleName("Box") +
                FaithfulMangleType(boxTy.GetBaseType(), genericsTypeStack)
        }
        if (let Some(thisTy) <- (ty as ThisType)) {
            return FAITHFUL_MANGLE_TYPE_CLASS_PREFIX + FaithfulMangleName(thisTy.ToString())
        }
        return FaithfulMangleName(ty.ToString())
    }

    private func EffectiveFunctionIdentifier(funcDecl: AstFuncDecl): String {
        return EffectiveMangledName(funcDecl)
    }

    private func EffectiveFunctionRawName(funcDecl: AstFuncDecl): String {
        return EffectiveRawMangledName(funcDecl)
    }

    private func EffectiveFunctionSrcIdentifier(funcDecl: AstFuncDecl): String {
        let identifier = funcDecl.identifier.Val()
        return if (identifier.isEmpty() && funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) { "main" } else { identifier }
    }

    private func EffectivePackageName(decl: AstDecl): String {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName
        }
        return CurrentPackage().GetName()
    }

    private func RequireAstTy(node: AstDecl): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for decl: ${node.identifier.Val()}")
    }

    private func RequireAstTy(node: AstExpr): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for expr: ${ASTKindName(node.astKind)}")
    }

    private func RequireExpr(expr: Option<AstExpr>, context: String): AstExpr {
        return expr ?? throw IllegalStateException("faithful AST2CHIR requires ${context}")
    }

    private func RequirePattern(pattern: Option<AstPattern>, context: String): AstPattern {
        return pattern ?? throw IllegalStateException("faithful AST2CHIR requires ${context}")
    }

    private func RequireFuncType(ty: Type): FuncType {
        return (ty as FuncType) ?? throw IllegalStateException("faithful AST2CHIR expected FuncType: ${ty.ToString()}")
    }

    private func RequireGlobalVar(value: Value): GlobalVar {
        return (value as GlobalVar) ??
            throw IllegalStateException("faithful AST2CHIR expected GlobalVar: ${value.GetIdentifier()}")
    }

    private func RequireFuncDecl(decl: AstDecl): AstFuncDecl {
        return (decl as AstFuncDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected func_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireVarDecl(decl: AstDecl): AstVarDecl {
        return (decl as AstVarDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected var_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireStructDecl(decl: AstDecl): AstStructDecl {
        return (decl as AstStructDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected struct_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireClassLikeDecl(decl: AstDecl): AstClassLikeDecl {
        return (decl as AstClassLikeDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected class_like_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireEnumDecl(decl: AstDecl): AstEnumDecl {
        return (decl as AstEnumDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected enum_decl, got ${ASTKindName(decl.astKind)}")
    }

    private func RequireExtendDecl(decl: AstDecl): AstExtendDecl {
        return (decl as AstExtendDecl) ??
            throw IllegalArgumentException("faithful AST2CHIR expected extend_decl, got ${ASTKindName(decl.astKind)}")
    }

    private static func FindInitEntryForFile(values: ArrayList<FaithfulInitFileVars>,
        file: AstFile): Option<FaithfulInitFileVars> {
        for (value in values) {
            if (SameAstFile(value.file, file)) {
                return value
            }
        }
        return None
    }

    private static func SameAstFile(left: AstFile, right: AstFile): Bool {
        return left.fileName == right.fileName && left.begin.hashCode() == right.begin.hashCode() &&
            left.end.hashCode() == right.end.hashCode()
    }

}
