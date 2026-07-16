package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.ASTMangler
import cjcj::modules.SemaImportManager
import cjcj::utils.{CFUNC_NAME, CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, CPOINTER_NAME, CSTRING_NAME,
    IncrementalCompilationLogger}

public enum Idx {
    | BODY
    | API
}

public class TypeMap {
    public let interfaceExtendTypes: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let children: HashMap<Decl, HashSet<Decl>> = HashMap<Decl, HashSet<Decl>>()
    private let extend2Decl: HashMap<String, String> = HashMap<String, String>()
    private let extends: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    public init() {}

    public func AddParent(parent: Decl, child: Decl): Unit {
        if (!children.contains(parent)) {
            children[parent] = HashSet<Decl>()
        }
        children[parent].add(child)
    }

    public static func TruncateExtendName(mangled: String): String {
        if (let Some(pos) <- mangled.indexOf("<:")) {
            return mangled[0..pos]
        }
        CJC_ABORT()
        return ""
    }

    public func FindExtendedTypeByExtendDeclMangleName(mangle: String): Option<String> {
        return extend2Decl.get(mangle)
    }

    public func GetAllExtendsOfType(decl: String): ArrayList<String> {
        if (let Some(values) <- extends.get(decl)) {
            return values
        }
        return ArrayList<String>()
    }

    public func AddExtend(extendedType: String, extendName: String): Unit {
        if (!extends.contains(extendedType)) {
            extends[extendedType] = ArrayList<String>()
        }
        extends[extendedType].add(extendName)
        extend2Decl[extendName] = extendedType
    }

    public func CollectImportedDeclExtraRelation(decl: Decl): Unit {
        if (!decl.IsNominalDecl()) {
            return
        }
        let inheritableDecl = (decl as InheritableDecl).getOrThrow()
        for (parentType in inheritableDecl.inheritedTypes) {
            let parentDecl = Ty.GetDeclOfTy(parentType.GetTy())
            CJC_NULLPTR_CHECK(parentDecl)
            AddParent(parentDecl.getOrThrow(), decl)
        }
        if (let Some(extendDecl) <- (inheritableDecl as ExtendDecl)) {
            AddExtend(GetTypeRawMangleName(extendDecl.GetTy().getOrThrow()), decl.rawMangleName)
        }
    }

    public func Merge(other: TypeMap): Unit {
        for ((extendName, typeName) in other.extend2Decl) {
            if (!extend2Decl.contains(extendName)) {
                extend2Decl[extendName] = typeName
            }
        }
        for ((parent, childSet) in other.children) {
            if (!children.contains(parent)) {
                children[parent] = HashSet<Decl>()
            }
            for (child in childSet) {
                children[parent].add(child)
            }
        }
        for ((typeName, extendList) in other.extends) {
            if (!extends.contains(typeName)) {
                extends[typeName] = ArrayList<String>()
            }
            for (extendName in extendList) {
                extends[typeName].add(extendName)
            }
        }
        CJC_ASSERT(other.interfaceExtendTypes.isEmpty())
    }
}

public class QualifiedUsage <: Hashable & Equatable<QualifiedUsage> {
    public var leftDecl: String = ""
    public var name: String = ""

    public init() {}

    public init(leftDecl: String, name: String) {
        this.leftDecl = leftDecl
        this.name = name
    }

    public operator func ==(right: QualifiedUsage): Bool {
        return leftDecl == right.leftDecl && name == right.name
    }

    public operator func !=(right: QualifiedUsage): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return name.hashCode() ^ leftDecl.hashCode()
    }
}

public type UnqualifiedName2Usages = HashMap<String, HashMap<Decl, HashSet<Decl>>>
public type QualifiedName2Usages = HashMap<QualifiedUsage, HashSet<Decl>>
public type PackageQualifiedUsages = HashMap<String, HashMap<String, HashSet<Decl>>>

public class Pack<T> {
    public let body: T
    public let api: T

    public init(body: T, api: T) {
        this.body = body
        this.api = api
    }

    public operator func [](index: Idx): T {
        return match (index) {
            case Idx.BODY => body
            case Idx.API => api
        }
    }
}

public class ChangePollutedMap {
    public let unqUses: Pack<UnqualifiedName2Usages> =
        Pack<UnqualifiedName2Usages>(UnqualifiedName2Usages(), UnqualifiedName2Usages())
    public let unqUsesOfImported: Pack<UnqualifiedName2Usages> =
        Pack<UnqualifiedName2Usages>(UnqualifiedName2Usages(), UnqualifiedName2Usages())
    public let qUses: Pack<QualifiedName2Usages> =
        Pack<QualifiedName2Usages>(QualifiedName2Usages(), QualifiedName2Usages())
    public let pqUses: Pack<PackageQualifiedUsages> =
        Pack<PackageQualifiedUsages>(PackageQualifiedUsages(), PackageQualifiedUsages())
    public let directUses: Pack<HashMap<RawMangledName, HashSet<Decl>>> =
        Pack<HashMap<RawMangledName, HashSet<Decl>>>(HashMap<RawMangledName, HashSet<Decl>>(),
            HashMap<RawMangledName, HashSet<Decl>>())
    public let boxUses: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    public let packageAliasMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let declAliasMap: HashMap<String, HashMap<String, HashSet<String>>> =
        HashMap<String, HashMap<String, HashSet<String>>>()

    public init() {}

    public func GetUnqUses(getImportOnly: Bool, index: Idx, identifier: String,
        scope: Decl): HashSet<Decl> {
        let container = if (getImportOnly) { unqUsesOfImported[index] } else { unqUses[index] }
        if (let Some(scopeMap) <- container.get(identifier)) {
            if (let Some(usages) <- scopeMap.get(scope)) {
                return usages
            }
        }
        return HashSet<Decl>()
    }

    public func GetQUses(index: Idx, identifier: String): HashSet<Decl> {
        let container = qUses[index]
        let usages = HashSet<Decl>()
        for ((usage, decls) in container) {
            if (usage.name == identifier) {
                for (decl in decls) {
                    usages.add(decl)
                }
            }
        }
        return usages
    }

    public func GetPackageQualifiedUses(index: Idx, identifier: String,
        packageName: String): HashSet<Decl> {
        let container = pqUses[index]
        if (let Some(pkgMap) <- container.get(identifier)) {
            if (let Some(values) <- pkgMap.get(packageName)) {
                return values
            }
        }
        return HashSet<Decl>()
    }

    public func GetAccessibleDeclName(decl: Decl): HashSet<String> {
        if (let Some(names) <- declAliasMap.get(decl.fullPackageName)) {
            if (let Some(values) <- names.get(decl.identifier.Val())) {
                return values
            }
        }
        let out = HashSet<String>()
        out.add(decl.identifier.Val())
        return out
    }

    public func GetAccessiblePackageName(fullPackageName: String): HashSet<String> {
        if (let Some(values) <- packageAliasMap.get(fullPackageName)) {
            return values
        }
        let out = HashSet<String>()
        out.add(fullPackageName)
        return out
    }

}

public enum IncreKind {
    | NO_CHANGE
    | INCR
    | ROLLBACK
    | EMPTY_PKG
    | INVALID
}

public func IncreKindIndex(kind: IncreKind): Int64 {
    return match (kind) {
        case IncreKind.NO_CHANGE => 0
        case IncreKind.INCR => 1
        case IncreKind.ROLLBACK => 2
        case IncreKind.EMPTY_PKG => 3
        case IncreKind.INVALID => 4
    }
}

extend IncreKind <: Equatable<IncreKind> {
    public operator func ==(right: IncreKind): Bool {
        return IncreKindIndex(this) == IncreKindIndex(right)
    }

    public operator func !=(right: IncreKind): Bool {
        return !(this == right)
    }
}

public class PollutionResult {
    public var kind: IncreKind = IncreKind.INVALID
    public let declsToRecompile: HashSet<Decl> = HashSet<Decl>()
    public let deleted: ArrayList<String> = ArrayList<String>()
    public let reBoxedTypes: ArrayList<String> = ArrayList<String>()

    public init() {}

    public init(kind: IncreKind) {
        this.kind = kind
    }
}

public class PollutionAnalyseArgs {
    public var rawModified: ModifiedDecls
    public var pkg: PackageDecl
    public var sourcePopulations: SrcImportedDepMap
    public var semaInfo: SemanticInfo
    public var chirOptInfo: OptEffectStrMap
    public var fileMap: CachedFileMap
    public var man: SemaImportManager
    public var mangled2Decl: RawMangled2DeclMap
    public var extends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>
    public var importedRelations: TypeMap

    public init(rawModified: ModifiedDecls, pkg: PackageDecl, sourcePopulations: SrcImportedDepMap,
        semaInfo: SemanticInfo, chirOptInfo: OptEffectStrMap, fileMap: CachedFileMap,
        man: SemaImportManager, mangled2Decl: RawMangled2DeclMap,
        extends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>, importedRelations: TypeMap) {
        this.rawModified = rawModified
        this.pkg = pkg
        this.sourcePopulations = sourcePopulations
        this.semaInfo = semaInfo
        this.chirOptInfo = chirOptInfo
        this.fileMap = fileMap
        this.man = man
        this.mangled2Decl = mangled2Decl
        this.extends = extends
        this.importedRelations = importedRelations
    }
}

private class PollutedCommonChangeRecord {
    public var sig: Bool = false
    public var srcUse: Bool = false
    public var body: Bool = false
}

private class PollutedTypeChangeRecord {
    public var instVar: Bool = false
    public var virt: Bool = false
    public var sig: Bool = false
    public var visibleAPI: Bool = false
    public var srcUse: Bool = false
    public var body: Bool = false
    public var member: Bool = false
}

private class PollutedOtherUseRecord {
    public var instantiation: Bool = false
    public var chirOpt: Bool = false
    public var box: Bool = false
}

private func GetAllMembers(decl: Decl): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    for (member in decl.GetMemberDeclPtrs()) {
        for (nested in GetAllMembers(member)) { result.add(nested) }
        result.add(member)
    }
    if (let Some(propDecl) <- (decl as PropDecl)) {
        for (getter in propDecl.getters) { result.add(getter) }
        for (setter in propDecl.setters) { result.add(setter) }
    }
    return result
}

private func TruncatePrecedingNumber(mangle: String, begin: Int64, end: Int64): Int64 {
    CJC_ASSERT(end <= mangle.size)
    var idx = begin
    let bytes = mangle.toArray()
    while (idx < end) {
        if (bytes[idx] < b'0' || bytes[idx] > b'9') { return idx }
        idx++
    }
    CJC_ASSERT(false)
    return -1
}

private func TruncatePackage(mangle: String, end: Int64): Int64 {
    CJC_ASSERT(end != 0 && end <= mangle.size)
    let bytes = mangle.toArray()
    var idx = end - 1
    while (true) {
        if (bytes[idx] == b'.') { return idx + 1 }
        if (idx == 0) { break }
        idx--
    }
    return 0
}

private func TruncateGeneric(mangle: String): Int64 {
    if (let Some(end) <- mangle.indexOf("<")) {
        return end
    }
    return mangle.size
}

private func GetIdentifierFromTruncatedName(mangle: String): String {
    CJC_ASSERT(!mangle.isEmpty())
    let end = TruncateGeneric(mangle)
    let begin = TruncatePackage(mangle, end)
    let identifierBegin = TruncatePrecedingNumber(mangle, begin, end)
    CJC_ASSERT(end > identifierBegin)
    return mangle[identifierBegin..end]
}

public class PollutionAnalyzer {
    private var p: ChangePollutedMap
    private var t: TypeMap
    private var mangled2Decl: RawMangled2DeclMap
    private let directExtends: HashMap<RawMangledName, ArrayList<ExtendDecl>> =
        HashMap<RawMangledName, ArrayList<ExtendDecl>>()
    private let typeAliases: ArrayList<Decl> = ArrayList<Decl>()
    private let unfoundExtends: ArrayList<Decl> = ArrayList<Decl>()
    private let unfoundNames: ArrayList<String> = ArrayList<String>()
    private let chirOptMap: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    private let changes: HashMap<Decl, PollutedCommonChangeRecord> =
        HashMap<Decl, PollutedCommonChangeRecord>()
    private let typeChanges: HashMap<Decl, PollutedTypeChangeRecord> =
        HashMap<Decl, PollutedTypeChangeRecord>()
    private let removedNotSupported: ArrayList<String> = ArrayList<String>()
    private let otherChanges: HashMap<String, PollutedOtherUseRecord> = HashMap<String, PollutedOtherUseRecord>()
    private let pollutedDecls: HashSet<Decl> = HashSet<Decl>()
    private let deletedDecls: ArrayList<String> = ArrayList<String>()
    private let reBoxedTypes: ArrayList<String> = ArrayList<String>()
    private let visitedBodyPollutedDecls: HashSet<Decl> = HashSet<Decl>()
    private let visitedAPIPollutedDecls: HashSet<Decl> = HashSet<Decl>()

    public init(p: ChangePollutedMap, t: TypeMap, mangled2Decl: RawMangled2DeclMap,
        chirOpt: OptEffectStrMap, extends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>) {
        this.p = p
        this.t = t
        this.mangled2Decl = mangled2Decl
        for ((src, affectedNames) in chirOpt) {
            let affected = ArrayList<Decl>()
            for (name in affectedNames) {
                if (let Some(decl) <- mangled2Decl.get(name)) {
                    affected.add(decl)
                }
            }
            if (!affected.isEmpty()) {
                chirOptMap[src] = affected
            }
        }
        for ((mangle, entries) in extends) {
            let values = ArrayList<ExtendDecl>()
            for (entry in entries) {
                values.add(entry[0])
            }
            directExtends[mangle] = values
        }
    }

    public static func Get(args: PollutionAnalyseArgs): PollutionResult {
        if (!args.rawModified.aliases.isEmpty()) {
            let logger = IncrementalCompilationLogger.GetInstance()
            if (logger.IsEnable()) {
                let message = StringBuilder()
                for (decl in args.rawModified.aliases) {
                    message.append("changed typealias: " + PrintDecl(decl) + "\n")
                }
                logger.LogLn(message.toString())
            }
            return PollutionResult(IncreKind.ROLLBACK)
        }

        let generated = PollutionMapGen.Get(args.pkg, args.mangled2Decl, args.sourcePopulations, args.semaInfo,
            args.chirOptInfo, args.man)
        let typeMap = generated[1]
        typeMap.Merge(args.importedRelations)
        let analyzer = PollutionAnalyzer(generated[0], typeMap, args.mangled2Decl, args.chirOptInfo, args.extends)

        for (decl in args.rawModified.added) {
            analyzer.PollutionForAddedDecl(decl)
        }
        if (analyzer.FallBack()) {
            analyzer.PrintFallbackInfo()
            return PollutionResult(IncreKind.ROLLBACK)
        }

        for (decl in args.rawModified.deletes) {
            analyzer.PollutionForDeletedDecl(decl)
        }
        if (analyzer.FallBack()) {
            analyzer.PrintFallbackInfo()
            return PollutionResult(IncreKind.ROLLBACK)
        }
        for (decl in args.rawModified.deletedTypeAlias) {
            analyzer.removedNotSupported.add(decl)
        }
        if (analyzer.FallBack()) {
            analyzer.PrintFallbackInfo()
            return PollutionResult(IncreKind.ROLLBACK)
        }

        for ((_, change) in args.rawModified.commons) {
            analyzer.PollutionForChangedNonTypeDecl(change)
        }
        if (analyzer.FallBack()) {
            analyzer.PrintFallbackInfo()
            return PollutionResult(IncreKind.ROLLBACK)
        }

        for ((decl, change) in args.rawModified.types) {
            analyzer.PollutionForChangedTypeDecl((decl as InheritableDecl).getOrThrow(), change)
        }
        if (analyzer.FallBack()) {
            analyzer.PrintFallbackInfo()
            return PollutionResult(IncreKind.ROLLBACK)
        }

        for (decl in args.rawModified.orderChanges) {
            analyzer.PollutionForOrderChangeDecl(decl)
        }

        let result = PollutionResult(IncreKind.INCR)
        for (decl in analyzer.pollutedDecls) {
            result.declsToRecompile.add(decl)
        }
        for (name in analyzer.deletedDecls) {
            result.deleted.add(name)
        }
        for (name in analyzer.reBoxedTypes) {
            result.reBoxedTypes.add(name)
        }
        if (result.declsToRecompile.isEmpty() && result.deleted.isEmpty()) {
            result.kind = IncreKind.NO_CHANGE
        }
        return result
    }

    public func AddToPollutedDecls(decl: Decl): Unit {
        pollutedDecls.add(decl)
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (IsImported(funcDecl) && funcDecl.funcBody.isSome()) {
                for (param in funcDecl.funcBody.getOrThrow().paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        desugarDecl.rawMangleName = desugarDecl.mangledName
                        AddToPollutedDecls(desugarDecl)
                    }
                }
            }
        } else if (let Some(varWithPattern) <- (decl as VarWithPatternDecl)) {
            for (pattern in FlattenVarWithPatternDecl(varWithPattern)) {
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    pollutedDecls.add(varPattern.varDecl.getOrThrow())
                }
            }
        }
    }

    public func PollutionForAddedDecl(decl: Decl): Unit {
        if (decl.astKind == ASTKind.TYPE_ALIAS_DECL) {
            typeAliases.add(decl)
            return
        }
        if (decl.IsNominalDecl()) {
            PollutionForAddedTypeDecl(decl)
        } else {
            PollutionForAddedNonTypeDecl(decl)
        }
    }

    public func PollutionForAddedTypeDecl(decl: Decl): Unit {
        if (decl.TestAttr(Attribute.IMPORTED)) {
            let genericImported = IsInDeclWithAttribute(decl, Attribute.GENERIC)
            if (genericImported) {
                AddToPollutedDecls(decl)
                for (member in decl.GetMemberDeclPtrs()) { PollutionForAddedNonTypeDecl(member) }
            } else {
                for (member in decl.GetMemberDeclPtrs()) { PollutionForAddedNonTypeDecl(member) }
            }
        } else {
            AddToPollutedDecls(decl)
            for (member in GetAllMembers(decl)) { PollutionForAddedNonTypeDecl(member) }
        }
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            AdditionPollutionForAddedExtendDecl(extendDecl)
        }
    }

    public func PollutionForAddedNonTypeDecl(decl: Decl): Unit {
        if (decl.TestAttr(Attribute.IMPORTED)) {
            var srcImported = false
            if (let Some(varDecl) <- (decl as VarDecl)) {
                if (varDecl.TestAttr(Attribute.GLOBAL) && varDecl.initializer.isSome()) {
                    srcImported = true
                }
            } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (funcDecl.funcBody.isSome() && funcDecl.funcBody.getOrThrow().body.isSome()) {
                    srcImported = true
                }
            }
            let genericImported = IsInDeclWithAttribute(decl, Attribute.GENERIC)
            if (srcImported || genericImported) {
                AddToPollutedDecls(decl)
            }
        } else {
            AddToPollutedDecls(decl)
        }
        PollutionForAddedNonTypeDeclImpl(decl)
    }

    public func PollutionForAddedNonTypeDeclImpl(decl: Decl): Unit {
        if (let Some(propDecl) <- (decl as PropDecl)) {
            for (getter in propDecl.getters) {
                AddToPollutedDecls(getter)
                PollutionForAddedNonTypeDeclImpl(getter)
            }
            for (setter in propDecl.setters) {
                AddToPollutedDecls(setter)
                PollutionForAddedNonTypeDeclImpl(setter)
            }
        }
        if (let Some(varWithPatternDecl) <- (decl as VarWithPatternDecl)) {
            for (pattern in FlattenVarWithPatternDecl(varWithPatternDecl)) {
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    let variable = varPattern.varDecl.getOrThrow()
                    AddToPollutedDecls(variable)
                    PollutionForAddedNonTypeDeclImpl(variable)
                }
            }
        }
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
    }

    public func AdditionPollutionForBodyChangedExtendDecl(decl: ExtendDecl): Unit {
        if (decl.inheritedTypes.isEmpty()) {
            if (let Some(extendsWithSameName) <- directExtends.get(decl.rawMangleName)) {
                for (extendDecl in extendsWithSameName) {
                    if (!pollutedDecls.contains(extendDecl)) {
                        AddToPollutedDecls(extendDecl)
                        PollutionForAddedTypeDecl(extendDecl)
                    }
                }
            }
        }
    }

    public func AdditionPollutionAPIOfExtendedDecl(decl: ExtendDecl): Unit {
        if (let Some(extendedTypeName) <- GetExtendedTypeRawMangleName(decl)) {
            if (let Some(extendedType) <- mangled2Decl.get(extendedTypeName)) {
                PolluteAPIOfDecl(extendedType)
            } else {
                for (extendName in t.GetAllExtendsOfType(extendedTypeName)) {
                    if (let Some(extendDecl) <- mangled2Decl.get(extendName)) {
                        let extendOfBuiltinDecl = (extendDecl as ExtendDecl).getOrThrow()
                        AddToPollutedDecls(extendOfBuiltinDecl)
                        PollutedInstantiationChangeFromDecl(extendOfBuiltinDecl)
                    }
                }
            }
        }
    }

    public func AdditionPollutionAPIOfExtendDecl(decl: ExtendDecl): Unit {
        AdditionPollutionAPIOfExtendedDecl(decl)
        AdditionPollutionAPIOfDirectExtendDecls(decl.rawMangleName)
    }

    public func AdditionPollutionForAddedExtendDecl(decl: ExtendDecl): Unit {
        if (decl.inheritedTypes.isEmpty() && decl.GetMemberDeclPtrs().isEmpty()) {
            return
        }
        AdditionPollutionAPIOfExtendedDecl(decl)
        AdditionPollutionForBodyChangedExtendDecl(decl)
    }

    public func PollutionForDeletedDecl(mangle: String): Unit {
        deletedDecls.add(mangle)
        PollutePreciseUsages(mangle)
        if (let Some(extendedTypeName) <- t.FindExtendedTypeByExtendDeclMangleName(mangle)) {
            if (let Some(extendedType) <- mangled2Decl.get(extendedTypeName)) {
                PolluteAPIOfDecl(extendedType)
            } else {
                for (extendName in t.GetAllExtendsOfType(extendedTypeName)) {
                    if (let Some(extendDecl) <- mangled2Decl.get(extendName)) {
                        AddToPollutedDecls(extendDecl)
                        PollutedInstantiationChangeFromDecl(extendDecl)
                    }
                }
            }
        } else if (let Some(truncatedExtendName) <- ASTMangler.TruncateExtendMangledName(mangle)) {
            let identifier = GetIdentifierFromTruncatedName(truncatedExtendName)
            let candidateSet = ArrayList<Decl>()
            for ((_, decl) in mangled2Decl) {
                if (decl.identifier == identifier && decl.IsNominalDecl() &&
                    decl.astKind != ASTKind.EXTEND_DECL) {
                    candidateSet.add(decl)
                }
            }
            for (candidate in candidateSet) {
                AddToPollutedDecls(candidate)
                PolluteBoxUsesFromDecl(candidate)
                PollutedInstantiationChangeFromDecl(candidate)
            }
            if (candidateSet.isEmpty()) { PollutedToBoxUses(identifier) }
        }
        for (extendDecl in FindAllExtendDeclsOfType(mangle)) {
            AddToPollutedDecls(extendDecl)
            PollutedInstantiationChangeFromDecl(extendDecl)
        }
    }

    public func PollutionForConstDecl(decl: Decl): Unit {
        AddToPollutedDecls(decl)
        if (decl.TestAttr(Attribute.GENERIC)) {
            PollutedInstantiationChangeFromDecl(decl)
        }
    }

    public func PollutionForOrderChangeDecl(decl: Decl): Unit {
        PollutionForConstDecl(decl)
    }

    public func PollutionForChangedNonTypeDecl(change: CommonChange): Unit {
        AddToPollutedDecls(change.decl)
        if (change.sig) {
            PollutionForSigChangedDecl(change.decl)
        } else if (change.srcUse) {
            PollutionForSrcUseChangedDecl(change.decl)
        } else if (change.body) {
            PollutionForBodyChangedDecl(change.decl)
        }
        if (let Some(parent) <- change.decl.outerDecl) {
            if (IsInDeclWithAttribute(parent, Attribute.GENERIC)) {
                PollutedInstantiationChangeFromDecl(parent)
            }
        }
    }

    public func PollutionForBodyChangedDecl(decl: Decl): Unit {
        if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            if (!typeChanges.contains(typeDecl)) {
                typeChanges[typeDecl] = PollutedTypeChangeRecord()
            }
            let record = typeChanges[typeDecl]
            if (record.body) {
                return
            }
            record.body = true
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                if (let Some(extendedTypeRawMangleName) <- GetExtendedTypeRawMangleName(extendDecl)) {
                    if (let Some(extendedTypeDecl) <- mangled2Decl.get(extendedTypeRawMangleName)) {
                        if (let Some(inheritableDecl) <- (extendedTypeDecl as InheritableDecl)) {
                            PollutionForBodyChangedDecl(inheritableDecl)
                        }
                    } else {
                        for (extendName in t.GetAllExtendsOfType(extendedTypeRawMangleName)) {
                            if (let Some(extendOfBuiltinDecl) <- mangled2Decl.get(extendName)) {
                                AddToPollutedDecls((extendOfBuiltinDecl as ExtendDecl).getOrThrow())
                            }
                        }
                    }
                }
                AdditionPollutionForBodyChangedExtendDecl(extendDecl)
            }
            if (decl.astKind == ASTKind.CLASS_DECL) {
                PolluteDownStreamTypes(decl)
            }
            PolluteBoxUsesFromDecl(decl)
            AddToPollutedDecls(decl)
            PollutedInstantiationChangeFromDecl(decl)
        } else {
            if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
            let record = changes[decl]
            if (record.body) {
                return
            }
            record.body = true
            AddToPollutedDecls(decl)
            if (decl.astKind == ASTKind.PROP_DECL) {
                for (member in GetMembers(decl)) {
                    AddToPollutedDecls(member)
                }
            }
            if (IsUntyped(decl)) {
                PollutionForSigChangedDecl(decl)
            }
            PollutedInstantiationChangeFromDecl(decl)
            if (decl.IsConst()) {
                PollutionForSrcUseChangedDecl(decl)
            }
            PolluteCHIROptAffectDecl(decl)
            if (let Some(parent) <- decl.outerDecl) {
                if (!decl.TestAttr(Attribute.STATIC)) {
                    if (let Some(enclosingType) <- (parent as InheritableDecl)) {
                        PolluteToConstructors(enclosingType)
                    }
                }
            }
        }
    }

    public func PollutionForSigChangedDecl(decl: Decl): Unit {
        match (decl.astKind) {
            case ASTKind.FUNC_DECL | ASTKind.PRIMARY_CTOR_DECL =>
                PollutionForSigChangedFuncDecl(decl)
            case ASTKind.MAIN_DECL | ASTKind.MACRO_DECL =>
                CJC_ABORT()
            case ASTKind.VAR_DECL | ASTKind.FUNC_PARAM =>
                CJC_ASSERT(decl.astKind == ASTKind.VAR_DECL ||
                    (decl.astKind == ASTKind.FUNC_PARAM && (decl as FuncParam).getOrThrow().isMemberParam))
                PollutionForSigChangedVarDecl((decl as VarDecl).getOrThrow())
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                PollutionForSigChangedVarWithPatternDecl((decl as VarWithPatternDecl).getOrThrow())
            case ASTKind.PROP_DECL =>
                PollutionForSigChangedPropDecl((decl as PropDecl).getOrThrow())
            case _ =>
                PollutionForSigChangedInheritableDecl((decl as InheritableDecl).getOrThrow())
        }
    }

    public func PollutionForSigChangedFuncDecl(decl: Decl): Unit {
        if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
        let record = changes[decl]
        if (record.sig) {
            return
        }
        record.sig = true
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
        PollutedInstantiationChangeFromDecl(decl)
        if (let Some(parent) <- decl.outerDecl) {
            if (parent.astKind == ASTKind.EXTEND_DECL) {
                AdditionPollutionAPIOfExtendDecl((parent as ExtendDecl).getOrThrow())
            }
        }
    }

    public func PollutionForSigChangedVarDecl(decl: VarDecl): Unit {
        if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
        let record = changes[decl]
        if (record.sig) {
            return
        }
        record.sig = true
        if (let None <- decl.outerDecl) {
            PollutedUnqualifiedUses(decl)
            PollutedToExprUsages(p.GetPackageQualifiedUses(Idx.BODY, decl.identifier.Val(), decl.fullPackageName))
        } else {
            PollutePreciseUsages(decl)
        }
    }

    public func PollutionForSigChangedVarWithPatternDecl(decl: VarWithPatternDecl): Unit {
        if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
        let record = changes[decl]
        if (record.sig) {
            return
        }
        record.sig = true
        for (pattern in FlattenVarWithPatternDecl(decl)) {
            if (let Some(varPattern) <- (pattern as VarPattern)) {
                PollutionForSigChangedDecl(varPattern.varDecl.getOrThrow())
            }
        }
    }

    public func PollutionForSigChangedPropDecl(decl: PropDecl): Unit {
        if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
        let record = changes[decl]
        if (record.sig) {
            return
        }
        record.sig = true
        for (getter in decl.getters) {
            AddToPollutedDecls(getter)
            PollutionForSigChangedDecl(getter)
        }
        for (setter in decl.setters) {
            AddToPollutedDecls(setter)
            PollutionForSigChangedDecl(setter)
        }
    }

    public func PollutionForSigChangedInheritableDecl(decl: InheritableDecl): Unit {
        if (!typeChanges.contains(decl)) { typeChanges[decl] = PollutedTypeChangeRecord() }
        let record = typeChanges[decl]
        if (record.sig) {
            return
        }
        record.sig = true
        PollutePreciseUsages(decl)
        for (member in decl.GetMemberDeclPtrs()) {
            if (decl.astKind == ASTKind.ENUM_DECL && member.astKind == ASTKind.FUNC_DECL &&
                member.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                continue
            }
            if (member.rawMangleName.isEmpty()) {
                continue
            }
            if (member.astKind == ASTKind.FUNC_DECL || member.astKind == ASTKind.PROP_DECL ||
                member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                PolluteAPIOfDecl(member)
            }
        }
        for (extendDecl in FindAllExtendDeclsOfType(decl.rawMangleName)) {
            PolluteAPIOfDecl(extendDecl)
        }
        PolluteBoxUsesFromDecl(decl)
    }

    public func PollutionForSrcUseChangedDecl(decl: Decl): Unit {
        if (IsEnumConstructor(decl)) {
            return
        }
        if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            if (!typeChanges.contains(typeDecl)) { typeChanges[typeDecl] = PollutedTypeChangeRecord() }
            let typeRecord = typeChanges[typeDecl]
            if (typeRecord.srcUse) {
                return
            }
            typeRecord.srcUse = true
        } else {
            if (!changes.contains(decl)) { changes[decl] = PollutedCommonChangeRecord() }
            let record = changes[decl]
            if (record.srcUse) {
                return
            }
            record.srcUse = true
            for (member in GetAllMembers(decl)) {
                AddToPollutedDecls(member)
                PollutionForSrcUseChangedDecl(member)
            }
        }
        PollutePreciseUsages(decl)
        PolluteBoxUsesFromDecl(decl)
    }

    public func PollutionForChangedTypeDecl(decl: InheritableDecl, change: TypeChange): Unit {
        CJC_ASSERT(decl.astKind == ASTKind.ENUM_DECL || decl.astKind == ASTKind.STRUCT_DECL ||
            decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL ||
            decl.astKind == ASTKind.EXTEND_DECL)
        if (decl.TestAttr(Attribute.IMPORTED) && decl.TestAttr(Attribute.PRIVATE)) {
            AddToPollutedDecls(decl)
            return
        }
        if (change.instVar) {
            AddToPollutedDecls(decl)
            PollutionForLayoutChangedDecl(decl)
        }
        if (change.virtFun) {
            AddToPollutedDecls(decl)
            PollutionForVTableChangedDecl(decl)
        }
        if (change.sig) {
            AddToPollutedDecls(decl)
            PollutionForSigChangedDecl(decl)
        }
        if (change.srcUse) {
            AddToPollutedDecls(decl)
            PollutionForSrcUseChangedDecl(decl)
        }
        if (change.body) {
            AddToPollutedDecls(decl)
            PollutionForBodyChangedDecl(decl)
        }
        if (!change.added.isEmpty() || !change.del.isEmpty() || !change.changed.isEmpty()) {
            PollutedInstantiationChangeFromDecl(decl)
        }
        for (member in change.added) {
            PollutionForAddedDecl(member)
        }
        for (member in change.del) {
            PollutionForDeletedDecl(member)
        }
        for (member in change.changed) {
            PollutionForChangedNonTypeDecl(member)
        }
    }

    public func PolluteBoxUsesFromDecl(decl: Decl): Unit {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- GetExtendedTypeRawMangleName(extendDecl)) {
                PollutedToBoxUses(extendedType)
            }
        } else if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            PollutedToBoxUses(typeDecl.rawMangleName)
        }
    }

    public func PolluteToConstructors(decl: Decl): Unit {
        var primaryCtor: Option<PrimaryCtorDecl> = None
        var hasCtor = false
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.rawMangleName.isEmpty()) {
                continue
            }
            if (IsClassOrEnumConstructor(member)) {
                hasCtor = true
                PolluteAPIOfDecl(member)
            }
            if (member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                hasCtor = true
                primaryCtor = member as PrimaryCtorDecl
                PolluteAPIOfDecl(member)
            }
        }
        if (!hasCtor) {
            PollutePreciseUsages(decl.rawMangleName + "<init>")
        }
        if (let Some(pc) <- primaryCtor) {
            for (paramList in pc.funcBody.getOrThrow().paramLists) {
                for (param in paramList.params) {
                    if (param.isMemberParam) {
                        PolluteAPIOfDecl(param)
                    }
                }
            }
        }
    }

    public func PollutionForLayoutChangedDecl(decl: InheritableDecl): Unit {
        if (!typeChanges.contains(decl)) { typeChanges[decl] = PollutedTypeChangeRecord() }
        let record = typeChanges[decl]
        if (record.instVar) {
            return
        }
        record.instVar = true
        if (decl.astKind == ASTKind.ENUM_DECL) {
            for (constructor in (decl as EnumDecl).getOrThrow().constructors) {
                PolluteAPIOfDecl(constructor)
            }
            PolluteAPIOfDecl(decl)
        } else if (decl.astKind == ASTKind.STRUCT_DECL) {
            PolluteAPIOfDecl(decl)
            for (member in decl.GetMemberDeclPtrs()) {
                if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC)) {
                    PolluteAPIOfDecl(member)
                }
            }
            PolluteToConstructors(decl)
        } else if (decl.astKind == ASTKind.CLASS_DECL) {
            for (member in decl.GetMemberDeclPtrs()) {
                if (member.astKind == ASTKind.VAR_DECL && !member.TestAttr(Attribute.STATIC)) {
                    PolluteAPIOfDecl(member)
                }
            }
            PolluteToConstructors(decl)
        } else if (decl.astKind == ASTKind.EXTEND_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            CJC_ABORT()
        }
    }

    public func PollutionForVTableChangedDecl(decl: InheritableDecl): Unit {
        if (!typeChanges.contains(decl)) { typeChanges[decl] = PollutedTypeChangeRecord() }
        let record = typeChanges[decl]
        if (record.virt) {
            return
        }
        record.virt = true
        PolluteDownStreamTypes(decl)
        PolluteBoxUsesFromDecl(decl)
        for (member in GetMembers(decl)) {
            if (IsVirtual(member)) {
                PolluteAPIOfDecl(member)
            }
        }
    }

    public func PolluteBodyOfDecl(decl: Decl): Unit {
        if (visitedBodyPollutedDecls.contains(decl)) {
            return
        }
        visitedBodyPollutedDecls.add(decl)
        AddToPollutedDecls(decl)
        if (IsUntyped(decl)) {
            PolluteAPIOfDecl(decl)
        }
        PollutedInstantiationChangeFromDecl(decl)
        PolluteCHIROptAffectDecl(decl)
    }

    public func FindAllExtendDeclsOfType(name: String): HashSet<Decl> {
        let out = HashSet<Decl>()
        for (mangle in t.GetAllExtendsOfType(name)) {
            if (let Some(decl) <- mangled2Decl.get(mangle)) {
                out.add(decl)
            }
        }
        return out
    }

    private static func LookupSpecialBuiltinType(typeNode: RefType): Option<String> {
        let builtinNonPrimitiveTypes: Array<(String, Int64)> =
            [(CPOINTER_NAME, 1), (CSTRING_NAME, 0), (CFUNC_NAME, 1)]
        for (entry in builtinNonPrimitiveTypes) {
            if (entry[0] == typeNode.ref.identifier.Val() && entry[1] == typeNode.typeArguments.size) {
                return Some(entry[0])
            }
        }
        return None
    }

    public func GetExtendedTypeRawMangleNameImpl(extendedType: Type): Option<String> {
        let ty = extendedType.GetTy()
        if (Ty.IsTyCorrect(ty)) {
            return Some(GetTypeRawMangleName(ty.getOrThrow()))
        }
        var typeId: Option<String> = None
        if (extendedType.astKind == ASTKind.PRIMITIVE_TYPE) {
            return Some(ASTMangler.ManglePrimitiveType((extendedType as PrimitiveType).getOrThrow()))
        } else if (extendedType.astKind == ASTKind.REF_TYPE) {
            let refType = (extendedType as RefType).getOrThrow()
            if (let Some(specialName) <- LookupSpecialBuiltinType(refType)) {
                return Some(specialName)
            }
            typeId = Some(refType.ref.identifier.Val())
        } else if (extendedType.astKind == ASTKind.QUALIFIED_TYPE) {
            typeId = Some((extendedType as QualifiedType).getOrThrow().field.Val())
        } else if (extendedType.astKind != ASTKind.OPTION_TYPE && extendedType.astKind != ASTKind.CONSTANT_TYPE &&
            extendedType.astKind != ASTKind.VARRAY_TYPE && extendedType.astKind != ASTKind.FUNC_TYPE &&
            extendedType.astKind != ASTKind.TUPLE_TYPE && extendedType.astKind != ASTKind.PAREN_TYPE &&
            extendedType.astKind != ASTKind.THIS_TYPE && extendedType.astKind != ASTKind.INVALID_TYPE) {
            CJC_ABORT()
        }
        if (let Some(identifier) <- typeId) {
            for ((mangle, candidate) in mangled2Decl) {
                if (candidate.identifier == identifier) {
                    if (candidate.IsNominalDecl()) {
                        return Some(mangle)
                    }
                    if (let Some(typeAlias) <- (candidate as TypeAliasDecl)) {
                        return GetExtendedTypeRawMangleNameImpl(typeAlias.typeNode.getOrThrow())
                    }
                }
            }
        }
        return None
    }

    public func GetExtendedTypeRawMangleName(extendDecl: ExtendDecl): Option<String> {
        return GetExtendedTypeRawMangleNameImpl(extendDecl.extendedType.getOrThrow())
    }

    public func PolluteAPIOfDecl(decl: Decl): Unit {
        if (visitedAPIPollutedDecls.contains(decl)) {
            return
        }
        visitedAPIPollutedDecls.add(decl)
        AddToPollutedDecls(decl)
        PolluteBoxUsesFromDecl(decl)
        PollutedInstantiationChangeFromDecl(decl)
        if (let Some(parent) <- decl.outerDecl) {
            if (parent.astKind == ASTKind.EXTEND_DECL) {
                AdditionPollutionAPIOfExtendDecl((parent as ExtendDecl).getOrThrow())
            }
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            for (getter in propDecl.getters) {
                PolluteAPIOfDecl(getter)
            }
            for (setter in propDecl.setters) {
                PolluteAPIOfDecl(setter)
            }
            return
        }
        if (decl.astKind == ASTKind.VAR_DECL && !decl.TestAttr(Attribute.STATIC)) {
            if (let Some(parent) <- decl.outerDecl) {
                if (let Some(parentDecl) <- (parent as InheritableDecl)) {
                    AddToPollutedDecls(parentDecl)
                    PollutionForLayoutChangedDecl(parentDecl)
                }
            }
        }
        if (decl.astKind == ASTKind.EXTEND_DECL) {
            AdditionPollutionAPIOfExtendDecl((decl as ExtendDecl).getOrThrow())
            return
        }
        if (decl.astKind == ASTKind.MAIN_DECL) {
            return
        }
        if (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.FUNC_PARAM ||
            decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL || decl.astKind == ASTKind.FUNC_DECL ||
            decl.astKind == ASTKind.PRIMARY_CTOR_DECL || decl.astKind == ASTKind.ENUM_DECL ||
            decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL) {
            PollutePreciseUsages(decl)
            PollutedUnqualifiedUses(decl)
            PollutedGlobalChangeToPackageQualifiedUses(decl)
            PolluteGlobalChangeToQualifiedUses(decl)
            for (extendDecl in FindAllExtendDeclsOfType(decl.rawMangleName)) {
                AddToPollutedDecls(extendDecl)
                PollutedInstantiationChangeFromDecl(extendDecl)
            }
            return
        }
        CJC_ABORT()
    }

    public func AdditionPollutionAPIOfDirectExtendDecls(mangle: String): Unit {
        if (let Some(values) <- directExtends.get(mangle)) {
            for (decl in values) {
                PolluteAPIOfDecl(decl)
            }
        }
    }

    public func GetPollutionResult(): HashSet<Decl> {
        return pollutedDecls
    }

    public func GetDeletedResult(): ArrayList<String> {
        return deletedDecls
    }

    public func GetReBoxedTypes(): ArrayList<String> {
        return reBoxedTypes
    }

    public func NeedPollutedInstantiationChange(decl: Decl): Bool {
        return IsInDeclWithAttribute(decl, Attribute.GENERIC)
    }

    public func PollutedInstantiationChangeFromDecl(decl: Decl): Unit {
        if (!otherChanges.contains(decl.rawMangleName)) {
            otherChanges[decl.rawMangleName] = PollutedOtherUseRecord()
        }
        let record = otherChanges[decl.rawMangleName]
        if (record.instantiation) {
            return
        }
        record.instantiation = true
        if (let Some(parent) <- decl.outerDecl) {
            PollutedInstantiationChangeFromDecl(parent)
        }
        if (NeedPollutedInstantiationChange(decl)) {
            AddToPollutedDecls(decl)
            for (member in GetAllMembers(decl)) {
                AddToPollutedDecls(member)
            }
            PollutePreciseUsages(decl)
        }
    }

    public func PolluteCHIROptAffectDecl(decl: Decl): Unit {
        if (let Some(varWithPatternDecl) <- (decl as VarWithPatternDecl)) {
            for (pattern in FlattenVarWithPatternDecl(varWithPatternDecl)) {
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    PolluteCHIROptAffectDecl(varPattern.varDecl.getOrThrow())
                }
            }
        }
        if (let Some(affected) <- chirOptMap.get(decl.rawMangleName)) {
            if (!otherChanges.contains(decl.rawMangleName)) {
                otherChanges[decl.rawMangleName] = PollutedOtherUseRecord()
            }
            let record = otherChanges[decl.rawMangleName]
            if (record.chirOpt) {
                return
            }
            record.chirOpt = true
            for (user in affected) {
                if (let Some(extendDecl) <- (user as ExtendDecl)) {
                    PolluteAPIOfDecl(extendDecl)
                    PolluteCHIROptAffectDecl(extendDecl)
                } else {
                    PolluteBodyOfDecl(user)
                }
            }
        }
    }

    public func PollutedToBoxUses(mangle: String): Unit {
        if (!otherChanges.contains(mangle)) { otherChanges[mangle] = PollutedOtherUseRecord() }
        let record = otherChanges[mangle]
        if (record.box) {
            return
        }
        record.box = true
        reBoxedTypes.add(mangle)
        if (let Some(uses) <- p.boxUses.get(mangle)) {
            for (decl in uses) {
                PollutionForBodyChangedDecl(decl)
            }
        }
        if (let Some(decl) <- mangled2Decl.get(mangle)) {
            if (let Some(children) <- t.children.get(decl)) {
                for (child in children) {
                    AddToPollutedDecls(child)
                    PollutedToBoxUses(child.rawMangleName)
                }
            }
        }
        for (extendDecl in FindAllExtendDeclsOfType(mangle)) {
            let extendValue = (extendDecl as ExtendDecl).getOrThrow()
            if (!extendValue.inheritedTypes.isEmpty()) {
                AddToPollutedDecls(extendValue)
                PolluteCHIROptAffectDecl(extendValue)
            }
        }
    }

    public func PollutedToExprUsages(usages: HashSet<Decl>): Unit {
        for (usageDecl in usages) {
            PolluteBodyOfDecl(usageDecl)
        }
    }

    public func PollutePreciseUsages(decl: Decl): Unit {
        if (!decl.rawMangleName.isEmpty()) {
            PollutePreciseUsages(decl.rawMangleName)
        }
    }

    public func PollutePreciseUsages(mangled: String): Unit {
        if (let Some(bodyUses) <- p.directUses.body.get(mangled)) {
            for (usage in bodyUses) {
                PolluteBodyOfDecl(usage)
            }
        }
        if (let Some(apiUses) <- p.directUses.api.get(mangled)) {
            for (usage in apiUses) {
                PolluteAPIOfDecl(usage)
            }
        }
    }

    public func PolluteDownStreamTypes(decl: Decl): Unit {
        CJC_ASSERT(decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.CLASS_DECL ||
            decl.astKind == ASTKind.INTERFACE_DECL || decl.astKind == ASTKind.ENUM_DECL ||
            decl.astKind == ASTKind.EXTEND_DECL)
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            let extendedType = extendDecl.extendedType.getOrThrow()
            var extendedTypeIdentifier = ""
            if (let Some(refType) <- (extendedType as RefType)) {
                extendedTypeIdentifier = refType.ref.identifier.Val()
            } else if (let Some(qualifiedType) <- (extendedType as QualifiedType)) {
                extendedTypeIdentifier = qualifiedType.field.Val()
            }
            var extendedTypeDecl: Option<Decl> = None
            for ((_, candidate) in mangled2Decl) {
                if (candidate.identifier == extendedTypeIdentifier) {
                    extendedTypeDecl = Some(candidate)
                    break
                }
            }
            if (let Some(candidate) <- extendedTypeDecl) { PolluteDownStreamTypes(candidate) }
            return
        }
        if (let Some(children) <- t.children.get(decl)) {
            for (child in children) {
                PolluteAPIOfDecl(child)
            }
        }
        if (let Some(interfaceExtenders) <- t.interfaceExtendTypes.get(decl.rawMangleName)) {
            for (name in interfaceExtenders) {
                if (let Some(child) <- mangled2Decl.get(name)) {
                    PolluteAPIOfDecl(child)
                } else {
                    for (extendName in t.GetAllExtendsOfType(name)) {
                        if (let Some(extendDecl) <- mangled2Decl.get(extendName)) {
                            AddToPollutedDecls(extendDecl)
                            PollutedInstantiationChangeFromDecl(extendDecl)
                        }
                    }
                }
            }
        }
    }

    public func PollutedUnqualifiedUses(decl: Decl): Unit {
        for (identifier in p.GetAccessibleDeclName(decl)) {
            let container = if (IsImported(decl)) { p.unqUsesOfImported.body } else { p.unqUses.body }
            if (let Some(scopeMap) <- container.get(identifier)) {
                for ((_, users) in scopeMap) {
                    for (user in users) {
                        PolluteBodyOfDecl(user)
                    }
                }
            }
        }
        if (!decl.IsNominalDecl()) {
            return
        }
        for (identifier in p.GetAccessibleDeclName(decl)) {
            let container = if (IsImported(decl)) { p.unqUsesOfImported.api } else { p.unqUses.api }
            if (let Some(scopeMap) <- container.get(identifier)) {
                for ((_, users) in scopeMap) {
                    for (user in users) {
                        PolluteAPIOfDecl(user)
                    }
                }
            }
        }
    }

    public func PolluteGlobalChangeToQualifiedUses(decl: Decl): Unit {
        if (let None <- decl.outerDecl) {
            return
        }
        for (user in p.GetQUses(Idx.BODY, decl.identifier.Val())) {
            PolluteBodyOfDecl(user)
        }
    }

    public func PollutedGlobalChangeToPackageQualifiedUses(decl: Decl): Unit {
        for (packageName in p.GetAccessiblePackageName(decl.fullPackageName)) {
            for (user in p.GetPackageQualifiedUses(Idx.BODY, decl.identifier.Val(), packageName)) {
                PolluteBodyOfDecl(user)
            }
        }
        if (!decl.IsNominalDecl()) {
            return
        }
        for (packageName in p.GetAccessiblePackageName(decl.fullPackageName)) {
            for (user in p.GetPackageQualifiedUses(Idx.API, decl.identifier.Val(), packageName)) {
                PolluteAPIOfDecl(user)
            }
        }
    }

    public func FallBack(): Bool {
        return !typeAliases.isEmpty() || !unfoundExtends.isEmpty() || !unfoundNames.isEmpty() ||
            !removedNotSupported.isEmpty()
    }

    public func PrintFallbackInfo(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < DELIMITER_NUM) {
            builder.append("=")
            idx++
        }
        builder.append("\nFallback info:\n")
        for (decl in typeAliases) {
            builder.append("changed typealias: " + PrintDecl(decl) + "\n")
        }
        var previousExtend: Option<Decl> = None
        for (decl in unfoundExtends) {
            if (let Some(previous) <- previousExtend) {
                if (previous == decl) { continue }
            }
            builder.append("unfound extend: " + PrintDecl(decl) + "\n")
            previousExtend = Some(decl)
        }
        var previousName: Option<String> = None
        for (name in unfoundNames) {
            if (let Some(previous) <- previousName) {
                if (previous == name) { continue }
            }
            builder.append("unfound name: " + name + "\n")
            previousName = Some(name)
        }
        for (name in removedNotSupported) {
            builder.append("removed type " + name + "\n")
        }
        idx = 0
        while (idx < DELIMITER_NUM) {
            builder.append("=")
            idx++
        }
        logger.LogLn(builder.toString())
    }

}
