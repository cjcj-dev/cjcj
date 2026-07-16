package cjcj::incremental_compilation

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::basic.CANGJIE_VERSION
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset, FlatBufferString, VerifierOptions, VerifierTemplate}
import cjcj::modules.{FB_MAX_DEPTH, FB_MAX_TABLES}
import cjcj::parse.ASTHasher

public class HashedASTWriter {
    private let builder: FlatBufferBuilder = FlatBufferBuilder()
    private let bitcodeFilesName: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let compileArgs: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let varAndFunc: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let chirOptInfo: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let virtualFuncDep: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let varInitDep: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let ccOutFuncs: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private var semaUsages: FlatBufferOffset = 0u32
    private var allAST: FlatBufferOffset = 0u32
    private var importedDecls: FlatBufferOffset = 0u32
    private var lambdaCounter: UInt64 = 0u64
    private var envClassCounter: UInt64 = 0u64
    private var stringLiteralCounter: UInt64 = 0u64
    private var specs: UInt64 = 0u64

    public init() {}

    public func SetImportSpecs(packageValue: Package): Unit {
        specs = ASTHasher.HashSpecs(packageValue)
    }

    public func SetLambdaCounter(counter: UInt64): Unit { lambdaCounter = counter }

    public func SetEnvClassCounter(counter: UInt64): Unit { envClassCounter = counter }

    public func SetStringLiteralCounter(counter: UInt64): Unit { stringLiteralCounter = counter }

    public func SetCompileArgs(args: ArrayList<String>): Unit {
        for (arg in args) { compileArgs.add(builder.CreateSharedString(arg)) }
    }

    public func SetVarAndFuncDependency(varAndFuncDep: ArrayList<(Decl, ArrayList<Decl>)>): Unit {
        let orderedDep = ArrayList<(String, ArrayList<Decl>)>()
        for (dependency in varAndFuncDep) {
            var found = false
            for (entry in orderedDep) {
                if (entry[0] == dependency[0].rawMangleName) { found = true; break }
            }
            if (!found) { orderedDep.add((dependency[0].rawMangleName, dependency[1])) }
        }
        sort(orderedDep, by: { left: (String, ArrayList<Decl>), right: (String, ArrayList<Decl>) =>
            if (left[0] < right[0]) { Ordering.LT } else if (left[0] > right[0]) { Ordering.GT } else { Ordering.EQ }
        }, stable: true)
        for (dependency in orderedDep) {
            let stringDependencies = ArrayList<String>()
            for (decl in dependency[1]) { stringDependencies.add(decl.rawMangleName) }
            sort(stringDependencies)
            let dependencyOffset = builder.CreateVectorOfStrings(stringDependencies)
            let declNameOffset = builder.CreateString(dependency[0])
            varAndFunc.add(CreateDeclDep(builder, declNameOffset, dependencyOffset))
        }
    }

    public func SetCHIROptInfo(optInfo: OptEffectStrMap): Unit {
        for ((declName, effects) in optInfo) {
            let values = ArrayList<String>()
            for (effect in effects) { values.add(effect) }
            sort(values)
            chirOptInfo.add(CreateEffectMap(builder, builder.CreateString(declName),
                builder.CreateVectorOfStrings(values)))
        }
    }

    public func SetVirtualFuncDep(depMap: VirtualWrapperDepMap): Unit {
        for ((raw, wrapper) in depMap) {
            virtualFuncDep.add(CreateVirtualDep(builder, builder.CreateSharedString(raw),
                builder.CreateSharedString(wrapper)))
        }
    }

    public func SetVarInitDep(depMap: VarInitDepMap): Unit {
        for ((raw, wrapper) in depMap) {
            varInitDep.add(CreateVirtualDep(builder, builder.CreateSharedString(raw),
                builder.CreateSharedString(wrapper)))
        }
    }

    public func SetCCOutFuncs(funcs: HashSet<String>): Unit {
        for (funcName in funcs) { ccOutFuncs.add(builder.CreateSharedString(funcName)) }
    }

    public func SetBitcodeFilesName(bitcodeFiles: ArrayList<String>): Unit {
        for (fileName in bitcodeFiles) { bitcodeFilesName.add(builder.CreateSharedString(fileName)) }
    }

    public func SetSemanticInfo(info: SemanticInfo): Unit {
        semaUsages = CreateSemanticInfo(builder, builder.CreateVectorOffsets(CreateUsages(builder, info.usages)),
            builder.CreateVectorOffsets(CreateRelations(builder, info.relations)),
            builder.CreateVectorOffsets(CreateRelations(builder, info.builtInTypeRelations)),
            builder.CreateVectorOffsets(CreateAddedRelations(builder, info.compilerAddedUsages)))
    }

    public func WriteAllDecls(ast: ASTCache, imports: ASTCache, order: ArrayList<Decl>): Unit {
        allAST = WriteCachedAST(builder, ast, order)
        importedDecls = WriteImported(builder, imports)
    }

    public func AST2FB(pkgName: String): Array<UInt8> {
        let root = CreateHashedPackage(builder, builder.CreateString(CANGJIE_VERSION), builder.CreateString(pkgName),
            specs, builder.CreateVectorOffsets(compileArgs), allAST, importedDecls,
            builder.CreateVectorOffsets(varAndFunc), builder.CreateVectorOffsets(chirOptInfo),
            builder.CreateVectorOffsets(virtualFuncDep), builder.CreateVectorOffsets(varInitDep),
            builder.CreateVectorOffsets(ccOutFuncs), lambdaCounter, envClassCounter, stringLiteralCounter,
            semaUsages, builder.CreateVectorOffsets(bitcodeFilesName))
        return FinishHashedPackageBuffer(builder, root)
    }
}

public class HashedASTLoader {
    private let serializedData: Array<UInt8>
    private let fileMap: HashMap<String, ArrayList<(RawMangledName, Int64)>> =
        HashMap<String, ArrayList<(RawMangledName, Int64)>>()

    public init(astData: Array<UInt8>) {
        serializedData = astData
    }

    private func VerifyData(): Bool {
        var options = VerifierOptions()
        options.maxDepth = UInt32(FB_MAX_DEPTH)
        options.maxTables = UInt32(FB_MAX_TABLES)
        return VerifyHashedPackageBuffer(serializedData, VerifierTemplate(serializedData, opts: options))
    }

    public func DeserializeData(mangledName2DeclMap: RawMangled2DeclMap): (Bool, CompilationCache) {
        if (!VerifyData()) { return (false, CompilationCache()) }
        let packageInfo = GetHashedPackage(serializedData)
        if (packageInfo.version().getOrThrow().str() != CANGJIE_VERSION) {
            return (false, CompilationCache())
        }
        let cached = CompilationCache()
        if (let Some(args) <- packageInfo.compileOptionArgs()) {
            var idx: UInt32 = 0u32
            while (idx < args.size()) {
                cached.compileArgs.add(FlatBufferString(args.data, (args.Get(idx) as Int64).getOrThrow()).str())
                idx++
            }
        }
        if (let Some(files) <- packageInfo.bitcodeFilesName()) {
            var idx: UInt32 = 0u32
            while (idx < files.size()) {
                cached.bitcodeFilesName.add(FlatBufferString(files.data,
                    (files.Get(idx) as Int64).getOrThrow()).str())
                idx++
            }
        }
        for ((mangle, value) in LoadCachedAST(packageInfo)) { cached.curPkgASTCache[mangle] = value }
        for ((file, entries) in fileMap) {
            sort(entries, by: { left: (RawMangledName, Int64), right: (RawMangledName, Int64) =>
                if (left[1] < right[1]) { Ordering.LT } else if (left[1] > right[1]) { Ordering.GT } else {
                    Ordering.EQ
                }
            }, stable: true)
            let mangles = ArrayList<RawMangledName>()
            for (entry in entries) { mangles.add(entry[0]) }
            cached.fileMap[file] = mangles
        }
        for ((mangle, value) in LoadImported(packageInfo)) { cached.importedASTCache[mangle] = value }
        cached.specs = packageInfo.specs()
        cached.lambdaCounter = packageInfo.lambdaCounter()
        cached.envClassCounter = packageInfo.envClassCounter()
        cached.stringLiteralCounter = packageInfo.strLitCounter()
        cached.semaInfo = LoadSemanticInfos(packageInfo, mangledName2DeclMap)
        LoadCHIROptInfo(packageInfo, mangledName2DeclMap, cached)
        LoadVirtualFuncDep(packageInfo, cached)
        LoadVarInitDep(packageInfo, cached)
        LoadCCOutFunc(packageInfo, cached)
        return (true, cached)
    }

    private func Load(decl: CachedASTFormat_MemberDecl): MemberDeclCache {
        let result = MemberDeclCache()
        result.sigHash = decl.sig()
        result.srcUse = decl.srcUse()
        result.bodyHash = decl.body()
        result.astKind = decl.`type`()
        let gvid = decl.gvid().getOrThrow()
        result.gvid = GlobalVarIndex(gvid.file().getOrThrow().str(), Int64(gvid.id()))
        result.isGV = decl.isGV()
        if (let Some(members) <- decl.members()) {
            var idx: UInt32 = 0u32
            while (idx < members.size()) {
                result.members.add(Load(CachedASTFormat_MemberDecl(members.data,
                    (members.Get(idx) as Int64).getOrThrow())))
                idx++
            }
        }
        result.rawMangle = decl.mangle().getOrThrow().str()
        result.cgMangle = decl.cgMangle().getOrThrow().str()
        return result
    }

    private static func IsOOEAffectedDecl(decl: MemberDeclCache): Bool {
        return decl.astKind == UInt8(ASTKindIndex(ASTKind.VAR_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.PRIMARY_CTOR_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.FUNC_DECL))
    }

    private static func IsOOEAffectedDecl(decl: TopLevelDeclCache): Bool {
        return decl.astKind == UInt8(ASTKindIndex(ASTKind.VAR_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.VAR_WITH_PATTERN_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.FUNC_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.MAIN_DECL)) ||
            decl.astKind == UInt8(ASTKindIndex(ASTKind.MACRO_DECL))
    }

    private func Load(decl: CachedASTFormat_TopDecl, srcPkg: Bool): TopLevelDeclCache {
        let result = TopLevelDeclCache()
        result.sigHash = decl.sig()
        result.srcUse = decl.srcUse()
        result.bodyHash = decl.body()
        result.astKind = decl.`type`()
        result.instVarHash = decl.instVar()
        result.virtHash = decl.virt()
        if (srcPkg) {
            let gvid = decl.gvid().getOrThrow()
            result.gvid = GlobalVarIndex(gvid.file().getOrThrow().str(), Int64(gvid.id()))
            result.isGV = decl.isGV()
        }
        if (let Some(members) <- decl.members()) {
            var idx: UInt32 = 0u32
            while (idx < members.size()) {
                result.members.add(Load(CachedASTFormat_MemberDecl(members.data,
                    (members.Get(idx) as Int64).getOrThrow())))
                idx++
            }
            if (srcPkg) {
                for (member in result.members) {
                    if (member.isGV) {
                        if (!fileMap.contains(member.gvid.file)) {
                            fileMap[member.gvid.file] = ArrayList<(RawMangledName, Int64)>()
                        }
                        fileMap[member.gvid.file].add((member.rawMangle, member.gvid.id))
                    }
                }
                for (member in result.members) {
                    for (nested in member.members) {
                        if (!fileMap.contains(nested.gvid.file)) {
                            fileMap[nested.gvid.file] = ArrayList<(RawMangledName, Int64)>()
                        }
                        fileMap[nested.gvid.file].add((nested.rawMangle, nested.gvid.id))
                    }
                    if (IsOOEAffectedDecl(member) && !member.isGV) {
                        if (!fileMap.contains(member.gvid.file)) {
                            fileMap[member.gvid.file] = ArrayList<(RawMangledName, Int64)>()
                        }
                        fileMap[member.gvid.file].add((member.rawMangle, member.gvid.id))
                    }
                }
            }
        }
        if (let Some(extends) <- decl.extends()) {
            var idx: UInt32 = 0u32
            while (idx < extends.size()) {
                result.extends.add(FlatBufferString(extends.data, (extends.Get(idx) as Int64).getOrThrow()).str())
                idx++
            }
        }
        result.cgMangle = decl.cgMangle().getOrThrow().str()
        return result
    }

    private func LoadCachedAST(packageInfo: CachedASTFormat_HashedPackage): ASTCache {
        let result = ASTCache()
        if (let Some(topDecls) <- packageInfo.topDecls()) {
            var idx: UInt32 = 0u32
            while (idx < topDecls.size()) {
                let topDecl = CachedASTFormat_TopDecl(topDecls.data,
                    (topDecls.Get(idx) as Int64).getOrThrow())
                let cache = Load(topDecl, true)
                if (IsOOEAffectedDecl(cache) &&
                    !(cache.astKind == UInt8(ASTKindIndex(ASTKind.VAR_DECL)) && !cache.isGV)) {
                    let gvid = topDecl.gvid().getOrThrow()
                    let file = gvid.file().getOrThrow().str()
                    if (!fileMap.contains(file)) { fileMap[file] = ArrayList<(RawMangledName, Int64)>() }
                    fileMap[file].add((topDecl.mangle().getOrThrow().str(), Int64(gvid.id())))
                }
                result[topDecl.mangle().getOrThrow().str()] = cache
                idx++
            }
        }
        return result
    }

    private func LoadImported(packageInfo: CachedASTFormat_HashedPackage): ASTCache {
        let result = ASTCache()
        if (let Some(topDecls) <- packageInfo.importedDecls()) {
            var idx: UInt32 = 0u32
            while (idx < topDecls.size()) {
                let topDecl = CachedASTFormat_TopDecl(topDecls.data,
                    (topDecls.Get(idx) as Int64).getOrThrow())
                result[topDecl.mangle().getOrThrow().str()] = Load(topDecl, false)
                idx++
            }
        }
        return result
    }

    private static func LoadSemanticInfos(packageInfo: CachedASTFormat_HashedPackage,
        mangledName2DeclMap: RawMangled2DeclMap): SemanticInfo {
        let info = SemanticInfo()
        if (let None <- packageInfo.semanticInfo()) { return info }
        let semaInfo = packageInfo.semanticInfo().getOrThrow()
        if (let Some(usages) <- semaInfo.usages()) {
            var idx: UInt32 = 0u32
            while (idx < usages.size()) {
                let usageOff = CachedASTFormat_Usage(usages.data,
                    (usages.Get(idx) as Int64).getOrThrow())
                let definition = usageOff.definition().getOrThrow().str()
                if (let Some(decl) <- mangledName2DeclMap.get(definition)) {
                    let usage = SemaUsage()
                    usage.apiUsages = GetUseInfo(usageOff.apiUsage())
                    usage.bodyUsages = GetUseInfo(usageOff.bodyUsage())
                    for (boxedType in GetSetStrings(usageOff.boxedTypes())) {
                        usage.boxedTypes.add(boxedType)
                    }
                    info.usages[decl] = usage
                }
                idx++
            }
        }
        if (let Some(relations) <- semaInfo.relations()) {
            var idx: UInt32 = 0u32
            while (idx < relations.size()) {
                let relationOff = CachedASTFormat_Relation(relations.data,
                    (relations.Get(idx) as Int64).getOrThrow())
                let relation = SemaRelation()
                for (mangle in GetSetStrings(relationOff.inherited())) { relation.inherits.add(mangle) }
                for (mangle in GetSetStrings(relationOff.extends())) { relation.extends.add(mangle) }
                for (mangle in GetSetStrings(relationOff.extendInterfaces())) {
                    relation.extendedInterfaces.add(mangle)
                }
                info.relations[relationOff.definition().getOrThrow().str()] = relation
                idx++
            }
        }
        if (let Some(relations) <- semaInfo.builtInTypeRelations()) {
            var idx: UInt32 = 0u32
            while (idx < relations.size()) {
                let relationOff = CachedASTFormat_Relation(relations.data,
                    (relations.Get(idx) as Int64).getOrThrow())
                let relation = SemaRelation()
                for (mangle in GetSetStrings(relationOff.extends())) { relation.extends.add(mangle) }
                for (mangle in GetSetStrings(relationOff.extendInterfaces())) {
                    relation.extendedInterfaces.add(mangle)
                }
                info.builtInTypeRelations[relationOff.definition().getOrThrow().str()] = relation
                idx++
            }
        }
        if (let Some(relations) <- semaInfo.compilerAddedUsages()) {
            var idx: UInt32 = 0u32
            while (idx < relations.size()) {
                let relationOff = CachedASTFormat_CompilerAddedUsage(relations.data,
                    (relations.Get(idx) as Int64).getOrThrow())
                info.compilerAddedUsages[relationOff.definition().getOrThrow().str()] =
                    GetSetStrings(relationOff.related())
                idx++
            }
        }
        return info
    }
}
