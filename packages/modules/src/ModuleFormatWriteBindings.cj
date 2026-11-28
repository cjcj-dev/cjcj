package cjcj::modules

import std.collection.ArrayList
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

// FlatBuffers write bindings used by ModuleFormat.fbs producers and tests.
// Each CreateX mirrors the generated CreateX: it opens a table with the exact
// field count, slots each field at its generated field index ((VT-4)/2), and
// applies the schema default so unset fields are elided. Struct fields take the
// packed byte image from ModuleFormatStructs.cj; offset fields (tables, strings,
// vectors, union values) take a prebuilt FlatBufferOffset (0 = absent). Field
// add order is not observable to readers; alignment is handled per element by
// the builder. FlatBufferBuilder uses 0-based field indexes (Slot).

// ModuleFormat_generated.h:2124-2138 (CreateFullId).
public func CreateFullId(builder: FlatBufferBuilder, pkgId: Int64, decl: FlatBufferOffset, index: UInt32): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU32(2, index, defaultValue: 0u32)
    builder.AddOffset(1, decl)
    builder.AddI32(0, pkgId, defaultValue: 0)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateParamInfo).
public func CreateParamInfo(builder: FlatBufferBuilder, isNamedParam: Bool, isMemberParam: Bool, defaultVal: UInt32): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU32(2, defaultVal, defaultValue: 0u32)
    builder.AddBool(1, isMemberParam, defaultValue: false)
    builder.AddBool(0, isNamedParam, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateDecl). info is DeclInfo union.
public func CreateDecl(builder: FlatBufferBuilder, kind: UInt16, isTopLevel: Bool, fullPkgName: FlatBufferOffset,
    genericDecl: FlatBufferOffset, generic: FlatBufferOffset, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
    identifier: FlatBufferOffset, identifierPos: ArrayList<UInt8>, attributes: FlatBufferOffset, annotations: FlatBufferOffset,
    ty: UInt32, mangledName: FlatBufferOffset, exportId: FlatBufferOffset, mangledBeforeSema: FlatBufferOffset,
    hash: ArrayList<UInt8>, infoType: UInt8, info: FlatBufferOffset, dependencies: FlatBufferOffset,
    tyMode!: FlatBufferOffset = 0u32): FlatBufferOffset {
    builder.StartTable(20)
    builder.AddOffset(19, tyMode)
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

// ModuleFormat_generated.h (CreateCallInfo). callKind default CallKind.NA.
public func CreateCallInfo(builder: FlatBufferBuilder, hasSideEffect: Bool, callKind: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddBool(0, hasSideEffect, defaultValue: false)
    builder.AddU8(1, callKind, defaultValue: MF_CALL_KIND_NA)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateUnaryInfo).
public func CreateUnaryInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateBinaryInfo).
public func CreateBinaryInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateIncOrDecInfo).
public func CreateIncOrDecInfo(builder: FlatBufferBuilder, op: UInt8): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddU8(0, op, defaultValue: 0u8)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateLitConstInfo).
public func CreateLitConstInfo(builder: FlatBufferBuilder, strValue: FlatBufferOffset, constKind: UInt8, strKind: UInt8): FlatBufferOffset {
    builder.StartTable(3)
    builder.AddU8(2, strKind, defaultValue: 0u8)
    builder.AddU8(1, constKind, defaultValue: 0u8)
    builder.AddOffset(0, strValue)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateReferenceInfo).
public func CreateReferenceInfo(builder: FlatBufferBuilder, reference: FlatBufferOffset, target: FlatBufferOffset,
    instTys: FlatBufferOffset, matchedParentTy: UInt32): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddU32(3, matchedParentTy, defaultValue: 0u32)
    builder.AddOffset(2, instTys)
    builder.AddOffset(1, target)
    builder.AddOffset(0, reference)
    return builder.EndTable()
}

// ModuleFormat_generated.h:4739-4759 (CreateLambdaInfo). funcBody is required;
// CreateLambdaInfo ends with fbb_.Required(o, LambdaInfo::VT_FUNCBODY).
public func CreateLambdaInfo(builder: FlatBufferBuilder, funcBody: FlatBufferOffset, supportMock: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, funcBody)
    builder.AddBool(1, supportMock, defaultValue: false)
    let o = builder.EndTable()
    builder.Required(o, MF_LAMBDA_INFO_VT_FUNCBODY)
    return o
}

// ModuleFormat_generated.h (CreateAssignInfo).
public func CreateAssignInfo(builder: FlatBufferBuilder, isCompound: Bool, op: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddU8(1, op, defaultValue: 0u8)
    builder.AddBool(0, isCompound, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateArrayInfo).
public func CreateArrayInfo(builder: FlatBufferBuilder, initFunc: FlatBufferOffset, isValueArray: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, initFunc)
    builder.AddBool(1, isValueArray, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateJumpInfo).
public func CreateJumpInfo(builder: FlatBufferBuilder, isBreak: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, isBreak, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFuncArgInfo).
public func CreateFuncArgInfo(builder: FlatBufferBuilder, withInout: Bool, isDefaultVal: Bool): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddBool(1, isDefaultVal, defaultValue: false)
    builder.AddBool(0, withInout, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSubscriptInfo).
public func CreateSubscriptInfo(builder: FlatBufferBuilder, isTupleAccess: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, isTupleAccess, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateMatchInfo).
public func CreateMatchInfo(builder: FlatBufferBuilder, matchMode: Bool): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddBool(0, matchMode, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateBlockInfo).
public func CreateBlockInfo(builder: FlatBufferBuilder, isExpr: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, isExpr)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateTryInfo).
public func CreateTryInfo(builder: FlatBufferBuilder, resources: FlatBufferOffset, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(1, patterns)
    builder.AddOffset(0, resources)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateLetPatternDestructorInfo).
public func CreateLetPatternDestructorInfo(builder: FlatBufferBuilder, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, patterns)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateForInInfo). forInKind default ForInKind.NA.
public func CreateForInInfo(builder: FlatBufferBuilder, pattern: FlatBufferOffset, forInKind: UInt8): FlatBufferOffset {
    builder.StartTable(2)
    builder.AddOffset(0, pattern)
    builder.AddU8(1, forInKind, defaultValue: MF_FOR_IN_KIND_NA)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateMatchCaseInfo).
public func CreateMatchCaseInfo(builder: FlatBufferBuilder, patterns: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, patterns)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSpawnInfo).
public func CreateSpawnInfo(builder: FlatBufferBuilder, future: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, future)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateExpr). info is ExprInfo union.
public func CreateExpr(builder: FlatBufferBuilder, kind: UInt16, begin: ArrayList<UInt8>, end: ArrayList<UInt8>, mapExpr: UInt32,
    operands: FlatBufferOffset, ty: UInt32, overflowPolicy: UInt8, infoType: UInt8, info: FlatBufferOffset,
    tyMode!: FlatBufferOffset = 0u32): FlatBufferOffset {
    builder.StartTable(10)
    builder.AddOffset(9, tyMode)
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
public func CreatePattern(builder: FlatBufferBuilder, kind: Int64, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
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
public func CreateFuncTyInfo(builder: FlatBufferBuilder, retType: UInt32, isC: Bool, hasVariableLenArg: Bool,
    paramModes!: FlatBufferOffset = 0u32, retMode!: FlatBufferOffset = 0u32): FlatBufferOffset {
    builder.StartTable(5)
    builder.AddOffset(4, retMode)
    builder.AddOffset(3, paramModes)
    builder.AddU32(0, retType, defaultValue: 0u32)
    builder.AddBool(2, hasVariableLenArg, defaultValue: false)
    builder.AddBool(1, isC, defaultValue: false)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateSemaTy). kind default TypeKind.Unit(1). info is SemaTyInfo union.
public func CreateSemaTy(builder: FlatBufferBuilder, kind: UInt16, typeArgs: FlatBufferOffset, infoType: UInt8,
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
    withImplicitExport: Bool, isImplicitAdd: Bool): FlatBufferOffset {
    builder.StartTable(10)
    builder.AddBool(9, isImplicitAdd, defaultValue: false)
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

// ModuleFormat_generated.h (CreateFeatureId).
public func CreateFeatureId(builder: FlatBufferBuilder, identifiers: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, identifiers)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFeaturesSet).
public func CreateFeaturesSet(builder: FlatBufferBuilder, features: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, features)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFeaturesDirective).
public func CreateFeaturesDirective(builder: FlatBufferBuilder, featuresSet: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(1)
    builder.AddOffset(0, featuresSet)
    return builder.EndTable()
}

// ModuleFormat_generated.h (CreateFileInfo).
public func CreateFileInfo(builder: FlatBufferBuilder, fileID: UInt32, begin: ArrayList<UInt8>, end: ArrayList<UInt8>,
    feature: FlatBufferOffset): FlatBufferOffset {
    builder.StartTable(4)
    builder.AddOffset(3, feature)
    builder.AddStruct(2, end, 4)
    builder.AddStruct(1, begin, 4)
    builder.AddU32(0, fileID, defaultValue: 0u32)
    return builder.EndTable()
}

// Finish the buffer with the "CJOF" file identifier. ModuleFormat_generated.h:6706-6715
// (FinishPackageBuffer). Returns the serialized byte image.
// ConstValue union struct-member writers: a struct member is stored by offset,
// so the struct is written standalone and its offset used as the union value.
