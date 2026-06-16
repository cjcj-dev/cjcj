package cangjie_compiler::incremental_compilation

import std.collection.*

public type RawMangledName = String
public type RawMangled2DeclMap = HashMap<String, IncrDecl>
public type OptEffectStrMap = HashMap<String, HashSet<String>>
public type VirtualWrapperDepMap = HashMap<String, String>
public type VarInitDepMap = HashMap<String, String>
public type SrcImportedDepMap = HashMap<IncrDecl, HashSet<IncrDecl>>
public type FileMap = HashMap<String, ArrayList<IncrDecl>>
public type CachedFileMap = HashMap<String, ArrayList<String>>
public type ASTCache = HashMap<String, TopLevelDeclCache>

public let CACHED_AST_EXTENSION: String = ".cachedast"
public let SERIALIZED_FILE_EXTENSION: String = ".cjo"

public enum IncrDeclKind {
    | INVALID_DECL
    | PACKAGE_DECL
    | FUNC_DECL
    | MACRO_DECL
    | MAIN_DECL
    | VAR_DECL
    | VAR_WITH_PATTERN_DECL
    | FUNC_PARAM
    | PROP_DECL
    | TYPE_ALIAS_DECL
    | ENUM_DECL
    | STRUCT_DECL
    | CLASS_DECL
    | INTERFACE_DECL
    | EXTEND_DECL
    | PRIMARY_CTOR_DECL
}

public func IncrDeclKindIndex(kind: IncrDeclKind): Int64 {
    return match (kind) {
        case IncrDeclKind.INVALID_DECL => 0
        case IncrDeclKind.PACKAGE_DECL => 1
        case IncrDeclKind.FUNC_DECL => 2
        case IncrDeclKind.MACRO_DECL => 3
        case IncrDeclKind.MAIN_DECL => 4
        case IncrDeclKind.VAR_DECL => 5
        case IncrDeclKind.VAR_WITH_PATTERN_DECL => 6
        case IncrDeclKind.FUNC_PARAM => 7
        case IncrDeclKind.PROP_DECL => 8
        case IncrDeclKind.TYPE_ALIAS_DECL => 9
        case IncrDeclKind.ENUM_DECL => 10
        case IncrDeclKind.STRUCT_DECL => 11
        case IncrDeclKind.CLASS_DECL => 12
        case IncrDeclKind.INTERFACE_DECL => 13
        case IncrDeclKind.EXTEND_DECL => 14
        case IncrDeclKind.PRIMARY_CTOR_DECL => 15
    }
}

public func IncrDeclKindName(kind: IncrDeclKind): String {
    return match (kind) {
        case IncrDeclKind.INVALID_DECL => "INVALID_DECL"
        case IncrDeclKind.PACKAGE_DECL => "PACKAGE_DECL"
        case IncrDeclKind.FUNC_DECL => "FUNC_DECL"
        case IncrDeclKind.MACRO_DECL => "MACRO_DECL"
        case IncrDeclKind.MAIN_DECL => "MAIN_DECL"
        case IncrDeclKind.VAR_DECL => "VAR_DECL"
        case IncrDeclKind.VAR_WITH_PATTERN_DECL => "VAR_WITH_PATTERN_DECL"
        case IncrDeclKind.FUNC_PARAM => "FUNC_PARAM"
        case IncrDeclKind.PROP_DECL => "PROP_DECL"
        case IncrDeclKind.TYPE_ALIAS_DECL => "TYPE_ALIAS_DECL"
        case IncrDeclKind.ENUM_DECL => "ENUM_DECL"
        case IncrDeclKind.STRUCT_DECL => "STRUCT_DECL"
        case IncrDeclKind.CLASS_DECL => "CLASS_DECL"
        case IncrDeclKind.INTERFACE_DECL => "INTERFACE_DECL"
        case IncrDeclKind.EXTEND_DECL => "EXTEND_DECL"
        case IncrDeclKind.PRIMARY_CTOR_DECL => "PRIMARY_CTOR_DECL"
    }
}

public func IncrDeclKindFromIndex(value: Int64): IncrDeclKind {
    return match (value) {
        case 1 => IncrDeclKind.PACKAGE_DECL
        case 2 => IncrDeclKind.FUNC_DECL
        case 3 => IncrDeclKind.MACRO_DECL
        case 4 => IncrDeclKind.MAIN_DECL
        case 5 => IncrDeclKind.VAR_DECL
        case 6 => IncrDeclKind.VAR_WITH_PATTERN_DECL
        case 7 => IncrDeclKind.FUNC_PARAM
        case 8 => IncrDeclKind.PROP_DECL
        case 9 => IncrDeclKind.TYPE_ALIAS_DECL
        case 10 => IncrDeclKind.ENUM_DECL
        case 11 => IncrDeclKind.STRUCT_DECL
        case 12 => IncrDeclKind.CLASS_DECL
        case 13 => IncrDeclKind.INTERFACE_DECL
        case 14 => IncrDeclKind.EXTEND_DECL
        case 15 => IncrDeclKind.PRIMARY_CTOR_DECL
        case _ => IncrDeclKind.INVALID_DECL
    }
}

extend IncrDeclKind <: Equatable<IncrDeclKind> {
    public operator func ==(right: IncrDeclKind): Bool {
        return IncrDeclKindIndex(this) == IncrDeclKindIndex(right)
    }

    public operator func !=(right: IncrDeclKind): Bool {
        return !(this == right)
    }
}

extend IncrDeclKind <: Hashable {
    public func hashCode(): Int64 {
        return IncrDeclKindIndex(this)
    }
}

public enum IncrAttribute {
    | ABSTRACT
    | CONSTRUCTOR
    | CONST
    | ENUM_CONSTRUCTOR
    | FROM_COMMON_PART
    | GENERIC
    | GLOBAL
    | IMPORTED
    | MACRO_FUNC
    | OPEN
    | PRIVATE
    | PROTECTED
    | PUBLIC
    | STATIC
}

public func IncrAttributeIndex(attr: IncrAttribute): Int64 {
    return match (attr) {
        case IncrAttribute.ABSTRACT => 0
        case IncrAttribute.CONSTRUCTOR => 1
        case IncrAttribute.CONST => 2
        case IncrAttribute.ENUM_CONSTRUCTOR => 3
        case IncrAttribute.FROM_COMMON_PART => 4
        case IncrAttribute.GENERIC => 5
        case IncrAttribute.GLOBAL => 6
        case IncrAttribute.IMPORTED => 7
        case IncrAttribute.MACRO_FUNC => 8
        case IncrAttribute.OPEN => 9
        case IncrAttribute.PRIVATE => 10
        case IncrAttribute.PROTECTED => 11
        case IncrAttribute.PUBLIC => 12
        case IncrAttribute.STATIC => 13
    }
}

public func IncrAttributeName(attr: IncrAttribute): String {
    return match (attr) {
        case IncrAttribute.ABSTRACT => "ABSTRACT"
        case IncrAttribute.CONSTRUCTOR => "CONSTRUCTOR"
        case IncrAttribute.CONST => "CONST"
        case IncrAttribute.ENUM_CONSTRUCTOR => "ENUM_CONSTRUCTOR"
        case IncrAttribute.FROM_COMMON_PART => "FROM_COMMON_PART"
        case IncrAttribute.GENERIC => "GENERIC"
        case IncrAttribute.GLOBAL => "GLOBAL"
        case IncrAttribute.IMPORTED => "IMPORTED"
        case IncrAttribute.MACRO_FUNC => "MACRO_FUNC"
        case IncrAttribute.OPEN => "OPEN"
        case IncrAttribute.PRIVATE => "PRIVATE"
        case IncrAttribute.PROTECTED => "PROTECTED"
        case IncrAttribute.PUBLIC => "PUBLIC"
        case IncrAttribute.STATIC => "STATIC"
    }
}

public func IncrAttributeFromName(name: String): Option<IncrAttribute> {
    return match (name) {
        case "ABSTRACT" => Some(IncrAttribute.ABSTRACT)
        case "CONSTRUCTOR" => Some(IncrAttribute.CONSTRUCTOR)
        case "CONST" => Some(IncrAttribute.CONST)
        case "ENUM_CONSTRUCTOR" => Some(IncrAttribute.ENUM_CONSTRUCTOR)
        case "FROM_COMMON_PART" => Some(IncrAttribute.FROM_COMMON_PART)
        case "GENERIC" => Some(IncrAttribute.GENERIC)
        case "GLOBAL" => Some(IncrAttribute.GLOBAL)
        case "IMPORTED" => Some(IncrAttribute.IMPORTED)
        case "MACRO_FUNC" => Some(IncrAttribute.MACRO_FUNC)
        case "OPEN" => Some(IncrAttribute.OPEN)
        case "PRIVATE" => Some(IncrAttribute.PRIVATE)
        case "PROTECTED" => Some(IncrAttribute.PROTECTED)
        case "PUBLIC" => Some(IncrAttribute.PUBLIC)
        case "STATIC" => Some(IncrAttribute.STATIC)
        case _ => None
    }
}

extend IncrAttribute <: Equatable<IncrAttribute> {
    public operator func ==(right: IncrAttribute): Bool {
        return IncrAttributeIndex(this) == IncrAttributeIndex(right)
    }

    public operator func !=(right: IncrAttribute): Bool {
        return !(this == right)
    }
}

extend IncrAttribute <: Hashable {
    public func hashCode(): Int64 {
        return IncrAttributeIndex(this)
    }
}

public class IncrPosition {
    public var line: Int64 = 0
    public var column: Int64 = 0

    public init() {}

    public init(line: Int64, column: Int64) {
        this.line = line
        this.column = column
    }

    public func IsZero(): Bool {
        return line == 0 && column == 0
    }

    public func ToString(): String {
        return "${line},${column}"
    }
}

public class DeclHashInfo {
    public var sig: UInt64 = 0u64
    public var srcUse: UInt64 = 0u64
    public var bodyHash: UInt64 = 0u64
    public var instVar: UInt64 = 0u64
    public var virt: UInt64 = 0u64
    public var gvid: Int64 = 0

    public init() {}
}

public class IncrDecl <: Hashable & Equatable<IncrDecl> {
    public var identifier: String = ""
    public var rawMangleName: String = ""
    public var mangledName: String = ""
    public var fullPackageName: String = ""
    public var filePath: String = ""
    public var begin: IncrPosition = IncrPosition()
    public var astKind: IncrDeclKind = IncrDeclKind.INVALID_DECL
    public let attrs: HashSet<IncrAttribute> = HashSet<IncrAttribute>()
    public let members: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let getters: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let setters: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let constructorMangles: ArrayList<String> = ArrayList<String>()
    public let enumConstructorMangles: ArrayList<String> = ArrayList<String>()
    public var outerDecl: Option<IncrDecl> = None
    public var extendedTypeMangle: Option<String> = None
    public var extendedTypeIdentifier: String = ""
    public var hasExplicitType: Bool = true
    public var hasBody: Bool = false
    public var hasInitializer: Bool = false
    public var isMemberParam: Bool = false
    public var isFinalizer: Bool = false
    public var isConstValue: Bool = false
    public var hasEllipsis: Bool = false
    public var toBeCompiled: Bool = false
    public var cgMangle: String = ""
    public var cacheHash: DeclHashInfo = DeclHashInfo()

    public init() {}

    public init(identifier: String, rawMangleName: String, kind: IncrDeclKind) {
        this.identifier = identifier
        this.rawMangleName = rawMangleName
        this.mangledName = rawMangleName
        this.astKind = kind
    }

    public operator func ==(right: IncrDecl): Bool {
        if (!rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return rawMangleName == right.rawMangleName
        }
        return identifier == right.identifier && filePath == right.filePath &&
            begin.line == right.begin.line && begin.column == right.begin.column &&
            astKind == right.astKind
    }

    public operator func !=(right: IncrDecl): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        var out = rawMangleName.hashCode()
        if (rawMangleName.isEmpty()) {
            out = CombineHashI64(out, identifier.hashCode())
            out = CombineHashI64(out, filePath.hashCode())
            out = CombineHashI64(out, begin.line)
            out = CombineHashI64(out, begin.column)
            out = CombineHashI64(out, IncrDeclKindIndex(astKind))
        }
        return out
    }

    public func AddAttr(attr: IncrAttribute): Unit {
        attrs.add(attr)
    }

    public func AddMember(member: IncrDecl): Unit {
        member.outerDecl = Some(this)
        if (member.fullPackageName.isEmpty()) {
            member.fullPackageName = fullPackageName
        }
        if (member.filePath.isEmpty()) {
            member.filePath = filePath
        }
        members.add(member)
    }

    public func AddGetter(getter: IncrDecl): Unit {
        getter.outerDecl = Some(this)
        getters.add(getter)
        members.add(getter)
    }

    public func AddSetter(setter: IncrDecl): Unit {
        setter.outerDecl = Some(this)
        setters.add(setter)
        members.add(setter)
    }

    public func TestAttr(attr: IncrAttribute): Bool {
        return attrs.contains(attr)
    }

    public func TestAnyAttr(left: IncrAttribute, right: IncrAttribute): Bool {
        return attrs.contains(left) || attrs.contains(right)
    }

    public func IsImported(): Bool {
        return TestAttr(IncrAttribute.IMPORTED)
    }

    public func IsNominalDecl(): Bool {
        return astKind == IncrDeclKind.ENUM_DECL || astKind == IncrDeclKind.STRUCT_DECL ||
            astKind == IncrDeclKind.CLASS_DECL || astKind == IncrDeclKind.INTERFACE_DECL ||
            astKind == IncrDeclKind.EXTEND_DECL
    }

    public func IsTypeDecl(): Bool {
        return IsNominalDecl() || astKind == IncrDeclKind.TYPE_ALIAS_DECL
    }

    public func IsConst(): Bool {
        return isConstValue || TestAttr(IncrAttribute.CONST)
    }

    public func IsStaticVar(): Bool {
        return astKind == IncrDeclKind.VAR_DECL && TestAttr(IncrAttribute.STATIC)
    }

    public func IsGlobalOrStaticVar(): Bool {
        return astKind == IncrDeclKind.VAR_DECL && (!HasOuterDecl() || TestAttr(IncrAttribute.STATIC) ||
            TestAttr(IncrAttribute.GLOBAL))
    }

    public func IsClassOrEnumConstructor(): Bool {
        return TestAttr(IncrAttribute.CONSTRUCTOR) || TestAttr(IncrAttribute.ENUM_CONSTRUCTOR) ||
            astKind == IncrDeclKind.PRIMARY_CTOR_DECL
    }

    public func IsDirectExtend(): Bool {
        return astKind == IncrDeclKind.EXTEND_DECL && HasExtendedTypeMangle() && constructorMangles.isEmpty()
    }

    public func DisplayName(): String {
        if (identifier.isEmpty()) {
            if (astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL) {
                return "VarWithPatternDecl"
            }
            if (astKind == IncrDeclKind.EXTEND_DECL) {
                return "ExtendDecl"
            }
            return IncrDeclKindName(astKind)
        }
        return identifier
    }

    public func HasOuterDecl(): Bool {
        if (let Some(_) <- outerDecl) {
            return true
        }
        return false
    }

    public func HasExtendedTypeMangle(): Bool {
        if (let Some(_) <- extendedTypeMangle) {
            return true
        }
        return false
    }

    public func AllMembersIncludingAccessors(): ArrayList<IncrDecl> {
        let out = ArrayList<IncrDecl>()
        for (member in members) {
            out.add(member)
        }
        for (getter in getters) {
            if (!out.contains(getter)) {
                out.add(getter)
            }
        }
        for (setter in setters) {
            if (!out.contains(setter)) {
                out.add(setter)
            }
        }
        return out
    }
}

public class IncrFile {
    public var fileName: String = ""
    public var filePath: String = ""
    public let decls: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let exportedInternalDecls: ArrayList<IncrDecl> = ArrayList<IncrDecl>()

    public init() {}

    public init(path: String) {
        this.filePath = path
        this.fileName = path
    }

    public func AddDecl(decl: IncrDecl): Unit {
        decl.filePath = filePath
        decls.add(decl)
    }
}

public class IncrPackage {
    public var fullPackageName: String = ""
    public var specsHash: UInt64 = 0u64
    public let files: ArrayList<IncrFile> = ArrayList<IncrFile>()

    public init() {}

    public init(fullPackageName: String) {
        this.fullPackageName = fullPackageName
    }

    public func AddFile(file: IncrFile): Unit {
        for (decl in file.decls) {
            if (decl.fullPackageName.isEmpty()) {
                decl.fullPackageName = fullPackageName
            }
        }
        files.add(file)
    }

    public func AllTopLevelDecls(): ArrayList<IncrDecl> {
        let out = ArrayList<IncrDecl>()
        for (file in files) {
            for (decl in file.decls) {
                out.add(decl)
            }
            for (decl in file.exportedInternalDecls) {
                out.add(decl)
            }
        }
        return out
    }
}

public class IncrImportManager {
    public let importedPackages: ArrayList<IncrPackage> = ArrayList<IncrPackage>()
    private let packageDecls: HashMap<String, IncrDecl> = HashMap<String, IncrDecl>()

    public init() {}

    public func AddImportedPackage(pkg: IncrPackage): Unit {
        importedPackages.add(pkg)
    }

    public func GetAllImportedPackages(): ArrayList<IncrPackage> {
        return importedPackages
    }

    public func RegisterPackageDecl(packageName: String, decl: IncrDecl): Unit {
        packageDecls[packageName] = decl
    }

    public func GetPackageDecl(packageName: String): Option<IncrDecl> {
        return packageDecls.get(packageName)
    }
}

public class IncrGlobalOptions {
    public var enableCompileDebug: Bool = false
    public var displayLineInfo: Bool = false
    public var cachedAstPath: String = ""
    public var serializedFilePath: String = ""
    public let compileArgs: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func ToSerialized(): ArrayList<String> {
        return CloneStringList(compileArgs)
    }

    public func GenerateCachedPathName(packageName: String, extension: String): String {
        if (extension == CACHED_AST_EXTENSION && !cachedAstPath.isEmpty()) {
            return cachedAstPath
        }
        if (extension == SERIALIZED_FILE_EXTENSION && !serializedFilePath.isEmpty()) {
            return serializedFilePath
        }
        return packageName.replace(".", "_") + extension
    }
}

public class GlobalVarIndex <: Hashable & Equatable<GlobalVarIndex> {
    public var file: String = ""
    public var id: Int64 = 0

    public init() {}

    public init(file: String, id: Int64) {
        this.file = file
        this.id = id
    }

    public operator func ==(right: GlobalVarIndex): Bool {
        return file == right.file && id == right.id
    }

    public operator func !=(right: GlobalVarIndex): Bool {
        return !(this == right)
    }

    public operator func <(right: GlobalVarIndex): Bool {
        return file < right.file || (file == right.file && id < right.id)
    }

    public func hashCode(): Int64 {
        return CombineHashI64(file.hashCode(), id)
    }

    public func ToString(): String {
        return "(" + file + ", " + id.toString() + ")"
    }
}

public open class DeclCacheBase {
    public var sigHash: UInt64 = 0u64
    public var srcUse: UInt64 = 0u64
    public var bodyHash: UInt64 = 0u64
    public var astKind: UInt8 = 0u8
    public var isGV: Bool = false
    public var gvid: GlobalVarIndex = GlobalVarIndex()
    public let members: ArrayList<MemberDeclCache> = ArrayList<MemberDeclCache>()
    public var cgMangle: String = ""

    public init() {}

    public func CopyBaseTo(target: DeclCacheBase): Unit {
        target.sigHash = sigHash
        target.srcUse = srcUse
        target.bodyHash = bodyHash
        target.astKind = astKind
        target.isGV = isGV
        target.gvid = GlobalVarIndex(gvid.file, gvid.id)
        target.cgMangle = cgMangle
        for (member in members) {
            target.members.add(member.Clone())
        }
    }
}

public class MemberDeclCache <: DeclCacheBase {
    public var rawMangle: String = ""

    public init() {}

    public init(rawMangle: String) {
        this.rawMangle = rawMangle
    }

    public func Clone(): MemberDeclCache {
        let out = MemberDeclCache(rawMangle)
        CopyBaseTo(out)
        return out
    }
}

public class TopLevelDeclCache <: DeclCacheBase {
    public let extends: ArrayList<String> = ArrayList<String>()
    public var instVarHash: UInt64 = 0u64
    public var virtHash: UInt64 = 0u64

    public init() {}

    public func Clone(): TopLevelDeclCache {
        let out = TopLevelDeclCache()
        CopyBaseTo(out)
        for (ext in extends) {
            out.extends.add(ext)
        }
        out.instVarHash = instVarHash
        out.virtHash = virtHash
        return out
    }
}

public class NameUsage {
    public let parentDecls: HashSet<String> = HashSet<String>()
    public let packageQualifiers: HashSet<String> = HashSet<String>()
    public var hasUnqualifiedUsage: Bool = false
    public var hasUnqualifiedUsageOfImported: Bool = false

    public init() {}
}

public class UseInfo {
    public let usedDecls: HashSet<String> = HashSet<String>()
    public let usedNames: HashMap<String, NameUsage> = HashMap<String, NameUsage>()

    public init() {}
}

public class SemaUsage {
    public var apiUsages: UseInfo = UseInfo()
    public var bodyUsages: UseInfo = UseInfo()
    public let boxedTypes: HashSet<String> = HashSet<String>()

    public init() {}
}

public class SemaRelation {
    public let inherits: HashSet<String> = HashSet<String>()
    public let extends: HashSet<String> = HashSet<String>()
    public let extendedInterfaces: HashSet<String> = HashSet<String>()

    public init() {}
}

public class SemanticInfo {
    public let usages: HashMap<IncrDecl, SemaUsage> = HashMap<IncrDecl, SemaUsage>()
    public let relations: HashMap<String, SemaRelation> = HashMap<String, SemaRelation>()
    public let builtInTypeRelations: HashMap<String, SemaRelation> = HashMap<String, SemaRelation>()
    public let compilerAddedUsages: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()

    public init() {}
}

public class DeclDependency {
    public var decl: IncrDecl
    public let dependencies: ArrayList<IncrDecl> = ArrayList<IncrDecl>()

    public init(decl: IncrDecl) {
        this.decl = decl
    }
}

public class CompilationCache {
    public var specs: UInt64 = 0u64
    public var lambdaCounter: UInt64 = 0u64
    public var stringLiteralCounter: UInt64 = 0u64
    public var envClassCounter: UInt64 = 0u64
    public let compileArgs: ArrayList<String> = ArrayList<String>()
    public let varAndFuncDep: ArrayList<DeclDependency> = ArrayList<DeclDependency>()
    public let chirOptInfo: OptEffectStrMap = OptEffectStrMap()
    public let virtualFuncDep: VirtualWrapperDepMap = VirtualWrapperDepMap()
    public let varInitDepMap: VarInitDepMap = VarInitDepMap()
    public let ccOutFuncs: HashSet<String> = HashSet<String>()
    public var semaInfo: SemanticInfo = SemanticInfo()
    public let curPkgASTCache: ASTCache = ASTCache()
    public let fileMap: CachedFileMap = CachedFileMap()
    public let importedASTCache: ASTCache = ASTCache()
    public let bitcodeFilesName: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func ClearAST(): Unit {
        curPkgASTCache.clear()
        fileMap.clear()
        importedASTCache.clear()
    }
}

public class DirectExtendEntry {
    public var decl: IncrDecl
    public var gvid: Int64 = 0

    public init(decl: IncrDecl, gvid: Int64) {
        this.decl = decl
        this.gvid = gvid
    }
}

public func CombineHashI64(left: Int64, right: Int64): Int64 {
    return left ^ (right + 0x517cc1b727220a95i64 + (left << 6) + (left >> 2))
}

public func CombineHash(left: UInt64, right: UInt64): UInt64 {
    return left ^ (right + 0x9e3779b97f4a7c15u64 + (left << 6) + (left >> 2))
}

public func StableHash(value: String): UInt64 {
    var hash = 1469598103934665603u64
    for (byte in value.toArray()) {
        hash = (hash ^ UInt64(byte)) * 1099511628211u64
    }
    return hash
}

public func StableHashBool(value: Bool): UInt64 {
    return if (value) { 1u64 } else { 0u64 }
}

public func CloneStringList(values: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CloneStringSet(values: HashSet<String>): HashSet<String> {
    let out = HashSet<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}
