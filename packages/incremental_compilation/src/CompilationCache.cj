package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.*

public type RawMangledName = String
public type RawMangled2DeclMap = HashMap<RawMangledName, Decl>
public type OptEffectStrMap = HashMap<RawMangledName, HashSet<RawMangledName>>
public type OptEffectNodeMap = HashMap<Decl, HashSet<Decl>>
public type SrcImportedDepMap = HashMap<Decl, HashSet<Decl>>
public type VirtualWrapperDepMap = HashMap<RawMangledName, String>
public type VarInitDepMap = HashMap<RawMangledName, String>
public type FileMap = HashMap<String, ArrayList<Decl>>
public type CachedFileMap = HashMap<String, ArrayList<RawMangledName>>
public type ASTCache = HashMap<RawMangledName, TopLevelDeclCache>

public let CACHED_AST_EXTENSION: String = ".cachedast"
public let SERIALIZED_FILE_EXTENSION: String = ".cjo"

public class GlobalVarIndex {
    public var file: String = ""
    public var id: Int64 = 0

    public init() {}

    public init(file: String, id: Int64) {
        this.file = file
        this.id = id
    }

    public operator func <(right: GlobalVarIndex): Bool {
        return file == right.file && id < right.id
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
}

public class MemberDeclCache <: DeclCacheBase {
    public var rawMangle: RawMangledName = ""

    public init() {}

    public init(rawMangle: RawMangledName) {
        this.rawMangle = rawMangle
    }
}

public class TopLevelDeclCache <: DeclCacheBase {
    public let extends: ArrayList<RawMangledName> = ArrayList<RawMangledName>()
    public var instVarHash: UInt64 = 0u64
    public var virtHash: UInt64 = 0u64

    public init() {}
}

public class NameUsage {
    public let parentDecls: HashSet<RawMangledName> = HashSet<RawMangledName>()
    public let packageQualifiers: HashSet<String> = HashSet<String>()
    public var hasUnqualifiedUsage: Bool = false
    public var hasUnqualifiedUsageOfImported: Bool = false

    public init() {}
}

public class UseInfo {
    public let usedDecls: HashSet<RawMangledName> = HashSet<RawMangledName>()
    public let usedNames: HashMap<String, NameUsage> = HashMap<String, NameUsage>()

    public init() {}
}

public class SemaUsage {
    public var apiUsages: UseInfo = UseInfo()
    public var bodyUsages: UseInfo = UseInfo()
    public let boxedTypes: HashSet<RawMangledName> = HashSet<RawMangledName>()

    public init() {}
}

public class SemaRelation {
    public let inherits: HashSet<RawMangledName> = HashSet<RawMangledName>()
    public let extends: HashSet<RawMangledName> = HashSet<RawMangledName>()
    public let extendedInterfaces: HashSet<RawMangledName> = HashSet<RawMangledName>()

    public init() {}
}

public class SemanticInfo {
    public let usages: HashMap<Decl, SemaUsage> = HashMap<Decl, SemaUsage>()
    public let relations: HashMap<RawMangledName, SemaRelation> = HashMap<RawMangledName, SemaRelation>()
    public let builtInTypeRelations: HashMap<String, SemaRelation> = HashMap<String, SemaRelation>()
    public let compilerAddedUsages: HashMap<RawMangledName, HashSet<String>> =
        HashMap<RawMangledName, HashSet<String>>()

    public init() {}
}

public class CompilationCache {
    public var specs: UInt64 = 0u64
    public var lambdaCounter: UInt64 = 0u64
    public var stringLiteralCounter: UInt64 = 0u64
    public var envClassCounter: UInt64 = 0u64
    public let compileArgs: ArrayList<String> = ArrayList<String>()
    public let varAndFuncDep: ArrayList<(Decl, ArrayList<Decl>)> = ArrayList<(Decl, ArrayList<Decl>)>()
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
}
