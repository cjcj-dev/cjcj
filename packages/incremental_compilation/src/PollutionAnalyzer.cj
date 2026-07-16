package cjcj::incremental_compilation

import std.collection.*
import cjcj::utils.CJC_ABORT
import cjcj::utils.IncrementalCompilationLogger

public enum UseIndex {
    | BODY
    | API
}

public func UseIndexIndex(index: UseIndex): Int64 {
    return match (index) {
        case UseIndex.BODY => 0
        case UseIndex.API => 1
    }
}

extend UseIndex <: Equatable<UseIndex> {
    public operator func ==(right: UseIndex): Bool {
        return UseIndexIndex(this) == UseIndexIndex(right)
    }

    public operator func !=(right: UseIndex): Bool {
        return !(this == right)
    }
}

public class TypeMap {
    public let interfaceExtendTypes: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let children: HashMap<IncrDecl, HashSet<IncrDecl>> = HashMap<IncrDecl, HashSet<IncrDecl>>()
    private let extend2Decl: HashMap<String, String> = HashMap<String, String>()
    private let extends: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    public init() {}

    public func AddParent(parent: IncrDecl, child: IncrDecl): Unit {
        if (!children.contains(parent)) {
            children[parent] = HashSet<IncrDecl>()
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
            return CloneStringList(values)
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

    public func CollectImportedDeclExtraRelation(decl: IncrDecl): Unit {
        if (!decl.IsNominalDecl()) {
            return
        }
        for (parent in decl.inheritedTypes) {
            AddParent(parent, decl)
        }
        if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
            if (let Some(extendedType) <- decl.extendedTypeMangle) {
                AddExtend(extendedType, decl.rawMangleName)
            }
        }
    }

    public func Merge(other: TypeMap): Unit {
        for ((extendName, typeName) in other.extend2Decl) {
            extend2Decl[extendName] = typeName
        }
        for ((parent, childSet) in other.children) {
            if (!children.contains(parent)) {
                children[parent] = HashSet<IncrDecl>()
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
        for ((typeName, values) in other.interfaceExtendTypes) {
            if (!interfaceExtendTypes.contains(typeName)) {
                interfaceExtendTypes[typeName] = HashSet<String>()
            }
            for (value in values) {
                interfaceExtendTypes[typeName].add(value)
            }
        }
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
        return CombineHashI64(leftDecl.hashCode(), name.hashCode())
    }
}

public type UnqualifiedName2Usages = HashMap<String, HashMap<IncrDecl, HashSet<IncrDecl>>>
public type QualifiedName2Usages = HashMap<QualifiedUsage, HashSet<IncrDecl>>
public type PackageQualifiedUsages = HashMap<String, HashMap<String, HashSet<IncrDecl>>>

public func DeclAliasKey(fullPackageName: String, identifier: String): String {
    return fullPackageName + "::" + identifier
}

public class ChangePollutedMap {
    public let unqBody: UnqualifiedName2Usages = UnqualifiedName2Usages()
    public let unqApi: UnqualifiedName2Usages = UnqualifiedName2Usages()
    public let unqImportedBody: UnqualifiedName2Usages = UnqualifiedName2Usages()
    public let unqImportedApi: UnqualifiedName2Usages = UnqualifiedName2Usages()
    public let qBody: QualifiedName2Usages = QualifiedName2Usages()
    public let qApi: QualifiedName2Usages = QualifiedName2Usages()
    public let pqBody: PackageQualifiedUsages = PackageQualifiedUsages()
    public let pqApi: PackageQualifiedUsages = PackageQualifiedUsages()
    public let directBody: HashMap<String, HashSet<IncrDecl>> = HashMap<String, HashSet<IncrDecl>>()
    public let directApi: HashMap<String, HashSet<IncrDecl>> = HashMap<String, HashSet<IncrDecl>>()
    public let boxUses: HashMap<String, ArrayList<IncrDecl>> = HashMap<String, ArrayList<IncrDecl>>()
    public let packageAliasMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let declAliasMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()

    public init() {}

    public func GetUnqUses(getImportOnly: Bool, index: UseIndex, identifier: String,
        scope: IncrDecl): HashSet<IncrDecl> {
        let container = if (getImportOnly) {
            if (index == UseIndex.BODY) { unqImportedBody } else { unqImportedApi }
        } else {
            if (index == UseIndex.BODY) { unqBody } else { unqApi }
        }
        if (let Some(scopeMap) <- container.get(identifier)) {
            if (let Some(usages) <- scopeMap.get(scope)) {
                return usages
            }
        }
        return HashSet<IncrDecl>()
    }

    public func GetQUses(index: UseIndex, identifier: String): HashSet<IncrDecl> {
        let container = if (index == UseIndex.BODY) { qBody } else { qApi }
        let usages = HashSet<IncrDecl>()
        for ((usage, decls) in container) {
            if (usage.name == identifier) {
                for (decl in decls) {
                    usages.add(decl)
                }
            }
        }
        return usages
    }

    public func GetPackageQualifiedUses(index: UseIndex, identifier: String,
        packageName: String): HashSet<IncrDecl> {
        let container = if (index == UseIndex.BODY) { pqBody } else { pqApi }
        if (let Some(pkgMap) <- container.get(identifier)) {
            if (let Some(values) <- pkgMap.get(packageName)) {
                return values
            }
        }
        return HashSet<IncrDecl>()
    }

    public func GetAccessibleDeclName(decl: IncrDecl): HashSet<String> {
        let key = DeclAliasKey(decl.fullPackageName, decl.identifier)
        if (let Some(values) <- declAliasMap.get(key)) {
            return values
        }
        let out = HashSet<String>()
        out.add(decl.identifier)
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

    public func DirectUses(index: UseIndex): HashMap<String, HashSet<IncrDecl>> {
        return if (index == UseIndex.BODY) { directBody } else { directApi }
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
    public let declsToRecompile: HashSet<IncrDecl> = HashSet<IncrDecl>()
    public let deleted: ArrayList<String> = ArrayList<String>()
    public let reBoxedTypes: ArrayList<String> = ArrayList<String>()

    public init() {}

    public init(kind: IncreKind) {
        this.kind = kind
    }
}

public class PollutionAnalyseArgs {
    public var rawModified: ModifiedDecls
    public var pkg: IncrDecl
    public var sourcePopulations: SrcImportedDepMap
    public var semaInfo: SemanticInfo
    public var chirOptInfo: OptEffectStrMap
    public var fileMap: CachedFileMap
    public var man: IncrImportManager
    public var mangled2Decl: RawMangled2DeclMap
    public var extends: HashMap<String, ArrayList<DirectExtendEntry>>
    public var importedRelations: TypeMap

    public init(rawModified: ModifiedDecls, pkg: IncrDecl, sourcePopulations: SrcImportedDepMap,
        semaInfo: SemanticInfo, chirOptInfo: OptEffectStrMap, fileMap: CachedFileMap,
        man: IncrImportManager, mangled2Decl: RawMangled2DeclMap,
        extends: HashMap<String, ArrayList<DirectExtendEntry>>, importedRelations: TypeMap) {
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

private func TruncateDeletedExtendMangledName(name: String): Option<String> {
    if (name.contains("7Extend!")) {
        return None
    }
    if (let Some(pos) <- name.indexOf("<:")) {
        return Some(name[0..pos])
    }
    return None
}

private func IsDigitByte(byte: UInt8): Bool {
    return byte >= b'0' && byte <= b'9'
}

private func LastPackageSeparatorBefore(bytes: Array<UInt8>, end: Int64): Int64 {
    if (end <= 0) {
        return 0
    }
    var idx = end - 1
    while (idx >= 0) {
        if (bytes[idx] == b'.') {
            return idx + 1
        }
        if (idx == 0) {
            break
        }
        idx--
    }
    return 0
}

private func GenericBoundary(bytes: Array<UInt8>): Int64 {
    var idx: Int64 = 0
    while (idx < bytes.size) {
        if (bytes[idx] == b'<') {
            return idx
        }
        idx++
    }
    return bytes.size
}

private func BytesToString(bytes: Array<UInt8>, begin: Int64, end: Int64): String {
    let builder = StringBuilder()
    var idx = begin
    while (idx < end) {
        builder.append(String.fromUtf8([bytes[idx]]))
        idx++
    }
    return builder.toString()
}

private func GetIdentifierFromTruncatedName(mangle: String): String {
    let bytes = mangle.toArray()
    let end = GenericBoundary(bytes)
    var begin = LastPackageSeparatorBefore(bytes, end)
    while (begin < end && IsDigitByte(bytes[begin])) {
        begin++
    }
    return BytesToString(bytes, begin, end)
}

public class PollutionAnalyzer {
    private var p: ChangePollutedMap
    private var t: TypeMap
    private var mangled2Decl: RawMangled2DeclMap
    private let directExtends: HashMap<String, ArrayList<IncrDecl>> = HashMap<String, ArrayList<IncrDecl>>()
    private let typeAliases: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    private let unfoundExtends: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    private let unfoundNames: ArrayList<String> = ArrayList<String>()
    private let chirOptMap: HashMap<String, ArrayList<IncrDecl>> = HashMap<String, ArrayList<IncrDecl>>()
    private let changes: HashMap<IncrDecl, PollutedCommonChangeRecord> =
        HashMap<IncrDecl, PollutedCommonChangeRecord>()
    private let typeChanges: HashMap<IncrDecl, PollutedTypeChangeRecord> =
        HashMap<IncrDecl, PollutedTypeChangeRecord>()
    private let removedNotSupported: ArrayList<String> = ArrayList<String>()
    private let otherChanges: HashMap<String, PollutedOtherUseRecord> = HashMap<String, PollutedOtherUseRecord>()
    private let pollutedDecls: HashSet<IncrDecl> = HashSet<IncrDecl>()
    private let deletedDecls: ArrayList<String> = ArrayList<String>()
    private let reBoxedTypes: ArrayList<String> = ArrayList<String>()
    private let visitedBodyPollutedDecls: HashSet<IncrDecl> = HashSet<IncrDecl>()
    private let visitedAPIPollutedDecls: HashSet<IncrDecl> = HashSet<IncrDecl>()

    public init(p: ChangePollutedMap, t: TypeMap, mangled2Decl: RawMangled2DeclMap,
        chirOpt: OptEffectStrMap, extends: HashMap<String, ArrayList<DirectExtendEntry>>) {
        this.p = p
        this.t = t
        this.mangled2Decl = mangled2Decl
        for ((src, affectedNames) in chirOpt) {
            let affected = ArrayList<IncrDecl>()
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
            let values = ArrayList<IncrDecl>()
            for (entry in entries) {
                values.add(entry.decl)
            }
            directExtends[mangle] = values
        }
    }

    public static func Get(args: PollutionAnalyseArgs): PollutionResult {
        if (!args.rawModified.aliases.isEmpty()) {
            let logger = IncrementalCompilationLogger.GetInstance()
            if (logger.IsEnable()) {
                for (decl in args.rawModified.aliases) {
                    logger.LogLn("changed typealias: " + PrintDecl(decl))
                }
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
            analyzer.PollutionForChangedTypeDecl(decl, change)
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

    public func AddToPollutedDecls(decl: IncrDecl): Unit {
        pollutedDecls.add(decl)
        if (decl.astKind == IncrDeclKind.FUNC_DECL && decl.IsImported()) {
            for (desugarDecl in decl.defaultParamDesugarDecls) {
                if (desugarDecl.rawMangleName.isEmpty() && !desugarDecl.mangledName.isEmpty()) {
                    desugarDecl.rawMangleName = desugarDecl.mangledName
                }
                AddToPollutedDecls(desugarDecl)
            }
        } else if (decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
            for (member in GetMembers(decl)) {
                if (member.astKind == IncrDeclKind.VAR_DECL) {
                    pollutedDecls.add(member)
                }
            }
        }
    }

    public func PollutionForAddedDecl(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.TYPE_ALIAS_DECL) {
            typeAliases.add(decl)
            return
        }
        if (decl.IsNominalDecl()) {
            PollutionForAddedTypeDecl(decl)
        } else {
            PollutionForAddedNonTypeDecl(decl)
        }
    }

    public func PollutionForAddedTypeDecl(decl: IncrDecl): Unit {
        if (!decl.IsImported() || IsInDeclWithAttribute(decl, IncrAttribute.GENERIC)) {
            AddToPollutedDecls(decl)
        }
        for (member in GetAllMembers(decl)) {
            PollutionForAddedNonTypeDecl(member)
        }
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
        if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
            AdditionPollutionForAddedExtendDecl(decl)
        }
    }

    public func PollutionForAddedNonTypeDecl(decl: IncrDecl): Unit {
        if (decl.IsImported()) {
            var srcImported = false
            if (decl.astKind == IncrDeclKind.VAR_DECL) {
                if (decl.TestAttr(IncrAttribute.GLOBAL) && decl.hasInitializer) {
                    srcImported = true
                }
            } else if (decl.astKind == IncrDeclKind.FUNC_DECL) {
                if (decl.hasBody) {
                    srcImported = true
                }
            }
            let genericImported = IsInDeclWithAttribute(decl, IncrAttribute.GENERIC)
            if (srcImported || genericImported) {
                AddToPollutedDecls(decl)
            }
        } else {
            AddToPollutedDecls(decl)
        }
        PollutionForAddedNonTypeDeclImpl(decl)
    }

    public func PollutionForAddedNonTypeDeclImpl(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.PROP_DECL) {
            for (getter in decl.getters) {
                AddToPollutedDecls(getter)
                PollutionForAddedNonTypeDeclImpl(getter)
            }
            for (setter in decl.setters) {
                AddToPollutedDecls(setter)
                PollutionForAddedNonTypeDeclImpl(setter)
            }
        }
        if (decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
            for (variable in GetMembers(decl)) {
                if (variable.astKind != IncrDeclKind.VAR_DECL) {
                    continue
                }
                AddToPollutedDecls(variable)
                PollutionForAddedNonTypeDeclImpl(variable)
            }
        }
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
    }

    public func AdditionPollutionForBodyChangedExtendDecl(decl: IncrDecl): Unit {
        if (let Some(extendsWithSameName) <- directExtends.get(decl.rawMangleName)) {
            for (extendDecl in extendsWithSameName) {
                if (!pollutedDecls.contains(extendDecl)) {
                    AddToPollutedDecls(extendDecl)
                    PollutionForAddedTypeDecl(extendDecl)
                }
            }
        }
    }

    public func AdditionPollutionAPIOfExtendedDecl(decl: IncrDecl): Unit {
        if (let Some(extendedTypeName) <- GetExtendedTypeRawMangleName(decl)) {
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
        }
    }

    public func AdditionPollutionAPIOfExtendDecl(decl: IncrDecl): Unit {
        AdditionPollutionAPIOfExtendedDecl(decl)
        AdditionPollutionAPIOfDirectExtendDecls(decl.rawMangleName)
    }

    public func AdditionPollutionForAddedExtendDecl(decl: IncrDecl): Unit {
        if (decl.IsDirectExtend() && GetMembers(decl).isEmpty()) {
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
        } else if (let Some(truncatedExtendName) <- TruncateDeletedExtendMangledName(mangle)) {
            let identifier = GetIdentifierFromTruncatedName(truncatedExtendName)
            var foundCandidate = false
            for ((_, decl) in mangled2Decl) {
                if (decl.identifier == identifier && decl.IsNominalDecl() &&
                    decl.astKind != IncrDeclKind.EXTEND_DECL) {
                    foundCandidate = true
                    AddToPollutedDecls(decl)
                    PolluteBoxUsesFromDecl(decl)
                    PollutedInstantiationChangeFromDecl(decl)
                }
            }
            if (!foundCandidate) {
                PollutedToBoxUses(identifier)
            }
        }
        for (extendDecl in FindAllExtendDeclsOfType(mangle)) {
            AddToPollutedDecls(extendDecl)
            PollutedInstantiationChangeFromDecl(extendDecl)
        }
    }

    public func PollutionForConstDecl(decl: IncrDecl): Unit {
        AddToPollutedDecls(decl)
        if (decl.TestAttr(IncrAttribute.GENERIC)) {
            PollutedInstantiationChangeFromDecl(decl)
        }
    }

    public func PollutionForOrderChangeDecl(decl: IncrDecl): Unit {
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
            if (IsInDeclWithAttribute(parent, IncrAttribute.GENERIC)) {
                PollutedInstantiationChangeFromDecl(parent)
            }
        }
    }

    public func PollutionForBodyChangedDecl(decl: IncrDecl): Unit {
        if (decl.IsNominalDecl()) {
            let record = GetTypeRecord(decl)
            if (record.body) {
                return
            }
            record.body = true
            if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
                if (let Some(extendedTypeRawMangleName) <- GetExtendedTypeRawMangleName(decl)) {
                    if (let Some(extendedTypeDecl) <- mangled2Decl.get(extendedTypeRawMangleName)) {
                        if (extendedTypeDecl.IsNominalDecl() && extendedTypeDecl.astKind != IncrDeclKind.EXTEND_DECL) {
                            PollutionForBodyChangedDecl(extendedTypeDecl)
                        }
                    } else {
                        for (extendName in t.GetAllExtendsOfType(extendedTypeRawMangleName)) {
                            if (let Some(extendOfBuiltinDecl) <- mangled2Decl.get(extendName)) {
                                AddToPollutedDecls(extendOfBuiltinDecl)
                            }
                        }
                    }
                }
                AdditionPollutionForBodyChangedExtendDecl(decl)
            }
            if (decl.astKind == IncrDeclKind.CLASS_DECL) {
                PolluteDownStreamTypes(decl)
            }
            PolluteBoxUsesFromDecl(decl)
            AddToPollutedDecls(decl)
            PollutedInstantiationChangeFromDecl(decl)
        } else {
            let record = GetCommonRecord(decl)
            if (record.body) {
                return
            }
            record.body = true
            AddToPollutedDecls(decl)
            if (decl.astKind == IncrDeclKind.PROP_DECL) {
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
                if (!decl.TestAttr(IncrAttribute.STATIC) && parent.IsNominalDecl()) {
                    PolluteToConstructors(parent)
                }
            }
        }
    }

    public func PollutionForSigChangedDecl(decl: IncrDecl): Unit {
        match (decl.astKind) {
            case IncrDeclKind.FUNC_DECL | IncrDeclKind.PRIMARY_CTOR_DECL =>
                PollutionForSigChangedFuncDecl(decl)
            case IncrDeclKind.MAIN_DECL | IncrDeclKind.MACRO_DECL =>
                throw IllegalStateException("unexpected signature change for " + IncrDeclKindName(decl.astKind) +
                    ": " + decl.rawMangleName)
            case IncrDeclKind.VAR_DECL | IncrDeclKind.FUNC_PARAM =>
                PollutionForSigChangedVarDecl(decl)
            case IncrDeclKind.VAR_WITH_PATTERN_DECL =>
                PollutionForSigChangedVarWithPatternDecl(decl)
            case IncrDeclKind.PROP_DECL =>
                PollutionForSigChangedPropDecl(decl)
            case _ =>
                PollutionForSigChangedInheritableDecl(decl)
        }
    }

    public func PollutionForSigChangedFuncDecl(decl: IncrDecl): Unit {
        let record = GetCommonRecord(decl)
        if (record.sig) {
            return
        }
        record.sig = true
        PollutedUnqualifiedUses(decl)
        PollutedGlobalChangeToPackageQualifiedUses(decl)
        PolluteGlobalChangeToQualifiedUses(decl)
        PollutedInstantiationChangeFromDecl(decl)
        if (let Some(parent) <- decl.outerDecl) {
            if (parent.astKind == IncrDeclKind.EXTEND_DECL) {
                AdditionPollutionAPIOfExtendDecl(parent)
            }
        }
    }

    public func PollutionForSigChangedVarDecl(decl: IncrDecl): Unit {
        let record = GetCommonRecord(decl)
        if (record.sig) {
            return
        }
        record.sig = true
        if (!decl.HasOuterDecl()) {
            PollutedUnqualifiedUses(decl)
            PollutedToExprUsages(p.GetPackageQualifiedUses(UseIndex.BODY, decl.identifier, decl.fullPackageName))
        } else {
            PollutePreciseUsages(decl)
        }
    }

    public func PollutionForSigChangedVarWithPatternDecl(decl: IncrDecl): Unit {
        let record = GetCommonRecord(decl)
        if (record.sig) {
            return
        }
        record.sig = true
        for (member in decl.members) {
            if (member.astKind == IncrDeclKind.VAR_DECL) {
                PollutionForSigChangedDecl(member)
            }
        }
    }

    public func PollutionForSigChangedPropDecl(decl: IncrDecl): Unit {
        let record = GetCommonRecord(decl)
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

    public func PollutionForSigChangedInheritableDecl(decl: IncrDecl): Unit {
        let record = GetTypeRecord(decl)
        if (record.sig) {
            return
        }
        record.sig = true
        PollutePreciseUsages(decl)
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) {
                continue
            }
            if (member.astKind == IncrDeclKind.FUNC_DECL || member.astKind == IncrDeclKind.PROP_DECL ||
                member.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
                PolluteAPIOfDecl(member)
            }
        }
        for (extendDecl in FindAllExtendDeclsOfType(decl.rawMangleName)) {
            PolluteAPIOfDecl(extendDecl)
        }
        PolluteBoxUsesFromDecl(decl)
    }

    public func PollutionForSrcUseChangedDecl(decl: IncrDecl): Unit {
        if (IsEnumConstructor(decl)) {
            return
        }
        if (decl.IsNominalDecl()) {
            let typeRecord = GetTypeRecord(decl)
            if (typeRecord.srcUse) {
                return
            }
            typeRecord.srcUse = true
        } else {
            let record = GetCommonRecord(decl)
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

    public func PollutionForChangedTypeDecl(decl: IncrDecl, change: TypeChange): Unit {
        if (decl.IsImported() && decl.TestAttr(IncrAttribute.PRIVATE)) {
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

    public func PolluteBoxUsesFromDecl(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
            if (let Some(extendedType) <- GetExtendedTypeRawMangleName(decl)) {
                PollutedToBoxUses(extendedType)
            }
        } else if (decl.IsNominalDecl()) {
            PollutedToBoxUses(decl.rawMangleName)
        }
    }

    public func PolluteToConstructors(decl: IncrDecl): Unit {
        var hasCtor = false
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) {
                continue
            }
            if (IsClassOrEnumConstructor(member) || member.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
                hasCtor = true
                PolluteAPIOfDecl(member)
            }
        }
        if (!hasCtor) {
            PollutePreciseUsages(decl.rawMangleName + "<init>")
        }
        for (member in GetMembers(decl)) {
            if (member.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
                for (param in member.members) {
                    if (param.isMemberParam) {
                        PolluteAPIOfDecl(param)
                    }
                }
            }
        }
    }

    public func PollutionForLayoutChangedDecl(decl: IncrDecl): Unit {
        let record = GetTypeRecord(decl)
        if (record.instVar) {
            return
        }
        record.instVar = true
        if (decl.astKind == IncrDeclKind.ENUM_DECL) {
            for (constructor in GetEnumConstructors(decl)) {
                PolluteAPIOfDecl(constructor)
            }
            PolluteAPIOfDecl(decl)
        } else if (decl.astKind == IncrDeclKind.STRUCT_DECL || decl.astKind == IncrDeclKind.CLASS_DECL) {
            PolluteAPIOfDecl(decl)
            for (member in GetMembers(decl)) {
                if (member.astKind == IncrDeclKind.VAR_DECL && !member.TestAttr(IncrAttribute.STATIC)) {
                    PolluteAPIOfDecl(member)
                }
            }
            PolluteToConstructors(decl)
        }
    }

    public func PollutionForVTableChangedDecl(decl: IncrDecl): Unit {
        let record = GetTypeRecord(decl)
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

    public func PolluteBodyOfDecl(decl: IncrDecl): Unit {
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

    public func FindAllExtendDeclsOfType(name: String): HashSet<IncrDecl> {
        let out = HashSet<IncrDecl>()
        for (mangle in t.GetAllExtendsOfType(name)) {
            if (let Some(decl) <- mangled2Decl.get(mangle)) {
                out.add(decl)
            }
        }
        return out
    }

    public func GetExtendedTypeRawMangleName(decl: IncrDecl): Option<String> {
        if (let Some(value) <- decl.extendedTypeMangle) {
            return Some(value)
        }
        if (!decl.extendedTypeIdentifier.isEmpty()) {
            for ((mangle, candidate) in mangled2Decl) {
                if (candidate.identifier == decl.extendedTypeIdentifier && candidate.IsNominalDecl() &&
                    candidate.astKind != IncrDeclKind.EXTEND_DECL) {
                    return Some(mangle)
                }
            }
            return Some(decl.extendedTypeIdentifier)
        }
        return None
    }

    public func PolluteAPIOfDecl(decl: IncrDecl): Unit {
        if (visitedAPIPollutedDecls.contains(decl)) {
            return
        }
        visitedAPIPollutedDecls.add(decl)
        AddToPollutedDecls(decl)
        PolluteBoxUsesFromDecl(decl)
        PollutedInstantiationChangeFromDecl(decl)
        if (let Some(parent) <- decl.outerDecl) {
            if (parent.astKind == IncrDeclKind.EXTEND_DECL) {
                AdditionPollutionAPIOfExtendDecl(parent)
            }
        }
        if (decl.astKind == IncrDeclKind.PROP_DECL) {
            for (getter in decl.getters) {
                PolluteAPIOfDecl(getter)
            }
            for (setter in decl.setters) {
                PolluteAPIOfDecl(setter)
            }
            return
        }
        if (decl.astKind == IncrDeclKind.VAR_DECL && !decl.TestAttr(IncrAttribute.STATIC)) {
            if (let Some(parent) <- decl.outerDecl) {
                if (parent.IsNominalDecl()) {
                    AddToPollutedDecls(parent)
                    PollutionForLayoutChangedDecl(parent)
                }
            }
        }
        if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
            AdditionPollutionAPIOfExtendDecl(decl)
            return
        }
        if (decl.astKind == IncrDeclKind.MAIN_DECL) {
            return
        }
        if (IsAPIPropagationKind(decl.astKind)) {
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
        throw IllegalStateException("unexpected API pollution kind " + IncrDeclKindName(decl.astKind) +
            ": " + decl.rawMangleName)
    }

    private func IsAPIPropagationKind(kind: IncrDeclKind): Bool {
        return kind == IncrDeclKind.VAR_DECL || kind == IncrDeclKind.FUNC_PARAM ||
            kind == IncrDeclKind.VAR_WITH_PATTERN_DECL || kind == IncrDeclKind.FUNC_DECL ||
            kind == IncrDeclKind.PRIMARY_CTOR_DECL || kind == IncrDeclKind.ENUM_DECL ||
            kind == IncrDeclKind.STRUCT_DECL || kind == IncrDeclKind.CLASS_DECL ||
            kind == IncrDeclKind.INTERFACE_DECL
    }

    public func AdditionPollutionAPIOfDirectExtendDecls(mangle: String): Unit {
        if (let Some(values) <- directExtends.get(mangle)) {
            for (decl in values) {
                PolluteAPIOfDecl(decl)
            }
        }
    }

    public func GetPollutionResult(): HashSet<IncrDecl> {
        return pollutedDecls
    }

    public func GetDeletedResult(): ArrayList<String> {
        return deletedDecls
    }

    public func GetReBoxedTypes(): ArrayList<String> {
        return reBoxedTypes
    }

    public func NeedPollutedInstantiationChange(decl: IncrDecl): Bool {
        return IsInDeclWithAttribute(decl, IncrAttribute.GENERIC)
    }

    public func PollutedInstantiationChangeFromDecl(decl: IncrDecl): Unit {
        let record = GetOtherRecord(decl.rawMangleName)
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

    public func PolluteCHIROptAffectDecl(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
            for (member in GetMembers(decl)) {
                PolluteCHIROptAffectDecl(member)
            }
        }
        if (let Some(affected) <- chirOptMap.get(decl.rawMangleName)) {
            let record = GetOtherRecord(decl.rawMangleName)
            if (record.chirOpt) {
                return
            }
            record.chirOpt = true
            for (user in affected) {
                if (user.astKind == IncrDeclKind.EXTEND_DECL) {
                    PolluteAPIOfDecl(user)
                    PolluteCHIROptAffectDecl(user)
                } else {
                    PolluteBodyOfDecl(user)
                }
            }
        }
    }

    public func PollutedToBoxUses(mangle: String): Unit {
        let record = GetOtherRecord(mangle)
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
            if (!extendDecl.IsDirectExtend()) {
                AddToPollutedDecls(extendDecl)
                PolluteCHIROptAffectDecl(extendDecl)
            }
        }
    }

    public func PollutedToExprUsages(usages: HashSet<IncrDecl>): Unit {
        for (usageDecl in usages) {
            PolluteBodyOfDecl(usageDecl)
        }
    }

    public func PollutePreciseUsages(decl: IncrDecl): Unit {
        if (!decl.rawMangleName.isEmpty()) {
            PollutePreciseUsages(decl.rawMangleName)
        }
    }

    public func PollutePreciseUsages(mangled: String): Unit {
        if (let Some(bodyUses) <- p.directBody.get(mangled)) {
            for (usage in bodyUses) {
                PolluteBodyOfDecl(usage)
            }
        }
        if (let Some(apiUses) <- p.directApi.get(mangled)) {
            for (usage in apiUses) {
                PolluteAPIOfDecl(usage)
            }
        }
    }

    public func PolluteDownStreamTypes(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.EXTEND_DECL) {
            if (let Some(extendedType) <- GetExtendedTypeRawMangleName(decl)) {
                if (let Some(extendedDecl) <- mangled2Decl.get(extendedType)) {
                    PolluteDownStreamTypes(extendedDecl)
                }
            }
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

    public func PollutedUnqualifiedUses(decl: IncrDecl): Unit {
        for (identifier in p.GetAccessibleDeclName(decl)) {
            let container = if (decl.IsImported()) { p.unqImportedBody } else { p.unqBody }
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
            let container = if (decl.IsImported()) { p.unqImportedApi } else { p.unqApi }
            if (let Some(scopeMap) <- container.get(identifier)) {
                for ((_, users) in scopeMap) {
                    for (user in users) {
                        PolluteAPIOfDecl(user)
                    }
                }
            }
        }
    }

    public func PolluteGlobalChangeToQualifiedUses(decl: IncrDecl): Unit {
        if (!decl.HasOuterDecl()) {
            return
        }
        for (user in p.GetQUses(UseIndex.BODY, decl.identifier)) {
            PolluteBodyOfDecl(user)
        }
    }

    public func PollutedGlobalChangeToPackageQualifiedUses(decl: IncrDecl): Unit {
        for (packageName in p.GetAccessiblePackageName(decl.fullPackageName)) {
            for (user in p.GetPackageQualifiedUses(UseIndex.BODY, decl.identifier, packageName)) {
                PolluteBodyOfDecl(user)
            }
        }
        if (!decl.IsNominalDecl()) {
            return
        }
        for (packageName in p.GetAccessiblePackageName(decl.fullPackageName)) {
            for (user in p.GetPackageQualifiedUses(UseIndex.API, decl.identifier, packageName)) {
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
        for (decl in unfoundExtends) {
            builder.append("unfound extend: " + PrintDecl(decl) + "\n")
        }
        for (name in unfoundNames) {
            builder.append("unfound name: " + name + "\n")
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

    private func GetCommonRecord(decl: IncrDecl): PollutedCommonChangeRecord {
        if (!changes.contains(decl)) {
            changes[decl] = PollutedCommonChangeRecord()
        }
        return changes[decl]
    }

    private func GetTypeRecord(decl: IncrDecl): PollutedTypeChangeRecord {
        if (!typeChanges.contains(decl)) {
            typeChanges[decl] = PollutedTypeChangeRecord()
        }
        return typeChanges[decl]
    }

    private func GetOtherRecord(mangle: String): PollutedOtherUseRecord {
        if (!otherChanges.contains(mangle)) {
            otherChanges[mangle] = PollutedOtherUseRecord()
        }
        return otherChanges[mangle]
    }
}
