package cjcj::incremental_compilation

import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

// CachedASTFormat_generated.h:101-1417. Each CreateX mirrors the generated
// CreateX signature, table width, slot number, scalar default, and add order.

public func CreateDeclDep(builder: FlatBufferBuilder, decl: FlatBufferOffset,
    dependency: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, dependency)
    builder.AddOffset(0, decl)
    return builder.EndTable()
}

public func CreateEffectMap(builder: FlatBufferBuilder, srcDecl: FlatBufferOffset,
    effectedDecls: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, effectedDecls)
    builder.AddOffset(0, srcDecl)
    return builder.EndTable()
}

public func CreateVirtualDep(builder: FlatBufferBuilder, raw: FlatBufferOffset,
    wrapper: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, wrapper)
    builder.AddOffset(0, raw)
    return builder.EndTable()
}

public func CreateUsage(builder: FlatBufferBuilder, definition: FlatBufferOffset,
    apiUsage: FlatBufferOffset, bodyUsage: FlatBufferOffset, boxedTypes: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, boxedTypes)
    builder.AddOffset(2, bodyUsage)
    builder.AddOffset(1, apiUsage)
    builder.AddOffset(0, definition)
    return builder.EndTable()
}

public func CreateUseInfo(builder: FlatBufferBuilder, usedDecls: FlatBufferOffset,
    usedNames: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, usedNames)
    builder.AddOffset(0, usedDecls)
    return builder.EndTable()
}

public func CreateNameInfo(builder: FlatBufferBuilder, name: FlatBufferOffset,
    conditions: FlatBufferOffset, parentDecls: FlatBufferOffset, qualifiers: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, qualifiers)
    builder.AddOffset(2, parentDecls)
    builder.AddOffset(1, conditions)
    builder.AddOffset(0, name)
    return builder.EndTable()
}

public func CreateRelation(builder: FlatBufferBuilder, definition: FlatBufferOffset,
    inherited: FlatBufferOffset, extends: FlatBufferOffset, extendInterfaces: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, extendInterfaces)
    builder.AddOffset(2, extends)
    builder.AddOffset(1, inherited)
    builder.AddOffset(0, definition)
    return builder.EndTable()
}

public func CreateCompilerAddedUsage(builder: FlatBufferBuilder, definition: FlatBufferOffset,
    related: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, related)
    builder.AddOffset(0, definition)
    return builder.EndTable()
}

public func CreateSemanticInfo(builder: FlatBufferBuilder, usages: FlatBufferOffset,
    relations: FlatBufferOffset, builtInTypeRelations: FlatBufferOffset,
    compilerAddedUsages: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, compilerAddedUsages)
    builder.AddOffset(2, builtInTypeRelations)
    builder.AddOffset(1, relations)
    builder.AddOffset(0, usages)
    return builder.EndTable()
}

public func CreateGlobalVarIndex(builder: FlatBufferBuilder, file: FlatBufferOffset,
    id: Int64): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddI32(1, id, defaultValue: 0)
    builder.AddOffset(0, file)
    return builder.EndTable()
}

public func CreateMemberDecl(builder: FlatBufferBuilder, mangle: FlatBufferOffset, sig: UInt64,
    srcUse: UInt64, body: UInt64, type: UInt8, isGV: Bool, gvid: FlatBufferOffset,
    members: FlatBufferOffset, cgMangle: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(9)
    builder.AddU64(3, body, defaultValue: 0u64)
    builder.AddU64(2, srcUse, defaultValue: 0u64)
    builder.AddU64(1, sig, defaultValue: 0u64)
    builder.AddOffset(8, cgMangle)
    builder.AddOffset(7, members)
    builder.AddOffset(6, gvid)
    builder.AddOffset(0, mangle)
    builder.AddBool(5, isGV, defaultValue: false)
    builder.AddU8(4, type, defaultValue: 0u8)
    return builder.EndTable()
}

public func CreateTopDecl(builder: FlatBufferBuilder, mangle: FlatBufferOffset, sig: UInt64,
    srcUse: UInt64, body: UInt64, type: UInt8, isGV: Bool, instVar: UInt64, virt: UInt64,
    gvid: FlatBufferOffset, members: FlatBufferOffset, extends: FlatBufferOffset,
    cgMangle: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(12)
    builder.AddU64(7, virt, defaultValue: 0u64)
    builder.AddU64(6, instVar, defaultValue: 0u64)
    builder.AddU64(3, body, defaultValue: 0u64)
    builder.AddU64(2, srcUse, defaultValue: 0u64)
    builder.AddU64(1, sig, defaultValue: 0u64)
    builder.AddOffset(11, cgMangle)
    builder.AddOffset(10, extends)
    builder.AddOffset(9, members)
    builder.AddOffset(8, gvid)
    builder.AddOffset(0, mangle)
    builder.AddBool(5, isGV, defaultValue: false)
    builder.AddU8(4, type, defaultValue: 0u8)
    return builder.EndTable()
}

public func CreateHashedPackage(builder: FlatBufferBuilder, version: FlatBufferOffset,
    packageName: FlatBufferOffset, specs: UInt64, compileOptionArgs: FlatBufferOffset,
    topDecls: FlatBufferOffset, importedDecls: FlatBufferOffset, varAndFunc: FlatBufferOffset,
    chirOptInfo: FlatBufferOffset, virtualDep: FlatBufferOffset, varInitDep: FlatBufferOffset,
    ccOutFuncs: FlatBufferOffset, lambdaCounter: UInt64, envClassCounter: UInt64,
    strLitCounter: UInt64, semanticInfo: FlatBufferOffset,
    bitcodeFilesName: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(16)
    builder.AddU64(13, strLitCounter, defaultValue: 0u64)
    builder.AddU64(12, envClassCounter, defaultValue: 0u64)
    builder.AddU64(11, lambdaCounter, defaultValue: 0u64)
    builder.AddU64(2, specs, defaultValue: 0u64)
    builder.AddOffset(15, bitcodeFilesName)
    builder.AddOffset(14, semanticInfo)
    builder.AddOffset(10, ccOutFuncs)
    builder.AddOffset(9, varInitDep)
    builder.AddOffset(8, virtualDep)
    builder.AddOffset(7, chirOptInfo)
    builder.AddOffset(6, varAndFunc)
    builder.AddOffset(5, importedDecls)
    builder.AddOffset(4, topDecls)
    builder.AddOffset(3, compileOptionArgs)
    builder.AddOffset(1, packageName)
    builder.AddOffset(0, version)
    return builder.EndTable()
}

public func FinishHashedPackageBuffer(builder: FlatBufferBuilder,
    root: FlatBufferOffset): Array<UInt8> {
    return builder.Finish(root, HashedPackageIdentifier())
}
