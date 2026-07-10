package cjcj::chir

import std.collection.*
import cjcj::modules.{FlatBufferBuilder, FlatBufferOffset}

class ValueBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(4)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_type(`type`: UInt32): Unit {
        builder.AddU32(1, `type`, defaultValue: 0u32)
    }

    public func add_identifier(identifier: FlatBufferOffset): Unit {
        builder.AddOffset(2, identifier)
    }

    public func add_kind(kind: UInt8): Unit {
        builder.AddU8(3, kind, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateValue(builder: FlatBufferBuilder, base: FlatBufferOffset, `type`: UInt32, identifier: FlatBufferOffset, kind: UInt8): FlatBufferOffset {
    let tableBuilder = ValueBuilder(builder)
    tableBuilder.add_identifier(identifier)
    tableBuilder.add_type(`type`)
    tableBuilder.add_base(base)
    tableBuilder.add_kind(kind)
    return tableBuilder.Finish()
}

func CreateValueDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, `type`: UInt32, identifier: Option<String>, kind: UInt8): FlatBufferOffset {
    let identifierOffset = if (let Some(value) <- identifier) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateValue(builder, base, `type`, identifierOffset, kind)
}

class LiteralValueBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_literalKind(literalKind: UInt8): Unit {
        builder.AddU8(1, literalKind, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateLiteralValue(builder: FlatBufferBuilder, base: FlatBufferOffset, literalKind: UInt8): FlatBufferOffset {
    let tableBuilder = LiteralValueBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_literalKind(literalKind)
    return tableBuilder.Finish()
}

class BoolLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_val(val: Bool): Unit {
        builder.AddBool(1, val, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBoolLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset, val: Bool): FlatBufferOffset {
    let tableBuilder = BoolLiteralBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_val(val)
    return tableBuilder.Finish()
}

class StringLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_val(val: FlatBufferOffset): Unit {
        builder.AddOffset(1, val)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateStringLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset, val: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = StringLiteralBuilder(builder)
    tableBuilder.add_val(val)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateStringLiteralDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, val: Option<String>): FlatBufferOffset {
    let valOffset = if (let Some(value) <- val) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateStringLiteral(builder, base, valOffset)
}

class RuneLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_val(val: UInt32): Unit {
        builder.AddU32(1, val, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateRuneLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset, val: UInt32): FlatBufferOffset {
    let tableBuilder = RuneLiteralBuilder(builder)
    tableBuilder.add_val(val)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class IntLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_val(val: UInt64): Unit {
        builder.AddU64(1, val, defaultValue: 0u64)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateIntLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset, val: UInt64): FlatBufferOffset {
    let tableBuilder = IntLiteralBuilder(builder)
    tableBuilder.add_val(val)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class FloatLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_val(val: Float64): Unit {
        builder.AddFloat64(1, val, defaultValue: 1.0)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFloatLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset, val: Float64): FlatBufferOffset {
    let tableBuilder = FloatLiteralBuilder(builder)
    tableBuilder.add_val(val)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class UnitLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateUnitLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = UnitLiteralBuilder(builder)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class NullLiteralBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateNullLiteral(builder: FlatBufferBuilder, base: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = NullLiteralBuilder(builder)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class ParameterBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(5)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_ownedFunc(ownedFunc: UInt32): Unit {
        builder.AddU32(1, ownedFunc, defaultValue: 0u32)
    }

    public func add_ownedLambda(ownedLambda: UInt32): Unit {
        builder.AddU32(2, ownedLambda, defaultValue: 0u32)
    }

    public func add_srcCodeIdentifier(srcCodeIdentifier: FlatBufferOffset): Unit {
        builder.AddOffset(3, srcCodeIdentifier)
    }

    public func add_annoInfo(annoInfo: FlatBufferOffset): Unit {
        builder.AddOffset(4, annoInfo)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateParameter(builder: FlatBufferBuilder, base: FlatBufferOffset, ownedFunc: UInt32, ownedLambda: UInt32, srcCodeIdentifier: FlatBufferOffset, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = ParameterBuilder(builder)
    tableBuilder.add_annoInfo(annoInfo)
    tableBuilder.add_srcCodeIdentifier(srcCodeIdentifier)
    tableBuilder.add_ownedLambda(ownedLambda)
    tableBuilder.add_ownedFunc(ownedFunc)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateParameterDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, ownedFunc: UInt32, ownedLambda: UInt32, srcCodeIdentifier: Option<String>, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let srcCodeIdentifierOffset = if (let Some(value) <- srcCodeIdentifier) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateParameter(builder, base, ownedFunc, ownedLambda, srcCodeIdentifierOffset, annoInfo)
}

class LocalVarBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(4)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_associatedExpr(associatedExpr: UInt32): Unit {
        builder.AddU32(1, associatedExpr, defaultValue: 0u32)
    }

    public func add_isRetVal(isRetVal: Bool): Unit {
        builder.AddBool(2, isRetVal, defaultValue: false)
    }

    public func add_srcCodeIdentifier(srcCodeIdentifier: FlatBufferOffset): Unit {
        builder.AddOffset(3, srcCodeIdentifier)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateLocalVar(builder: FlatBufferBuilder, base: FlatBufferOffset, associatedExpr: UInt32, isRetVal: Bool, srcCodeIdentifier: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = LocalVarBuilder(builder)
    tableBuilder.add_srcCodeIdentifier(srcCodeIdentifier)
    tableBuilder.add_associatedExpr(associatedExpr)
    tableBuilder.add_base(base)
    tableBuilder.add_isRetVal(isRetVal)
    return tableBuilder.Finish()
}

func CreateLocalVarDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, associatedExpr: UInt32, isRetVal: Bool, srcCodeIdentifier: Option<String>): FlatBufferOffset {
    let srcCodeIdentifierOffset = if (let Some(value) <- srcCodeIdentifier) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateLocalVar(builder, base, associatedExpr, isRetVal, srcCodeIdentifierOffset)
}

class GlobalValueBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(7)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_srcCodeIdentifier(srcCodeIdentifier: FlatBufferOffset): Unit {
        builder.AddOffset(1, srcCodeIdentifier)
    }

    public func add_rawMangledName(rawMangledName: FlatBufferOffset): Unit {
        builder.AddOffset(2, rawMangledName)
    }

    public func add_packageName(packageName: FlatBufferOffset): Unit {
        builder.AddOffset(3, packageName)
    }

    public func add_declaredParent(declaredParent: UInt32): Unit {
        builder.AddU32(4, declaredParent, defaultValue: 0u32)
    }

    public func add_features(features: FlatBufferOffset): Unit {
        builder.AddOffset(5, features)
    }

    public func add_annoInfo(annoInfo: FlatBufferOffset): Unit {
        builder.AddOffset(6, annoInfo)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGlobalValue(builder: FlatBufferBuilder, base: FlatBufferOffset, srcCodeIdentifier: FlatBufferOffset, rawMangledName: FlatBufferOffset, packageName: FlatBufferOffset, declaredParent: UInt32, features: FlatBufferOffset, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = GlobalValueBuilder(builder)
    tableBuilder.add_annoInfo(annoInfo)
    tableBuilder.add_features(features)
    tableBuilder.add_declaredParent(declaredParent)
    tableBuilder.add_packageName(packageName)
    tableBuilder.add_rawMangledName(rawMangledName)
    tableBuilder.add_srcCodeIdentifier(srcCodeIdentifier)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateGlobalValueDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, srcCodeIdentifier: Option<String>, rawMangledName: Option<String>, packageName: Option<String>, declaredParent: UInt32, features: Option<ArrayList<FlatBufferOffset>>, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let srcCodeIdentifierOffset = if (let Some(value) <- srcCodeIdentifier) { builder.CreateSharedString(value) } else { 0u32 }
    let rawMangledNameOffset = if (let Some(value) <- rawMangledName) { builder.CreateSharedString(value) } else { 0u32 }
    let packageNameOffset = if (let Some(value) <- packageName) { builder.CreateSharedString(value) } else { 0u32 }
    let featuresOffset = if (let Some(value) <- features) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateGlobalValue(builder, base, srcCodeIdentifierOffset, rawMangledNameOffset, packageNameOffset, declaredParent, featuresOffset, annoInfo)
}

class GlobalVarBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_initializer(initializer: UInt32): Unit {
        builder.AddU32(1, initializer, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGlobalVar(builder: FlatBufferBuilder, base: FlatBufferOffset, initializer: UInt32): FlatBufferOffset {
    let tableBuilder = GlobalVarBuilder(builder)
    tableBuilder.add_initializer(initializer)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class FuncSigInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_funcName(funcName: FlatBufferOffset): Unit {
        builder.AddOffset(0, funcName)
    }

    public func add_funcType(funcType: UInt32): Unit {
        builder.AddU32(1, funcType, defaultValue: 0u32)
    }

    public func add_genericTypeParams(genericTypeParams: FlatBufferOffset): Unit {
        builder.AddOffset(2, genericTypeParams)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFuncSigInfo(builder: FlatBufferBuilder, funcName: FlatBufferOffset, funcType: UInt32, genericTypeParams: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = FuncSigInfoBuilder(builder)
    tableBuilder.add_genericTypeParams(genericTypeParams)
    tableBuilder.add_funcType(funcType)
    tableBuilder.add_funcName(funcName)
    return tableBuilder.Finish()
}

func CreateFuncSigInfoDirect(builder: FlatBufferBuilder, funcName: Option<String>, funcType: UInt32, genericTypeParams: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let funcNameOffset = if (let Some(value) <- funcName) { builder.CreateSharedString(value) } else { 0u32 }
    let genericTypeParamsOffset = if (let Some(value) <- genericTypeParams) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateFuncSigInfo(builder, funcNameOffset, funcType, genericTypeParamsOffset)
}

class FunctionBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(15)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_genericDecl(genericDecl: UInt32): Unit {
        builder.AddU32(1, genericDecl, defaultValue: 0u32)
    }

    public func add_funcKind(funcKind: UInt8): Unit {
        builder.AddU8(2, funcKind, defaultValue: 0u8)
    }

    public func add_isFastNative(isFastNative: Bool): Unit {
        builder.AddBool(3, isFastNative, defaultValue: false)
    }

    public func add_isCFFIWrapper(isCFFIWrapper: Bool): Unit {
        builder.AddBool(4, isCFFIWrapper, defaultValue: false)
    }

    public func add_originalLambdaInfo(originalLambdaInfo: FlatBufferOffset): Unit {
        builder.AddOffset(5, originalLambdaInfo)
    }

    public func add_genericTypeParams(genericTypeParams: FlatBufferOffset): Unit {
        builder.AddOffset(6, genericTypeParams)
    }

    public func add_paramDftValHostFunc(paramDftValHostFunc: UInt32): Unit {
        builder.AddU32(7, paramDftValHostFunc, defaultValue: 0u32)
    }

    public func add_body(body: UInt32): Unit {
        builder.AddU32(8, body, defaultValue: 0u32)
    }

    public func add_params(params: FlatBufferOffset): Unit {
        builder.AddOffset(9, params)
    }

    public func add_retVal(retVal: UInt32): Unit {
        builder.AddU32(10, retVal, defaultValue: 0u32)
    }

    public func add_propLoc(propLoc: FlatBufferOffset): Unit {
        builder.AddOffset(11, propLoc)
    }

    public func add_localId(localId: UInt64): Unit {
        builder.AddU64(12, localId, defaultValue: 0u64)
    }

    public func add_blockId(blockId: UInt64): Unit {
        builder.AddU64(13, blockId, defaultValue: 0u64)
    }

    public func add_blockGroupId(blockGroupId: UInt64): Unit {
        builder.AddU64(14, blockGroupId, defaultValue: 0u64)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFunction(builder: FlatBufferBuilder, base: FlatBufferOffset, genericDecl: UInt32, funcKind: UInt8, isFastNative: Bool, isCFFIWrapper: Bool, originalLambdaInfo: FlatBufferOffset, genericTypeParams: FlatBufferOffset, paramDftValHostFunc: UInt32, body: UInt32, params: FlatBufferOffset, retVal: UInt32, propLoc: FlatBufferOffset, localId: UInt64, blockId: UInt64, blockGroupId: UInt64): FlatBufferOffset {
    let tableBuilder = FunctionBuilder(builder)
    tableBuilder.add_blockGroupId(blockGroupId)
    tableBuilder.add_blockId(blockId)
    tableBuilder.add_localId(localId)
    tableBuilder.add_propLoc(propLoc)
    tableBuilder.add_retVal(retVal)
    tableBuilder.add_params(params)
    tableBuilder.add_body(body)
    tableBuilder.add_paramDftValHostFunc(paramDftValHostFunc)
    tableBuilder.add_genericTypeParams(genericTypeParams)
    tableBuilder.add_originalLambdaInfo(originalLambdaInfo)
    tableBuilder.add_genericDecl(genericDecl)
    tableBuilder.add_base(base)
    tableBuilder.add_isCFFIWrapper(isCFFIWrapper)
    tableBuilder.add_isFastNative(isFastNative)
    tableBuilder.add_funcKind(funcKind)
    return tableBuilder.Finish()
}

func CreateFunctionDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, genericDecl: UInt32, funcKind: UInt8, isFastNative: Bool, isCFFIWrapper: Bool, originalLambdaInfo: FlatBufferOffset, genericTypeParams: Option<ArrayList<UInt32>>, paramDftValHostFunc: UInt32, body: UInt32, params: Option<ArrayList<UInt32>>, retVal: UInt32, propLoc: FlatBufferOffset, localId: UInt64, blockId: UInt64, blockGroupId: UInt64): FlatBufferOffset {
    let genericTypeParamsOffset = if (let Some(value) <- genericTypeParams) { builder.CreateVectorU32(value) } else { 0u32 }
    let paramsOffset = if (let Some(value) <- params) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateFunction(builder, base, genericDecl, funcKind, isFastNative, isCFFIWrapper, originalLambdaInfo, genericTypeParamsOffset, paramDftValHostFunc, body, paramsOffset, retVal, propLoc, localId, blockId, blockGroupId)
}

class BlockBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(6)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_parentGroup(parentGroup: UInt32): Unit {
        builder.AddU32(1, parentGroup, defaultValue: 0u32)
    }

    public func add_exprs(exprs: FlatBufferOffset): Unit {
        builder.AddOffset(2, exprs)
    }

    public func add_predecessors(predecessors: FlatBufferOffset): Unit {
        builder.AddOffset(3, predecessors)
    }

    public func add_isLandingPadBlock(isLandingPadBlock: Bool): Unit {
        builder.AddBool(4, isLandingPadBlock, defaultValue: false)
    }

    public func add_exceptionCatchList(exceptionCatchList: FlatBufferOffset): Unit {
        builder.AddOffset(5, exceptionCatchList)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBlock(builder: FlatBufferBuilder, base: FlatBufferOffset, parentGroup: UInt32, exprs: FlatBufferOffset, predecessors: FlatBufferOffset, isLandingPadBlock: Bool, exceptionCatchList: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = BlockBuilder(builder)
    tableBuilder.add_exceptionCatchList(exceptionCatchList)
    tableBuilder.add_predecessors(predecessors)
    tableBuilder.add_exprs(exprs)
    tableBuilder.add_parentGroup(parentGroup)
    tableBuilder.add_base(base)
    tableBuilder.add_isLandingPadBlock(isLandingPadBlock)
    return tableBuilder.Finish()
}

func CreateBlockDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, parentGroup: UInt32, exprs: Option<ArrayList<UInt32>>, predecessors: Option<ArrayList<UInt32>>, isLandingPadBlock: Bool, exceptionCatchList: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let exprsOffset = if (let Some(value) <- exprs) { builder.CreateVectorU32(value) } else { 0u32 }
    let predecessorsOffset = if (let Some(value) <- predecessors) { builder.CreateVectorU32(value) } else { 0u32 }
    let exceptionCatchListOffset = if (let Some(value) <- exceptionCatchList) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateBlock(builder, base, parentGroup, exprsOffset, predecessorsOffset, isLandingPadBlock, exceptionCatchListOffset)
}

class BlockGroupBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(5)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_entryBlock(entryBlock: UInt32): Unit {
        builder.AddU32(1, entryBlock, defaultValue: 0u32)
    }

    public func add_blocks(blocks: FlatBufferOffset): Unit {
        builder.AddOffset(2, blocks)
    }

    public func add_ownedFunc(ownedFunc: UInt32): Unit {
        builder.AddU32(3, ownedFunc, defaultValue: 0u32)
    }

    public func add_ownedExpression(ownedExpression: UInt32): Unit {
        builder.AddU32(4, ownedExpression, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBlockGroup(builder: FlatBufferBuilder, base: FlatBufferOffset, entryBlock: UInt32, blocks: FlatBufferOffset, ownedFunc: UInt32, ownedExpression: UInt32): FlatBufferOffset {
    let tableBuilder = BlockGroupBuilder(builder)
    tableBuilder.add_ownedExpression(ownedExpression)
    tableBuilder.add_ownedFunc(ownedFunc)
    tableBuilder.add_blocks(blocks)
    tableBuilder.add_entryBlock(entryBlock)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateBlockGroupDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, entryBlock: UInt32, blocks: Option<ArrayList<UInt32>>, ownedFunc: UInt32, ownedExpression: UInt32): FlatBufferOffset {
    let blocksOffset = if (let Some(value) <- blocks) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateBlockGroup(builder, base, entryBlock, blocksOffset, ownedFunc, ownedExpression)
}
