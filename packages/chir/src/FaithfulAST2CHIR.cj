package cangjie_compiler::chir

import cangjie_compiler::option.GlobalOptions
import std.collection.*
import std.convert.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.AccessLevel as AstAccessLevel
import cangjie_compiler::ast.ArrayExpr as AstArrayExpr
import cangjie_compiler::ast.ArrayLit as AstArrayLit
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.EnumPattern as AstEnumPattern
import cangjie_compiler::ast.ExtendDecl as AstExtendDecl
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.File as AstFile
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.FuncParam as AstFuncParam
import cangjie_compiler::ast.GenericsTy as AstGenericsTy
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.Pattern as AstPattern
import cangjie_compiler::ast.PropDecl as AstPropDecl
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.TuplePattern as AstTuplePattern
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.TypeKind as AstTypeKind
import cangjie_compiler::ast.TypeKindInRange as AstTypeKindInRange
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.VarPattern as AstVarPattern
import cangjie_compiler::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cangjie_compiler::ast.VisitAction as AstVisitAction
import cangjie_compiler::ast.Walker as AstWalker
import cangjie_compiler::ast.WildcardPattern as AstWildcardPattern
import cangjie_compiler::ast.Position as AstPosition
import cangjie_compiler::ast.IsStaticInitializer as AstIsStaticInitializer
import cangjie_compiler::utils.{CJC_ABORT, CJC_ASSERT, MAIN_INVOKE, STATIC_INIT_VAR}

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
            if (existing.objectId == dep.objectId) {
                return
            }
        }
        deps.add(dep)
        for (entry in stableOrderValue) {
            if (entry.file.objectId == root.objectId) {
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
            if (existing.element.objectId == unit.element.objectId) {
                return
            }
        }
        depsUnits.add(unit)
    }

    public func AddUsers(unit: DepsUnit<T>): Unit {
        for (existing in userUnits) {
            if (existing.element.objectId == unit.element.objectId) {
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
            while (stack[stack.size - 1].element.objectId != unit.element.objectId) {
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
                    if (unit.depsUnits[idx].element.objectId == curFreeUnit.element.objectId) {
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
            if (unit.element.objectId == element.objectId) {
                return unit
            }
        }
        throw IllegalStateException("TarjanSort missing unit: " + GetEleStr(element))
    }

    private func SetSccUnit(element: T, unit: DepsUnit<T>): Unit {
        var idx: Int64 = 0
        while (idx < node2SccUnitMap.size) {
            if (node2SccUnitMap[idx].element.objectId == element.objectId) {
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
                if (item.objectId == element.objectId) {
                    return unit
                }
            }
        }
        throw IllegalStateException("TarjanSort missing SCC unit: " + GetEleStr(element))
    }

    private func ContainsUnit(values: ArrayList<DepsUnit<T>>, unit: DepsUnit<T>): Bool {
        for (value in values) {
            if (value.element.objectId == unit.element.objectId) {
                return true
            }
        }
        return false
    }

    private func ContainsElement(values: ArrayList<T>, element: T): Bool {
        for (value in values) {
            if (value.objectId == element.objectId) {
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

@OverflowWrapping
private func FaithfulInitHashCombine(seed: Int64, value: Int64): Int64 {
    return seed * 1315423911 + value + 0x9e3779b9
}

private func FaithfulInitDeclHash(decl: AstDecl): Int64 {
    if (let Some(defaultKey) <- FaithfulInitDefaultParamDeclIdentity(decl)) {
        return defaultKey.hashCode()
    }
    if (decl.TestAttr(AstAttribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return FaithfulInitHashCombine(17, decl.rawMangleName.hashCode())
        }
        if (!decl.mangledName.isEmpty()) {
            return FaithfulInitHashCombine(31, decl.mangledName.hashCode())
        }
    }
    return decl.objectId
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
    if (left.TestAttr(AstAttribute.IMPORTED) && right.TestAttr(AstAttribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return left.objectId == right.objectId
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

private func BuildPackageAccessLevel(level: AstAccessLevel): AccessLevel {
    return match (level) {
        case AstAccessLevel.INTERNAL => AccessLevel.INTERNAL
        case AstAccessLevel.PROTECTED => AccessLevel.PROTECTED
        case AstAccessLevel.PUBLIC => AccessLevel.PUBLIC
        case AstAccessLevel.PRIVATE => throw IllegalArgumentException("invalid package access level")
    }
}

private func TranslateLocationWithoutScope(context: CHIRContext, beginPos: AstPosition,
    endPos: AstPosition): DebugLocation {
    let fileId = UInt32(beginPos.fileID)
    return DebugLocation(context.GetSourceFileName(fileId), fileId,
        Position(UInt32(beginPos.line), UInt32(beginPos.column)),
        Position(UInt32(endPos.line), UInt32(endPos.column)), scopeInfo: ArrayList<Int64>([0]))
}

public class FaithfulAST2CHIRBuilder {
    private var builder: Option<CHIRBuilder> = None
    private var chirType: Option<CHIRType> = None
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

    public func SetOverrideSrcFuncResolver(
        resolver: (AstFuncDecl) -> Option<AstFuncDecl>): FaithfulAST2CHIRBuilder {
        overrideSrcFuncResolver = Some(resolver)
        return this
    }

    public func Build(): FaithfulAST2CHIR {
        return FaithfulAST2CHIR(
            builder ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRBuilder"),
            chirType ?? throw IllegalStateException("FaithfulAST2CHIRBuilder requires CHIRType"),
            overrideSrcFuncResolver: overrideSrcFuncResolver)
    }
}

public class FaithfulAST2CHIR {
    private let builder: CHIRBuilder
    private let chirType: CHIRType
    private let importedPackages: ArrayList<AstPackage>
    private let directImportedPackages: ArrayList<AstPackage>
    private let overrideSrcFuncResolver: Option<(AstFuncDecl) -> Option<AstFuncDecl>>
    private let opts: GlobalOptions
    private let chirWFC: Bool
    private let chirOptOverO2: Bool
    private var outputPackage: Option<Package> = None
    private var failure: Bool = false
    private var failureReason: String = ""

    private let globalCache: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
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
    private let packageInitializerBlocks: HashMap<Int64, Block> = HashMap<Int64, Block>()
    private let initFuncsForConstVar: ArrayList<Function> = ArrayList<Function>()

    public init(builder: CHIRBuilder, chirType: CHIRType,
        importedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        directImportedPkgs!: ArrayList<AstPackage> = ArrayList<AstPackage>(),
        overrideSrcFuncResolver!: Option<(AstFuncDecl) -> Option<AstFuncDecl>> = None,
        opts!: GlobalOptions = GlobalOptions(), chirWFC!: Bool = false, chirOptOverO2!: Bool = false) {
        this.builder = builder
        this.chirType = chirType
        this.importedPackages = importedPkgs
        this.directImportedPackages = directImportedPkgs
        this.overrideSrcFuncResolver = overrideSrcFuncResolver
        this.opts = opts
        this.chirWFC = chirWFC
        this.chirOptOverO2 = chirOptOverO2
    }

    public func ToCHIRPackage(node: AstPackage): Bool {
        outputPackage = builder.CreatePackage(node.fullPackageName)
        CurrentPackage().SetPackageAccessLevel(BuildPackageAccessLevel(node.accessible))
        CollectImportedDecls(node)
        CollectDeclsInCurPkg(node)
        CollectLocalConstFuncAndVars(node)
        CacheTopLevelDeclToGlobalSymbolTable()
        TranslateNominalDecls(node)
        TranslateOtherTopLevelDecls(node)
        SetInitFuncForStaticVar()
        UpdateMemberVarPath(builder).RunOnPackage(CurrentPackage())
        FlatForInExpr(builder).RunOnPackage(CurrentPackage())
        if (!failure && opts.IsConstEvalEnabled() && !opts.enIncrementalCompilation && opts.commonPartCjos.isEmpty()) {
            let bchirPackages = ArrayList<BCHIR>()
            ConstEvalPass(builder, opts: opts).RunOnPackage(CurrentPackage(), initFuncsForConstVar, bchirPackages)
        }
        if (chirWFC) {
            AST2CHIRCheck()
        }
        if (!failure) {
            ClosureConversion(builder).RunOnPackage(CurrentPackage())
            ReplaceSrcCodeImportedValAfterConstEval(CurrentPackage())
        }
        return !failure
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

    private func CurrentPackage(): Package {
        return outputPackage ?? throw IllegalStateException("faithful AST2CHIR package has not been created")
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
                CollectDeclsFromStructDecl(RequireStructDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.CLASS_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.INTERFACE_DECL =>
                CollectDeclsFromClassLikeDecl(RequireClassLikeDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.ENUM_DECL =>
                CollectDeclsFromEnumDecl(RequireEnumDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.EXTEND_DECL =>
                CollectDeclsFromExtendDecl(RequireExtendDecl(decl))
                CollectNominalDecl(decl, instantiated)
            case ASTKind.FUNC_DECL =>
                CollectFuncDecl(RequireFuncDecl(decl))
            case ASTKind.MAIN_DECL =>
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

    private func CollectFuncDecl(funcDecl: AstFuncDecl): Unit {
        if (funcDecl.TestAttr(AstAttribute.INTRINSIC)) {
            return
        }
        if (funcDecl.TestAttr(AstAttribute.FOREIGN)) {
            CollectDeclToList(funcDecl, foreignFuncs, foreignFuncSet)
            return
        }
        CollectDeclToList(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
        CollectDesugaredDefaultParams(funcDecl, globalAndMemberFuncs, globalAndMemberFuncSet)
    }

    private func CollectDesugarDecl(decl: AstDecl): Unit {
        if (decl.astKind == ASTKind.MAIN_DECL) {
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
        if (chirType.Has(decl)) {
            return
        }
        let packageName = EffectivePackageName(decl)
        let identifier = EffectiveMangledName(decl)
        let srcIdentifier = decl.identifier.Val()
        var customTypeDef: CustomTypeDef
        match (decl.astKind) {
            case ASTKind.STRUCT_DECL =>
                let def = builder.CreateStructDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedStruct(def) } else { CurrentPackage().AddStruct(def) }
            case ASTKind.CLASS_DECL =>
                let def = builder.CreateClassDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.INTERFACE_DECL =>
                let def = builder.CreateClassDef(packageName, identifier, isClass: false)
                def.SetSrcCodeIdentifier(srcIdentifier)
                def.EnableAttr(Attribute.ABSTRACT)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedClass(def) } else { CurrentPackage().AddClass(def) }
            case ASTKind.ENUM_DECL =>
                let def = builder.CreateEnumDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedEnum(def) } else { CurrentPackage().AddEnum(def) }
            case ASTKind.EXTEND_DECL =>
                let def = builder.CreateExtendDef(packageName, identifier)
                def.SetSrcCodeIdentifier(srcIdentifier)
                customTypeDef = def
                if (isImported) { CurrentPackage().AddImportedExtend(def) } else { CurrentPackage().AddExtend(def) }
            case _ =>
                throw IllegalArgumentException(
                    "faithful AST2CHIR CreateCustomTypeDef expected nominal decl, got ${ASTKindName(decl.astKind)}")
        }
        ApplyDeclAttrs(customTypeDef, decl)
        MaybeSetCoreBuiltinClassTy(customTypeDef)
        chirType.SetGlobalNominalCache(decl, customTypeDef)
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
                return Some(translated)
            }
        }
        return None
    }

    private func TranslateNominalDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(importedNominalDecls, trans)
        TranslateVecDecl(genericNominalDecls, trans)
        TranslateVecDecl(nominalDecls, trans)
        TranslateVecDecl(importedGenericInstantiatedNominalDecls, trans)
    }

    private func TranslateOtherTopLevelDecls(node: AstPackage): Unit {
        let _ = node
        let trans = CreateTranslator()
        TranslateVecDecl(globalAndMemberFuncs, trans)
        TranslateVecDecl(localConstFuncs.stableOrderValue, CreateTranslator())
        TranslateVecDecl(globalAndStaticVars, trans)
        SetCompileTimeValueFlag()
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

    private func SetInitFuncForStaticVar(): Unit {
        let initOrder = GlobalDeclAnalysis()
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "")
        CreatePackageInit(nodeInitOrder: initOrder, suffix: "_literal")
    }

    private func AST2CHIRCheck(): Unit {
        let result = CHIRChecker().CheckPackage(CurrentPackage())
        if (!result.ok) {
            failure = true
            failureReason = result.ToString()
        }
    }

    private func TranslateVecDecl(decls: ArrayList<AstDecl>, trans: Translator): Unit {
        for (decl in decls) {
            let _ = Translator.TranslateASTNode(decl, trans)
        }
    }

    private func CreateTranslator(): Translator {
        return Translator(builder, chirType, globalCache, localConstVars: localConstVars, localConstFuncs: localConstFuncs,
            overrideSrcFuncResolver: overrideSrcFuncResolver)
    }

    private func GlobalDeclAnalysis(): ArrayList<FaithfulInitFileVars> {
        let funcsAndVars = ElementList()
        let fileAndVarMap = ArrayList<FaithfulInitFileVars>()
        CollectStaticInitFuncInfo()
        CollectFuncsAndVars(funcsAndVars, fileAndVarMap)

        let nodesWithDeps = ElementList()
        for (element in funcsAndVars.stableOrderValue) {
            nodesWithDeps.AddElement(element)
        }
        return Run(nodesWithDeps, fileAndVarMap, funcsAndVars)
    }

    private func CollectStaticInitFuncInfo(): Unit {
        for (funcDecl in globalAndMemberFuncs) {
            if (!AstIsStaticInitializer(funcDecl)) {
                continue
            }
            let staticVars = ArrayList<AstDecl>()
            var staticInitVar: Option<AstDecl> = None
            let outerDecl = funcDecl.outerDecl.getOrThrow()
            for (member in outerDecl.GetMemberDecls()) {
                if (let Some(memberVar) <- (member as AstVarDecl)) {
                    if (!memberVar.TestAttr(AstAttribute.STATIC)) {
                        continue
                    }
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
        FlatternLocalConstVars()
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
        let _ = fileAndVarMap
        let funcsAndVarsDepMap = DeclDepMap()
        AnalysisDependency(nodesWithDeps, funcsAndVarsDepMap, funcsAndVars)

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
        return sortedFiles
    }

    private func AnalysisDependency(nodesWithDeps: ElementList, funcsAndVarsDepMap: DeclDepMap,
        funcsAndVars: ElementList): Unit {
        let globalVarSet = BuildDeclSet(globalAndStaticVars)
        let candidateSet = BuildDeclSet(funcsAndVars.stableOrderValue)
        for (localConstVar in localConstVars.stableOrderValue) {
            candidateSet.Add(localConstVar)
        }
        let patternOwnerMap = BuildPatternDependencyOwnerMap()
        for (node in nodesWithDeps.stableOrderValue) {
            if (let Some(varDecl) <- (node as AstVarDecl)) {
                if (varDecl.TestAttr(AstAttribute.STATIC) && !varDecl.TestAttr(AstAttribute.DEFAULT)) {
                    continue
                }
            }
            funcsAndVarsDepMap.AddDeps(node, CollectDirectDependencies(node, candidateSet, globalVarSet, patternOwnerMap))
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
                if (rootFile.objectId == depFile.objectId) {
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
        globalVarSet: FaithfulInitDeclSet, patternOwnerMap: FaithfulInitDeclOwnerMap): ArrayList<AstDecl> {
        let dependencies = ArrayList<AstDecl>()
        let dependencySet = FaithfulInitDeclSet()
        let visitor = { node: AstNode =>
            if (let Some(expr) <- (node as AstExpr)) {
                CollectExprDependency(expr, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            AstVisitAction.WALK_CHILDREN
        }
        AstWalker(root, visitPre: visitor).Walk()
        return dependencies
    }

    private func BuildPatternDependencyOwnerMap(): FaithfulInitDeclOwnerMap {
        let out = FaithfulInitDeclOwnerMap()
        for (candidate in globalAndStaticVars) {
            if (let Some(varWithPattern) <- (candidate as AstVarWithPatternDecl)) {
                if (let Some(pattern) <- varWithPattern.irrefutablePattern) {
                    AddPatternDependencyOwners(pattern, varWithPattern, out)
                }
            }
        }
        return out
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

    private func CollectExprDependency(expr: AstExpr, dependencies: ArrayList<AstDecl>,
        dependencySet: FaithfulInitDeclSet, candidateSet: FaithfulInitDeclSet, globalVarSet: FaithfulInitDeclSet,
        patternOwnerMap: FaithfulInitDeclOwnerMap): Unit {
        if (let Some(callExpr) <- (expr as AstCallExpr)) {
            if (let Some(callee) <- callExpr.resolvedFunction) {
                AddDependency(callee, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return
        }
        if (let Some(member) <- (expr as AstMemberAccess)) {
            if (let Some(target) <- member.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
            return
        }
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (target.astKind == ASTKind.FUNC_DECL || IsGlobalOrStaticVarDecl(target)) {
                    AddDependency(target, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
                }
            }
            return
        }
        if (let Some(arrayExpr) <- (expr as AstArrayExpr)) {
            if (let Some(initFunc) <- arrayExpr.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
            return
        }
        if (let Some(arrayLit) <- (expr as AstArrayLit)) {
            if (let Some(initFunc) <- arrayLit.initFunc) {
                AddDependency(initFunc, dependencies, dependencySet, candidateSet, globalVarSet, patternOwnerMap)
            }
        }
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

    private func IsGlobalOrStaticVarDecl(decl: AstDecl): Bool {
        return (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
            decl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)
    }

    private func ReplaceSrcCodeImportedValAfterConstEval(pkg: Package): Unit {
        let initFuncsToRemove = ArrayList<Function>()
        for (decl in globalAndMemberFuncs) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            let fn = (globalCache.Get(decl) as Function) ?? continue
            fn.DestroyFuncBody()
        }
        for (decl in globalAndStaticVars) {
            if (!IsSrcCodeImportedGlobalDecl(decl)) {
                continue
            }
            let globalVar = (globalCache.Get(decl) as GlobalVar) ?? continue
            if (let Some(initFunc) <- globalVar.GetInitFunc()) {
                if (!ContainsFunction(initFuncsToRemove, initFunc)) {
                    initFuncsToRemove.add(initFunc)
                }
            }
            globalVar.DestroyInitializer()
        }
        if (initFuncsToRemove.isEmpty()) {
            return
        }
        let newFuncs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (!ContainsFunction(initFuncsToRemove, fn)) {
                newFuncs.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(newFuncs)
    }

    private func ContainsFunction(functions: ArrayList<Function>, target: Function): Bool {
        for (fn in functions) {
            if (fn == target) {
                return true
            }
        }
        return false
    }

    private func CreatePackageInit(nodeInitOrder!: ArrayList<FaithfulInitFileVars>, suffix!: String): Unit {
        let pkg = CurrentPackage()
        let packageInit = GeneratePackageInitBase(suffix)
        packageInit.EnableAttr(Attribute.PUBLIC)
        if (suffix == "_literal") {
            pkg.SetPackageLiteralInitFunc(packageInit)
        } else {
            pkg.SetPackageInitFunc(packageInit)
        }
        let initBlock = GetBlockWithInitializers(packageInit)
        let importsInitFunc = CreateImportsInitFunc(suffix)
        InsertInitializerIntoPackageInitializer(importsInitFunc, packageInit)
        UpdateImportsInit(importsInitFunc, suffix)
        if (suffix != "_literal") {
            AddGenericInstantiatedInit(initBlock)
        }
        for (fileVars in nodeInitOrder) {
            if (fileVars.vars.isEmpty()) {
                continue
            }
            if (suffix == "_literal" && IsImportedInitEntry(fileVars)) {
                TranslateImportedFileLiteralInitializer(fileVars, initBlock)
                continue
            }
            if (!fileVars.vars.isEmpty() && IsSymbolImportedDecl(fileVars.vars[0])) {
                continue
            }
            let fileInit = if (suffix == "_literal") {
                TranslateFileLiteralInitializer(fileVars)
            } else {
                TranslateFileInitializer(fileVars)
            }
            if (let Some(initFn) <- fileInit) {
                InsertInitializerIntoPackageInitializer(initFn, packageInit)
            }
        }
        if (initBlock.GetTerminator().isNone()) {
            builder.CreateExit(None, initBlock)
        }
    }

    private func GeneratePackageInitBase(suffix: String): Function {
        let pkg = CurrentPackage()
        let packageInit = CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix),
            PackageInitFuncName(pkg.GetName(), suffix), "", pkg.GetName())
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
        initFlag.SetInitializer(builder.CreateLiteralValue(BoolLiteral(false), boolTy))
        AddGlobalVarToPackage(initFlag)
        return initFlag
    }

    private func CreateImportsInitFunc(suffix: String): Function {
        let pkg = CurrentPackage()
        let importsInit = CreateEmptyGVInitFunc(PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"),
            PackageInitFuncName(pkg.GetName(), suffix + "_importsInit"), "", pkg.GetName())
        importsInit.SetLinkage(Linkage.INTERNAL)
        let entry = RequireEntryBlock(importsInit)
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return importsInit
    }

    private func UpdateImportsInit(importsInitFunc: Function, suffix: String): Unit {
        let block = DropExitNodeOfInitializer(importsInitFunc)
        for (importedPackage in DirectImportedPackages()) {
            if (importedPackage.isMacroPackage) {
                continue
            }
            let pkgName = importedPackage.fullPackageName
            let initFuncName = PackageInitFuncName(pkgName, suffix)
            if (opts.IsCompilingCJMPSpecific()) {
                if (let Some(existing) <- CurrentPackage().TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + initFuncName)) {
                    if (existing.TestAttr(Attribute.DESERIALIZED) ||
                        existing.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                        continue
                    }
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
            AddFunctionToPackage(fn)
            InsertInitializerIntoPackageInitializer(fn, importsInitFunc)
        }
        if (block.GetTerminator().isNone()) {
            builder.CreateExit(None, block)
        }
    }

    private func InsertInitializerIntoPackageInitializer(initFn: Function, packageInit: Function): Unit {
        InsertInitializerIntoBlock(initFn, GetBlockWithInitializers(packageInit))
    }

    private func InsertInitializerIntoBlock(initFn: Function, block: Block): Unit {
        CreateInitFuncApply(initFn, block)
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
        if (let Some(block) <- packageInitializerBlocks.get(fn.nodeId)) {
            return block
        }
        return RequireEntryBlock(fn)
    }

    private func TranslateFileInitializer(fileVars: FaithfulInitFileVars): Option<Function> {
        if (fileVars.vars.isEmpty()) {
            return None
        }
        if (IsSymbolImportedDecl(fileVars.vars[0])) {
            return None
        }
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (let Some(initFunc) <- TranslateSingleInitializer(varDecl)) {
                    initFuncs.add(initFunc)
                }
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                if (let Some(initFunc) <- TranslateVarWithPatternInitializer(varWithPattern)) {
                    initFuncs.add(initFunc)
                }
            }
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, ""), FileInitFuncName(fileVars.file, ""),
            "", FileOwnerPackageName(fileVars.file))
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
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
        let initFuncs = ArrayList<Function>()
        for (decl in fileVars.vars) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (NeedVarLiteralInitFunc(varDecl)) {
                    initFuncs.add(CreateGlobalVarStoreInitFunc(varDecl, suffix: "$literal"))
                }
            }
        }
        if (initFuncs.isEmpty()) {
            return None
        }
        let fileInit = CreateEmptyGVInitFunc(FileInitFuncName(fileVars.file, "_literal"),
            FileInitFuncName(fileVars.file, "_literal"), "", FileOwnerPackageName(fileVars.file))
        let entry = RequireEntryBlock(fileInit)
        for (initFunc in initFuncs) {
            CreateInitFuncApply(initFunc, entry)
        }
        if (entry.GetTerminator().isNone()) {
            builder.CreateExit(None, entry)
        }
        return fileInit
    }

    private func TranslateSingleInitializer(varDecl: AstVarDecl): Option<Function> {
        if (varDecl.initializer.isNone() || varDecl.specificImplementation.isSome()) {
            return None
        }
        if (!NeedInitGlobalVarByInitFunc(varDecl)) {
            SetLiteralInitializer(varDecl)
            return None
        }
        return CreateGlobalVarStoreInitFunc(varDecl, suffix: "")
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

    private func CreateGlobalVarStoreInitFunc(varDecl: AstVarDecl, suffix!: String): Function {
        let initFn = CreateEmptyGVInitFunc(GlobalVarInitFuncName(varDecl),
            "gv$_" + varDecl.identifier.Val() + suffix, EffectiveRawMangledName(varDecl),
            EffectivePackageName(varDecl))
        if (varDecl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
            if (suffix != "$literal") {
                initFuncsForConstVar.add(initFn)
            }
        }
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        if (suffix != "$literal") {
            globalVar.SetInitFunc(initFn)
        }
        CreateTranslator().TranslateGlobalVarInitializer(initFn, varDecl, globalVar)
        return initFn
    }

    private func CreateGlobalVarWithPatternInitFunc(decl: AstVarWithPatternDecl): Function {
        let initFn = CreateEmptyGVInitFunc(GlobalVarWithPatternInitFuncName(decl),
            GlobalVarWithPatternInitSrcName(decl), EffectiveRawMangledName(decl), EffectivePackageName(decl))
        if (decl.IsConst()) {
            initFn.EnableAttr(Attribute.CONST)
            initFuncsForConstVar.add(initFn)
        }
        let varDecls = ArrayList<AstVarDecl>()
        FlattenGlobalVarWithPatternDecl(RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern"),
            varDecls)
        for (varDecl in varDecls) {
            RequireGlobalVar(globalCache.Get(varDecl)).SetInitFunc(initFn)
        }
        CreateTranslator().TranslateGlobalVarWithPatternInitializer(initFn, decl)
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
        let litExpr = (RequireExpr(varDecl.initializer, "literal global initializer") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR literal global initializer expected LitConstExpr")
        let globalVar = RequireGlobalVar(globalCache.Get(varDecl))
        globalVar.SetInitializer(TranslateLitConstant(litExpr, RequireAstTy(litExpr)))
        if (!varDecl.isVar) {
            return false
        }
        return true
    }

    private func NeedInitGlobalVarByInitFunc(varDecl: AstVarDecl): Bool {
        if (let None <- varDecl.initializer) {
            return false
        }
        if (varDecl.IsCommonOrSpecific()) {
            return true
        }
        let initExpr = RequireExpr(varDecl.initializer, "global variable initializer")
        if (let Some(litExpr) <- (initExpr as AstLitConstExpr)) {
            if (IsSimpleLiteralValue(litExpr)) {
                let declTy = chirType.TranslateType(RequireAstTy(varDecl))
                if (IsStringGlobalLiteralInit(litExpr, declTy)) {
                    return true
                }
                let initTy = chirType.TranslateType(RequireAstTy(initExpr))
                return !declTy.IsEqual(initTy)
            }
        }
        return true
    }

    private func IsStringGlobalLiteralInit(litExpr: AstLitConstExpr, declTy: Type): Bool {
        if (litExpr.kind != AstLitConstKind.STRING && litExpr.kind != AstLitConstKind.JSTRING) {
            return false
        }
        return declTy.IsString()
    }

    private func IsSimpleLiteralValue(expr: AstLitConstExpr): Bool {
        return match (expr.kind) {
            case AstLitConstKind.BOOL => true
            case AstLitConstKind.UNIT => true
            case AstLitConstKind.INTEGER => true
            case AstLitConstKind.RUNE_BYTE => true
            case AstLitConstKind.FLOAT => true
            case AstLitConstKind.RUNE => true
            case AstLitConstKind.STRING => true
            case AstLitConstKind.JSTRING => true
            case AstLitConstKind.NONE => false
        }
    }

    private func TranslateLiteralValue(expr: AstLitConstExpr): LiteralValue {
        let kind = RequireAstTy(expr).kind
        return match (kind) {
            case AstTypeKind.TYPE_UNIT => UnitLiteral()
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT32 | AstTypeKind.TYPE_FLOAT64 |
                AstTypeKind.TYPE_IDEAL_FLOAT => FloatLiteral(expr.constNumValue.asFloat.value)
            case AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 | AstTypeKind.TYPE_UINT32 |
                AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE | AstTypeKind.TYPE_INT8 |
                AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 | AstTypeKind.TYPE_INT64 |
                AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT => TranslateIntegerLiteralValue(expr)
            case AstTypeKind.TYPE_RUNE => RuneLiteral(Rune(expr.codepoint[0]))
            case AstTypeKind.TYPE_BOOLEAN => BoolLiteral(expr.stringValue == "true")
            case AstTypeKind.TYPE_STRUCT => StringLiteral(expr.stringValue)
            case _ =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: literal type")
        }
    }

    private func TranslateLitConstant(expr: AstLitConstExpr, realTy: AstTy): LiteralValue {
        let chirTyToTrans = chirType.TranslateType(realTy)
        return match (realTy.kind) {
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT64 | AstTypeKind.TYPE_IDEAL_FLOAT =>
                builder.CreateLiteralValue(FloatLiteral(expr.constNumValue.asFloat.value), chirTyToTrans)
            case AstTypeKind.TYPE_FLOAT32 =>
                builder.CreateLiteralValue(
                    FloatLiteral(Float64(Float32(Float64.parse(expr.stringValue.replace("_", ""))))), chirTyToTrans)
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

    private func CreateEmptyGVInitFunc(identifier: String, srcCodeIdentifier: String, rawMangledName: String,
        packageName: String): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let effectiveRawName = if (rawMangledName.isEmpty()) { identifier } else { rawMangledName }
        let fn = builder.CreateFunction(funcTy, identifier, srcCodeIdentifier: srcCodeIdentifier,
            rawMangledName: effectiveRawName, packageName: packageName)
        fn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        AddFunctionToPackage(fn)
        return fn
    }

    private func CreateInitFuncApply(initFn: Function, block: Block): Unit {
        builder.CreateApply(builder.context.GetVoidTy(), initFn, FuncCallContext(), block)
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

    private func EnsureReturnSlot(fn: Function, entry: Block): Unit {
        if (let Some(returnTy) <- fn.GetReturnType()) {
            if (returnTy.IsVoid()) {
                return
            }
            if (let Some(retValue) <- builder.CreateAllocate(builder.context.GetRefTy(returnTy), returnTy,
                entry).GetResult()) {
                fn.SetReturnValue(retValue)
            }
        }
    }

    private func CreateFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveFunctionIdentifier(funcDecl),
            srcCodeIdentifier: EffectiveFunctionSrcIdentifier(funcDecl), rawMangledName: EffectiveFunctionRawName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
        SetOverrideSrcFuncType(funcDecl, fn)
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
        }
        if (!funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            let entry = builder.CreateBlock(body)
            body.SetEntryBlock(entry)
            EnsureReturnSlot(fn, entry)
        }
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func CreateImportedFuncSignatureAndSetGlobalCache(funcDecl: AstFuncDecl): Unit {
        let funcTy = AdjustFuncType(funcDecl, RequireFuncType(chirType.TranslateType(RequireAstTy(funcDecl))))
        let fn = builder.CreateFunction(funcTy, EffectiveMangledName(funcDecl),
            srcCodeIdentifier: funcDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(funcDecl),
            packageName: EffectivePackageName(funcDecl))
        AttachFunctionGenericParams(funcDecl, fn)
        fn.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(fn, funcDecl)
        ApplyFuncKind(fn, funcDecl)
        SetOverrideSrcFuncType(funcDecl, fn)
        TranslateFuncParams(funcDecl, fn)
        globalCache.Set(funcDecl, fn)
        AddFunctionToPackage(fn)
    }

    private func SetOverrideSrcFuncType(funcDecl: AstFuncDecl, fn: Function): Unit {
        let resolver = overrideSrcFuncResolver ?? return
        let overrideSrcFuncDecl = resolver(funcDecl) ?? return
        let overrideSrcFuncTy = AdjustFuncType(overrideSrcFuncDecl,
            RequireFuncType(chirType.TranslateType(RequireAstTy(overrideSrcFuncDecl))))
        fn.SetOverrideSrcFuncType(overrideSrcFuncTy)
    }

    private func CreateImportedValueSignatureAndSetGlobalCache(varDecl: AstVarDecl): Unit {
        let varTy = chirType.TranslateType(RequireAstTy(varDecl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(varDecl),
            srcCodeIdentifier: varDecl.identifier.Val(), rawMangledName: EffectiveRawMangledName(varDecl),
            packageName: EffectivePackageName(varDecl))
        globalVar.EnableAttr(Attribute.IMPORTED)
        ApplyDeclAttrs(globalVar, varDecl)
        globalCache.Set(varDecl, globalVar)
        AddGlobalVarToPackage(globalVar)
    }

    private func CreateGlobalVarSignature(decls: ArrayList<AstDecl>, isLocalConst!: Bool = false): Unit {
        for (decl in decls) {
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                let _ = CreateAndCacheGlobalVar(varDecl, isLocalConst: isLocalConst)
            } else if (let Some(varWithPattern) <- (decl as AstVarWithPatternDecl)) {
                let varDecls = ArrayList<AstVarDecl>()
                FlattenGlobalVarWithPatternDecl(RequirePattern(varWithPattern.irrefutablePattern,
                    "global var-with-pattern pattern"), varDecls)
                for (varDecl in varDecls) {
                    let _ = CreateAndCacheGlobalVar(varDecl, isLocalConst: isLocalConst)
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
        let varTy = chirType.TranslateType(RequireAstTy(decl))
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(varTy), EffectiveMangledName(decl),
            srcCodeIdentifier: decl.identifier.Val(), rawMangledName: EffectiveRawMangledName(decl),
            packageName: EffectivePackageName(decl))
        globalVar.SetDebugLocation(TranslateLocationWithoutScope(builder.context, decl.begin, decl.end))
        ApplyDeclAttrs(globalVar, decl)
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
        AddGlobalVarToPackage(globalVar)
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

    private func ApplyFuncKind(fn: Function, funcDecl: AstFuncDecl): Unit {
        if (funcDecl.isGetter) {
            fn.SetFuncKind(FuncKind.GETTER)
            return
        }
        if (funcDecl.isSetter) {
            fn.SetFuncKind(FuncKind.SETTER)
            return
        }
        if (funcDecl.IsFinalizer()) {
            fn.SetFuncKind(FuncKind.FINALIZER)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MAIN_ENTRY)) {
            fn.SetFuncKind(FuncKind.MAIN_ENTRY)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.MACRO_FUNC)) {
            fn.SetFuncKind(FuncKind.MACRO_FUNC)
            return
        }
        if (funcDecl.TestAttr(AstAttribute.PRIMARY_CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.PRIMAL_CLASS_CONSTRUCTOR)
                return
            }
        } else if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            if (IsStructMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.STRUCT_CONSTRUCTOR)
                return
            }
            if (IsClassLikeMemberFunc(funcDecl)) {
                fn.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
                return
            }
        }
        if (funcDecl.TestAttr(AstAttribute.HAS_INITIAL)) {
            fn.SetFuncKind(FuncKind.DEFAULT_PARAMETER_FUNC)
        }
    }

    private func IsStructMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_STRUCT)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.STRUCT_DECL
        }
        return false
    }

    private func IsClassLikeMemberFunc(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAttr(AstAttribute.IN_CLASSLIKE)) {
            return true
        }
        if (let Some(outerDecl) <- funcDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.CLASS_DECL || outerDecl.astKind == ASTKind.INTERFACE_DECL
        }
        return false
    }

    private func AddFunctionToPackage(fn: Function): Unit {
        CurrentPackage().AddGlobalFunc(fn)
    }

    private func AddGlobalVarToPackage(globalVar: GlobalVar): Unit {
        CurrentPackage().AddGlobalVar(globalVar)
    }

    private func ApplyDeclAttrs(target: Base, decl: AstDecl): Unit {
        if (decl.TestAttr(AstAttribute.PUBLIC)) { target.EnableAttr(Attribute.PUBLIC) }
        if (decl.TestAttr(AstAttribute.PROTECTED)) { target.EnableAttr(Attribute.PROTECTED) }
        if (decl.TestAttr(AstAttribute.PRIVATE)) { target.EnableAttr(Attribute.PRIVATE) }
        if (decl.TestAttr(AstAttribute.STATIC)) { target.EnableAttr(Attribute.STATIC) }
        if (decl.TestAttr(AstAttribute.MUT)) { target.EnableAttr(Attribute.MUT) }
        if (decl.IsConst()) { target.EnableAttr(Attribute.CONST) }
        if (decl.TestAttr(AstAttribute.ABSTRACT)) { target.EnableAttr(Attribute.ABSTRACT) }
        if (decl.TestAttr(AstAttribute.OPEN)) { target.EnableAttr(Attribute.VIRTUAL) }
        if (decl.TestAttr(AstAttribute.FOREIGN)) { target.EnableAttr(Attribute.FOREIGN) }
        if (decl.TestAttr(AstAttribute.IMPORTED)) { target.EnableAttr(Attribute.IMPORTED) }
        if (decl.TestAttr(AstAttribute.SRC_IMPORTED)) { target.EnableAttr(Attribute.SRC_CODE_IMPORTED) }
        if (decl.TestAttr(AstAttribute.C)) {
            target.EnableAttr(Attribute.C)
            if (let Some(structDef) <- (target as StructDef)) {
                structDef.SetCStruct(true)
            }
        }
        if (decl.TestAttr(AstAttribute.OPERATOR)) { target.EnableAttr(Attribute.OPERATOR) }
        if (decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) { target.EnableAttr(Attribute.GENERIC_INSTANTIATED) }
        if (decl.TestAttr(AstAttribute.IMPLICIT_ADD)) { target.EnableAttr(Attribute.IMPLICIT_ADD) }
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
