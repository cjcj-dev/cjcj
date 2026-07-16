package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset, FlatBufferString}
import cjcj::utils.FileUtil

private func Write(builder: FlatBufferBuilder, decl: MemberDeclCache): FlatBufferOffset {
    let mangle = builder.CreateSharedString(decl.rawMangle)
    let file = builder.CreateSharedString(decl.gvid.file)
    let gvid = CreateGlobalVarIndex(builder, file, decl.gvid.id)
    var memberOffset: FlatBufferOffset = 0u32
    if (!decl.members.isEmpty()) {
        let members = ArrayList<FlatBufferOffset>()
        for (member in decl.members) { members.add(Write(builder, member)) }
        memberOffset = builder.CreateVectorOffsets(members)
    }
    let cgMangle = builder.CreateSharedString(decl.cgMangle)
    return CreateMemberDecl(builder, mangle, decl.sigHash, decl.srcUse, decl.bodyHash, decl.astKind, decl.isGV,
        gvid, memberOffset, cgMangle)
}

private func Write(builder: FlatBufferBuilder, mangle: RawMangledName,
    decl: TopLevelDeclCache): FlatBufferOffset {
    let rawMangle = builder.CreateSharedString(mangle)
    let file = builder.CreateSharedString(decl.gvid.file)
    let gvid = CreateGlobalVarIndex(builder, file, decl.gvid.id)
    var memberOffset: FlatBufferOffset = 0u32
    if (!decl.members.isEmpty()) {
        let members = ArrayList<FlatBufferOffset>()
        for (member in decl.members) {
            if (member.isGV) { members.add(Write(builder, member)) }
        }
        for (member in decl.members) {
            if (!member.isGV) { members.add(Write(builder, member)) }
        }
        memberOffset = builder.CreateVectorOffsets(members)
    }
    var extendsOffset: FlatBufferOffset = 0u32
    if (!decl.extends.isEmpty()) {
        extendsOffset = builder.CreateVectorOfStrings(decl.extends)
    }
    let cgMangle = builder.CreateSharedString(decl.cgMangle)
    return CreateTopDecl(builder, rawMangle, decl.sigHash, decl.srcUse, decl.bodyHash, decl.astKind, decl.isGV,
        decl.instVarHash, decl.virtHash, gvid, memberOffset, extendsOffset, cgMangle)
}

func WriteCachedAST(builder: FlatBufferBuilder, ast: ASTCache,
    order: ArrayList<Decl>): FlatBufferOffset {
    if (ast.isEmpty()) { return 0u32 }
    let result = ArrayList<FlatBufferOffset>()
    for (decl in order) {
        let mangled = if (let Some(mainDecl) <- (decl as MainDecl)) {
            mainDecl.desugarDecl.getOrThrow().rawMangleName
        } else {
            decl.rawMangleName
        }
        result.add(Write(builder, mangled, ast[mangled]))
    }
    return builder.CreateVectorOffsets(result)
}

func WriteImported(builder: FlatBufferBuilder, imports: ASTCache): FlatBufferOffset {
    if (imports.isEmpty()) { return 0u32 }
    let result = ArrayList<FlatBufferOffset>()
    for ((mangle, decl) in imports) { result.add(Write(builder, mangle, decl)) }
    return builder.CreateVectorOffsets(result)
}

private func GetDepRelationAsDecl(declMangle: RawMangledName, dependencies: ArrayList<String>,
    mangledName2DeclMap: RawMangled2DeclMap): Option<(Decl, ArrayList<Decl>)> {
    if (let None <- mangledName2DeclMap.get(declMangle)) { return None }
    let deps = ArrayList<Decl>()
    for (dependency in dependencies) {
        if (let Some(decl) <- mangledName2DeclMap.get(dependency)) { deps.add(decl) }
    }
    return Some((mangledName2DeclMap[declMangle], deps))
}

func LoadCHIROptInfo(packageInfo: CachedASTFormat_HashedPackage,
    mangledName2DeclMap: RawMangled2DeclMap, cached: CompilationCache): Unit {
    if (let Some(varAndFunc) <- packageInfo.varAndFunc()) {
        var idx: UInt32 = 0u32
        while (idx < varAndFunc.size()) {
            let declDep = CachedASTFormat_DeclDep(varAndFunc.data,
                (varAndFunc.Get(idx) as Int64).getOrThrow())
            let dependencies = ArrayList<String>()
            if (let Some(dependencyVector) <- declDep.dependency()) {
                var depIdx: UInt32 = 0u32
                while (depIdx < dependencyVector.size()) {
                    dependencies.add(FlatBufferString(dependencyVector.data,
                        (dependencyVector.Get(depIdx) as Int64).getOrThrow()).str())
                    depIdx++
                }
                if (let Some(relation) <- GetDepRelationAsDecl(declDep.decl().getOrThrow().str(), dependencies,
                    mangledName2DeclMap)) {
                    cached.varAndFuncDep.add(relation)
                }
            }
            idx++
        }
    }
    if (let Some(chirOptInfo) <- packageInfo.chirOptInfo()) {
        var idx: UInt32 = 0u32
        while (idx < chirOptInfo.size()) {
            let effectMap = CachedASTFormat_EffectMap(chirOptInfo.data,
                (chirOptInfo.Get(idx) as Int64).getOrThrow())
            if (let Some(effectedDecls) <- effectMap.effectedDecls()) {
                let srcDecl = effectMap.srcDecl().getOrThrow().str()
                if (!cached.chirOptInfo.contains(srcDecl)) { cached.chirOptInfo[srcDecl] = HashSet<String>() }
                var effectIdx: UInt32 = 0u32
                while (effectIdx < effectedDecls.size()) {
                    cached.chirOptInfo[srcDecl].add(FlatBufferString(effectedDecls.data,
                        (effectedDecls.Get(effectIdx) as Int64).getOrThrow()).str())
                    effectIdx++
                }
            }
            idx++
        }
    }
}

func LoadVirtualFuncDep(packageInfo: CachedASTFormat_HashedPackage, cached: CompilationCache): Unit {
    if (let Some(dependencies) <- packageInfo.virtualDep()) {
        var idx: UInt32 = 0u32
        while (idx < dependencies.size()) {
            let dependency = CachedASTFormat_VirtualDep(dependencies.data,
                (dependencies.Get(idx) as Int64).getOrThrow())
            cached.virtualFuncDep[dependency.raw().getOrThrow().str()] = dependency.wrapper().getOrThrow().str()
            idx++
        }
    }
}

func LoadVarInitDep(packageInfo: CachedASTFormat_HashedPackage, cached: CompilationCache): Unit {
    if (let Some(dependencies) <- packageInfo.varInitDep()) {
        var idx: UInt32 = 0u32
        while (idx < dependencies.size()) {
            let dependency = CachedASTFormat_VirtualDep(dependencies.data,
                (dependencies.Get(idx) as Int64).getOrThrow())
            cached.varInitDepMap[dependency.raw().getOrThrow().str()] = dependency.wrapper().getOrThrow().str()
            idx++
        }
    }
}

func LoadCCOutFunc(packageInfo: CachedASTFormat_HashedPackage, cached: CompilationCache): Unit {
    if (let Some(functions) <- packageInfo.ccOutFuncs()) {
        var idx: UInt32 = 0u32
        while (idx < functions.size()) {
            cached.ccOutFuncs.add(FlatBufferString(functions.data,
                (functions.Get(idx) as Int64).getOrThrow()).str())
            idx++
        }
    }
}

public func WriteCache(pkg: Package, cachedInfo: CompilationCache, order: ArrayList<Decl>, path: String): Bool {
    let writer = HashedASTWriter()
    writer.SetImportSpecs(pkg)
    writer.SetLambdaCounter(cachedInfo.lambdaCounter)
    writer.SetEnvClassCounter(cachedInfo.envClassCounter)
    writer.SetStringLiteralCounter(cachedInfo.stringLiteralCounter)
    writer.SetCompileArgs(cachedInfo.compileArgs)
    writer.SetVarAndFuncDependency(cachedInfo.varAndFuncDep)
    writer.SetCHIROptInfo(cachedInfo.chirOptInfo)
    writer.SetVirtualFuncDep(cachedInfo.virtualFuncDep)
    writer.SetVarInitDep(cachedInfo.varInitDepMap)
    writer.SetCCOutFuncs(cachedInfo.ccOutFuncs)
    writer.SetSemanticInfo(cachedInfo.semaInfo)
    writer.SetBitcodeFilesName(cachedInfo.bitcodeFilesName)
    writer.WriteAllDecls(cachedInfo.curPkgASTCache, cachedInfo.importedASTCache, order)
    return FileUtil.WriteBufferToASTFile(path, writer.AST2FB(pkg.fullPackageName))
}
