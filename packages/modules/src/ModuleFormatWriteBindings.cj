package cjcj::modules

import std.collection.ArrayList
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

// FlatBuffers write (create) bindings for the 58 tables of ModuleFormat.fbs.
// Each CreateX mirrors the generated CreateX: it opens a table with the exact
// field count, slots each field at its generated field index ((VT-4)/2), and
// applies the schema default so unset fields are elided. Struct fields take the
// packed byte image from ModuleFormatStructs.cj; offset fields (tables, strings,
// vectors, union values) take a prebuilt FlatBufferOffset (0 = absent). Field
// add order is not observable to readers; alignment is handled per element by
// the builder. FlatBufferBuilder uses 0-based field indexes (Slot).

// ModuleFormat_generated.h:2124-2138 (CreateFullId).
func CreateFullId(builder: FlatBufferBuilder, pkgId: Int64, decl: FlatBufferOffset, index: UInt32): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU32(2, index, defaultValue: 0u32)
    builder.AddOffset(1, decl)
    builder.AddI32(0, pkgId, defaultValue: 0)
    return builder.EndTable()
}

// ModuleFormat_generated.h:2124-2138 (CreateConstraint).
func CreateConstraint(builder: FlatBufferBuilder, begin: ArrayList<UInt8>, end: ArrayList<UInt8>, ty: UInt32,
    uppers: FlatBufferOffset, isImplicitlyIntroduced: Bool): FlatBufferOffset {
    builder.StartTable(5)
    builder.AddBool(4, isImplicitlyIntroduced, defaultValue: false)
    builder.AddOffset(3, uppers)
    builder.AddU32(2, ty, defaultValue: 0u32)
    builder.AddStruct(1, end, 4)
    builder.AddStruct(0, begin, 4)
    return builder.EndTable()
}

// ModuleFormat_generated.h:2201-2209 (CreateGeneric).
func CreateGeneric(builder: FlatBufferBuilder, typeParameters: FlatBufferOffset, constraints: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, constraints)
    builder.AddOffset(0, typeParameters)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncParamList).
func CreateFuncParamList(builder: FlatBufferBuilder, params: FlatBufferOffset, desugars: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, desugars)
    builder.AddOffset(0, params)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncBody).
func CreateFuncBody(builder: FlatBufferBuilder, paramLists: FlatBufferOffset, retType: UInt32, body: UInt32,
    always: Bool, captureKind: UInt8): FlatBufferOffset {
    builder.StartTable(5)
    builder.AddU8(4, captureKind, defaultValue: 0u8)
    builder.AddBool(3, always, defaultValue: false)
    builder.AddU32(2, body, defaultValue: 0u32)
    builder.AddU32(1, retType, defaultValue: 0u32)
    builder.AddOffset(0, paramLists)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateArrayValue). val is [ConstValue].
func CreateArrayValue(builder: FlatBufferBuilder, valType: FlatBufferOffset, val: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, val)
    builder.AddOffset(0, valType)
    return builder.EndTable()
}

// ModuleFormat_generated.h:2605-2617 (CreateMemberValue). value is ConstValue union.
func CreateMemberValue(builder: FlatBufferBuilder, field: FlatBufferOffset, ty: UInt32, valueType: UInt8,
    value: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, value)
    builder.AddU32(1, ty, defaultValue: 0u32)
    builder.AddOffset(0, field)
    builder.AddU8(2, valueType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateCompositeValue).
func CreateCompositeValue(builder: FlatBufferBuilder, ty: UInt32, fields: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, fields)
    builder.AddU32(0, ty, defaultValue: 0u32)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateAutoDiffInfo).
func CreateAutoDiffInfo(builder: FlatBufferBuilder, isDiff: Bool, isAdj: Bool, primal: FlatBufferOffset,
    excepts: FlatBufferOffset, includes: FlatBufferOffset, stage: UInt64): FlatBufferOffset {
    builder.StartTable(6)
    builder.AddU64(5, stage, defaultValue: 0u64)
    builder.AddOffset(4, includes)
    builder.AddOffset(3, excepts)
    builder.AddOffset(2, primal)
    builder.AddBool(1, isAdj, defaultValue: false)
    builder.AddBool(0, isDiff, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateClassInfo).
func CreateClassInfo(builder: FlatBufferBuilder, inheritedTypes: FlatBufferOffset, body: FlatBufferOffset,
    adInfo: FlatBufferOffset, isAnno: Bool, annoTargets: UInt8, runtimeVisible: Bool, annoTargets2: UInt8): FlatBufferOffset {
    builder.StartTable(7)
    builder.AddU8(6, annoTargets2, defaultValue: 0u8)
    builder.AddBool(5, runtimeVisible, defaultValue: false)
    builder.AddU8(4, annoTargets, defaultValue: 0u8)
    builder.AddBool(3, isAnno, defaultValue: false)
    builder.AddOffset(2, adInfo)
    builder.AddOffset(1, body)
    builder.AddOffset(0, inheritedTypes)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateInterfaceInfo).
func CreateInterfaceInfo(builder: FlatBufferBuilder, inheritedTypes: FlatBufferOffset, body: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, body)
    builder.AddOffset(0, inheritedTypes)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateStructInfo).
func CreateStructInfo(builder: FlatBufferBuilder, inheritedTypes: FlatBufferOffset, body: FlatBufferOffset,
    adInfo: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddOffset(2, adInfo)
    builder.AddOffset(1, body)
    builder.AddOffset(0, inheritedTypes)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateEnumInfo).
func CreateEnumInfo(builder: FlatBufferBuilder, inheritedTypes: FlatBufferOffset, body: FlatBufferOffset,
    adInfo: FlatBufferOffset, hasArguments: Bool, nonExhaustive: Bool, ellipsisPos: ArrayList<UInt8>): FlatBufferOffset {
    builder.StartTable(6)
    builder.AddStruct(5, ellipsisPos, 4)
    builder.AddBool(4, nonExhaustive, defaultValue: false)
    builder.AddBool(3, hasArguments, defaultValue: false)
    builder.AddOffset(2, adInfo)
    builder.AddOffset(1, body)
    builder.AddOffset(0, inheritedTypes)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateExtendInfo).
func CreateExtendInfo(builder: FlatBufferBuilder, inheritedTypes: FlatBufferOffset, body: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, body)
    builder.AddOffset(0, inheritedTypes)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateVarInfo). value is ConstValue union.
func CreateVarInfo(builder: FlatBufferBuilder, isVar: Bool, isConst: Bool, isMemberParam: Bool, initializer: UInt32,
    valueType: UInt8, value: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(6)
    builder.AddOffset(5, value)
    builder.AddU32(3, initializer, defaultValue: 0u32)
    builder.AddBool(2, isMemberParam, defaultValue: false)
    builder.AddBool(1, isConst, defaultValue: false)
    builder.AddBool(0, isVar, defaultValue: false)
    builder.AddU8(4, valueType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateVarWithPatternInfo).
func CreateVarWithPatternInfo(builder: FlatBufferBuilder, isVar: Bool, isConst: Bool, irrefutablePattern: FlatBufferOffset,
    initializer: UInt32): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddU32(3, initializer, defaultValue: 0u32)
    builder.AddOffset(2, irrefutablePattern)
    builder.AddBool(1, isConst, defaultValue: false)
    builder.AddBool(0, isVar, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncInfo). op default OperatorKind.NA.
func CreateFuncInfo(builder: FlatBufferBuilder, funcBody: FlatBufferOffset, overflowPolicy: UInt8, op: UInt8,
    adInfo: FlatBufferOffset, isConst: Bool, isInline: Bool, isFastNative: Bool): FlatBufferOffset {
    builder.StartTable(7)
    builder.AddBool(6, isFastNative, defaultValue: false)
    builder.AddBool(5, isInline, defaultValue: false)
    builder.AddBool(4, isConst, defaultValue: false)
    builder.AddOffset(3, adInfo)
    builder.AddOffset(0, funcBody)
    builder.AddU8(1, overflowPolicy, defaultValue: 0u8)
    builder.AddU8(2, op, defaultValue: MF_OPERATOR_KIND_NA)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateParamInfo).
func CreateParamInfo(builder: FlatBufferBuilder, isNamedParam: Bool, isMemberParam: Bool, defaultVal: UInt32): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU32(2, defaultVal, defaultValue: 0u32)
    builder.AddBool(1, isMemberParam, defaultValue: false)
    builder.AddBool(0, isNamedParam, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreatePropInfo).
func CreatePropInfo(builder: FlatBufferBuilder, isConst: Bool, isMutable: Bool, setters: FlatBufferOffset,
    getters: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, getters)
    builder.AddOffset(2, setters)
    builder.AddBool(1, isMutable, defaultValue: false)
    builder.AddBool(0, isConst, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateBuiltInInfo).
func CreateBuiltInInfo(builder: FlatBufferBuilder, builtInType: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, builtInType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateAliasInfo).
func CreateAliasInfo(builder: FlatBufferBuilder, aliasedTy: UInt32): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU32(0, aliasedTy, defaultValue: 0u32)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateDecl). info is DeclInfo union.
func CreateDecl(builder: FlatBufferBuilder, kind: UInt16, isTopLevel: Bool, fullPkgName: FlatBufferOffset,
    genericDecl: FlatBufferOffset, generic: FlatBufferOffset, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
    identifier: FlatBufferOffset, identifierPos: ArrayList<UInt8>, attributes: FlatBufferOffset, annotations: FlatBufferOffset,
    ty: UInt32, mangledName: FlatBufferOffset, exportId: FlatBufferOffset, mangledBeforeSema: FlatBufferOffset,
    hash: ArrayList<UInt8>, infoType: UInt8, info: FlatBufferOffset, dependencies: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(19)
    builder.AddOffset(18, dependencies)
    builder.AddOffset(17, info)
    builder.AddStruct(15, hash, 8)
    builder.AddOffset(14, mangledBeforeSema)
    builder.AddOffset(13, exportId)
    builder.AddOffset(12, mangledName)
    builder.AddU32(11, ty, defaultValue: 0u32)
    builder.AddOffset(10, annotations)
    builder.AddOffset(9, attributes)
    builder.AddStruct(8, identifierPos, 4)
    builder.AddOffset(7, identifier)
    builder.AddStruct(6, end, 4)
    builder.AddStruct(5, begin, 4)
    builder.AddOffset(4, generic)
    builder.AddOffset(3, genericDecl)
    builder.AddOffset(2, fullPkgName)
    builder.AddU16(0, kind, defaultValue: 0u16)
    builder.AddBool(1, isTopLevel, defaultValue: false)
    builder.AddU8(16, infoType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateAnno).
func CreateAnno(builder: FlatBufferBuilder, kind: UInt16, identifier: FlatBufferOffset, args: FlatBufferOffset,
    target: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, target)
    builder.AddOffset(2, args)
    builder.AddOffset(1, identifier)
    builder.AddU16(0, kind, defaultValue: 0u16)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateAnnoArg).
func CreateAnnoArg(builder: FlatBufferBuilder, name: FlatBufferOffset, expr: UInt32): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddU32(1, expr, defaultValue: 0u32)
    builder.AddOffset(0, name)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateCallInfo). callKind default CallKind.NA.
func CreateCallInfo(builder: FlatBufferBuilder, hasSideEffect: Bool, callKind: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddBool(0, hasSideEffect, defaultValue: false)
    builder.AddU8(1, callKind, defaultValue: MF_CALL_KIND_NA)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateUnaryInfo).
func CreateUnaryInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateBinaryInfo).
func CreateBinaryInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateIncOrDecInfo).
func CreateIncOrDecInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateLitConstInfo).
func CreateLitConstInfo(builder: FlatBufferBuilder, strValue: FlatBufferOffset, constKind: UInt8, strKind: UInt8): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU8(2, strKind, defaultValue: 0u8)
    builder.AddU8(1, constKind, defaultValue: 0u8)
    builder.AddOffset(0, strValue)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateReferenceInfo).
func CreateReferenceInfo(builder: FlatBufferBuilder, reference: FlatBufferOffset, target: FlatBufferOffset,
    instTys: FlatBufferOffset, matchedParentTy: UInt32): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddU32(3, matchedParentTy, defaultValue: 0u32)
    builder.AddOffset(2, instTys)
    builder.AddOffset(1, target)
    builder.AddOffset(0, reference)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateLambdaInfo). funcBody is required.
func CreateLambdaInfo(builder: FlatBufferBuilder, funcBody: FlatBufferOffset, supportMock: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, funcBody)
    builder.AddBool(1, supportMock, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateAssignInfo).
func CreateAssignInfo(builder: FlatBufferBuilder, isCompound: Bool, op: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddU8(1, op, defaultValue: 0u8)
    builder.AddBool(0, isCompound, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateArrayInfo).
func CreateArrayInfo(builder: FlatBufferBuilder, initFunc: FlatBufferOffset, isValueArray: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, initFunc)
    builder.AddBool(1, isValueArray, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateJumpInfo).
func CreateJumpInfo(builder: FlatBufferBuilder, isBreak: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, isBreak, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncArgInfo).
func CreateFuncArgInfo(builder: FlatBufferBuilder, withInout: Bool, isDefaultVal: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddBool(1, isDefaultVal, defaultValue: false)
    builder.AddBool(0, withInout, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSubscriptInfo).
func CreateSubscriptInfo(builder: FlatBufferBuilder, isTupleAccess: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, isTupleAccess, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateMatchInfo).
func CreateMatchInfo(builder: FlatBufferBuilder, matchMode: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, matchMode, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateBlockInfo).
func CreateBlockInfo(builder: FlatBufferBuilder, isExpr: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, isExpr)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateTryInfo).
func CreateTryInfo(builder: FlatBufferBuilder, resources: FlatBufferOffset, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, patterns)
    builder.AddOffset(0, resources)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateLetPatternDestructorInfo).
func CreateLetPatternDestructorInfo(builder: FlatBufferBuilder, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, patterns)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateForInInfo). forInKind default ForInKind.NA.
func CreateForInInfo(builder: FlatBufferBuilder, pattern: FlatBufferOffset, forInKind: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, pattern)
    builder.AddU8(1, forInKind, defaultValue: MF_FOR_IN_KIND_NA)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateMatchCaseInfo).
func CreateMatchCaseInfo(builder: FlatBufferBuilder, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, patterns)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSpawnInfo).
func CreateSpawnInfo(builder: FlatBufferBuilder, future: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, future)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateExpr). info is ExprInfo union.
func CreateExpr(builder: FlatBufferBuilder, kind: UInt16, begin: ArrayList<UInt8>, end: ArrayList<UInt8>, mapExpr: UInt32,
    operands: FlatBufferOffset, ty: UInt32, overflowPolicy: UInt8, infoType: UInt8, info: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(9)
    builder.AddOffset(8, info)
    builder.AddU32(5, ty, defaultValue: 0u32)
    builder.AddOffset(4, operands)
    builder.AddU32(3, mapExpr, defaultValue: 0u32)
    builder.AddStruct(2, end, 4)
    builder.AddStruct(1, begin, 4)
    builder.AddU16(0, kind, defaultValue: 0u16)
    builder.AddU8(6, overflowPolicy, defaultValue: 0u8)
    builder.AddU8(7, infoType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreatePattern). values is [ConstValue], kind is int8.
func CreatePattern(builder: FlatBufferBuilder, kind: Int64, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
    patterns: FlatBufferOffset, types: FlatBufferOffset, exprs: FlatBufferOffset, valuesType: FlatBufferOffset,
    values: FlatBufferOffset, matchBeforeRuntime: Bool, needRuntimeTypeCheck: Bool): FlatBufferOffset {
    builder.StartTable(10)
    builder.AddOffset(7, values)
    builder.AddOffset(6, valuesType)
    builder.AddOffset(5, exprs)
    builder.AddOffset(4, types)
    builder.AddOffset(3, patterns)
    builder.AddStruct(2, end, 4)
    builder.AddStruct(1, begin, 4)
    builder.AddBool(9, needRuntimeTypeCheck, defaultValue: false)
    builder.AddBool(8, matchBeforeRuntime, defaultValue: false)
    builder.AddI8(0, kind, defaultValue: 0)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncTyInfo).
func CreateFuncTyInfo(builder: FlatBufferBuilder, retType: UInt32, isC: Bool, hasVariableLenArg: Bool): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU32(0, retType, defaultValue: 0u32)
    builder.AddBool(2, hasVariableLenArg, defaultValue: false)
    builder.AddBool(1, isC, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateCompositeTyInfo).
func CreateCompositeTyInfo(builder: FlatBufferBuilder, declPtr: FlatBufferOffset, isThisTy: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, declPtr)
    builder.AddBool(1, isThisTy, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateGenericTyInfo).
func CreateGenericTyInfo(builder: FlatBufferBuilder, declPtr: FlatBufferOffset, upperBounds: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, upperBounds)
    builder.AddOffset(0, declPtr)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateArrayTyInfo).
func CreateArrayTyInfo(builder: FlatBufferBuilder, dimsOrSize: Int64): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddI64(0, dimsOrSize, defaultValue: 0)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSemaTy). kind default TypeKind.Unit(1). info is SemaTyInfo union.
func CreateSemaTy(builder: FlatBufferBuilder, kind: UInt16, typeArgs: FlatBufferOffset, infoType: UInt8,
    info: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, info)
    builder.AddOffset(1, typeArgs)
    builder.AddU16(0, kind, defaultValue: MF_TYPE_KIND_UNIT)
    builder.AddU8(2, infoType, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateImportSpec). reExport default AccessModifier.Private;
// withImplicitExport default true.
func CreateImportSpec(builder: FlatBufferBuilder, begin: ArrayList<UInt8>, end: ArrayList<UInt8>, prefixPaths: FlatBufferOffset,
    identifier: FlatBufferOffset, asIdentifier: FlatBufferOffset, reExport: UInt8, isDecl: Bool, hasDoubleColon: Bool,
    withImplicitExport: Bool): FlatBufferOffset {
    builder.StartTable(9)
    builder.AddOffset(4, asIdentifier)
    builder.AddOffset(3, identifier)
    builder.AddOffset(2, prefixPaths)
    builder.AddStruct(1, end, 4)
    builder.AddStruct(0, begin, 4)
    builder.AddBool(8, withImplicitExport, defaultValue: true)
    builder.AddBool(7, hasDoubleColon, defaultValue: false)
    builder.AddBool(6, isDecl, defaultValue: false)
    builder.AddU8(5, reExport, defaultValue: MF_ACCESS_MODIFIER_PRIVATE)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateImports).
func CreateImports(builder: FlatBufferBuilder, importSpecs: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, importSpecs)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFeatureId).
func CreateFeatureId(builder: FlatBufferBuilder, identifiers: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, identifiers)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFeaturesSet).
func CreateFeaturesSet(builder: FlatBufferBuilder, features: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, features)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFeaturesDirective).
func CreateFeaturesDirective(builder: FlatBufferBuilder, featuresSet: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, featuresSet)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFileInfo).
func CreateFileInfo(builder: FlatBufferBuilder, fileID: UInt32, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
    feature: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, feature)
    builder.AddStruct(2, end, 4)
    builder.AddStruct(1, begin, 4)
    builder.AddU32(0, fileID, defaultValue: 0u32)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateCompilationOptions).
func CreateCompilationOptions(builder: FlatBufferBuilder, optimizationLevel: UInt8, debug: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddBool(1, debug, defaultValue: false)
    builder.AddU8(0, optimizationLevel, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreatePackage). kind default PackageKind.Normal;
// access default AccessLevel.Public.
func CreatePackage(builder: FlatBufferBuilder, version: FlatBufferOffset, cjoVersion: ArrayList<UInt8>,
    fullPkgName: FlatBufferOffset, pkgDepInfo: FlatBufferOffset, imports: FlatBufferOffset, allFiles: FlatBufferOffset,
    allFileImports: FlatBufferOffset, allTypes: FlatBufferOffset, allDecls: FlatBufferOffset, allExprs: FlatBufferOffset,
    allValues: FlatBufferOffset, kind: UInt8, access: UInt8, moduleName: FlatBufferOffset, allFileInfo: FlatBufferOffset,
    allDependentStdPkgs: FlatBufferOffset, options: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(17)
    builder.AddOffset(16, options)
    builder.AddOffset(15, allDependentStdPkgs)
    builder.AddOffset(14, allFileInfo)
    builder.AddOffset(13, moduleName)
    builder.AddOffset(10, allValues)
    builder.AddOffset(9, allExprs)
    builder.AddOffset(8, allDecls)
    builder.AddOffset(7, allTypes)
    builder.AddOffset(6, allFileImports)
    builder.AddOffset(5, allFiles)
    builder.AddOffset(4, imports)
    builder.AddOffset(3, pkgDepInfo)
    builder.AddOffset(2, fullPkgName)
    builder.AddStruct(1, cjoVersion, 1)
    builder.AddOffset(0, version)
    builder.AddU8(11, kind, defaultValue: MF_PACKAGE_KIND_NORMAL)
    builder.AddU8(12, access, defaultValue: MF_ACCESS_LEVEL_PUBLIC)
    return builder.EndTable()
}

// Finish the buffer with the "CJOF" file identifier. ModuleFormat_generated.h:6706-6715
// (FinishPackageBuffer). Returns the serialized byte image.
func FinishPackageBuffer(builder: FlatBufferBuilder, root: FlatBufferOffset): Array<UInt8> {
    return builder.Finish(root, MF_FILE_IDENTIFIER)
}

// ConstValue union struct-member writers: a struct member is stored by offset,
// so the struct is written standalone and its offset used as the union value.
// ModuleFormat_generated.h:1767-1952 struct sizes/aligns.
func CreateConstValueInt8(builder: FlatBufferBuilder, val: Int8): FlatBufferOffset {
    return builder.CreateStructBytes(PackInt8Value(val), 1)
}
func CreateConstValueUInt8(builder: FlatBufferBuilder, val: UInt8): FlatBufferOffset {
    return builder.CreateStructBytes(PackUInt8Value(val), 1)
}
func CreateConstValueInt16(builder: FlatBufferBuilder, val: Int16): FlatBufferOffset {
    return builder.CreateStructBytes(PackInt16Value(val), 2)
}
func CreateConstValueUInt16(builder: FlatBufferBuilder, val: UInt16): FlatBufferOffset {
    return builder.CreateStructBytes(PackUInt16Value(val), 2)
}
func CreateConstValueInt32(builder: FlatBufferBuilder, val: Int32): FlatBufferOffset {
    return builder.CreateStructBytes(PackInt32Value(val), 4)
}
func CreateConstValueUInt32(builder: FlatBufferBuilder, val: UInt32): FlatBufferOffset {
    return builder.CreateStructBytes(PackUInt32Value(val), 4)
}
func CreateConstValueInt64(builder: FlatBufferBuilder, val: Int64): FlatBufferOffset {
    return builder.CreateStructBytes(PackInt64Value(val), 8)
}
func CreateConstValueUInt64(builder: FlatBufferBuilder, val: UInt64): FlatBufferOffset {
    return builder.CreateStructBytes(PackUInt64Value(val), 8)
}
func CreateConstValueFloat32(builder: FlatBufferBuilder, val: Float32): FlatBufferOffset {
    return builder.CreateStructBytes(PackFloat32Value(val), 4)
}
func CreateConstValueFloat64(builder: FlatBufferBuilder, val: Float64): FlatBufferOffset {
    return builder.CreateStructBytes(PackFloat64Value(val), 8)
}
func CreateConstValueCompositeIndex(builder: FlatBufferBuilder, idx: UInt32): FlatBufferOffset {
    return builder.CreateStructBytes(PackCompositeValueIndex(idx), 4)
}
