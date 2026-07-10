package cjcj::chir

import std.collection.*
import cjcj::modules.{FlatBufferBuilder, FlatBufferOffset}

class ExpressionBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(7)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_kind(kind: UInt8): Unit {
        builder.AddU8(1, kind, defaultValue: 0u8)
    }

    public func add_operands(operands: FlatBufferOffset): Unit {
        builder.AddOffset(2, operands)
    }

    public func add_blockGroups(blockGroups: FlatBufferOffset): Unit {
        builder.AddOffset(3, blockGroups)
    }

    public func add_owner(owner: UInt32): Unit {
        builder.AddU32(4, owner, defaultValue: 0u32)
    }

    public func add_resultLocalVar(resultLocalVar: UInt32): Unit {
        builder.AddU32(5, resultLocalVar, defaultValue: 0u32)
    }

    public func add_resultTy(resultTy: UInt32): Unit {
        builder.AddU32(6, resultTy, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateExpression(builder: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt8, operands: FlatBufferOffset, blockGroups: FlatBufferOffset, owner: UInt32, resultLocalVar: UInt32, resultTy: UInt32): FlatBufferOffset {
    let tableBuilder = ExpressionBuilder(builder)
    tableBuilder.add_resultTy(resultTy)
    tableBuilder.add_resultLocalVar(resultLocalVar)
    tableBuilder.add_owner(owner)
    tableBuilder.add_blockGroups(blockGroups)
    tableBuilder.add_operands(operands)
    tableBuilder.add_base(base)
    tableBuilder.add_kind(kind)
    return tableBuilder.Finish()
}

func CreateExpressionDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt8, operands: Option<ArrayList<UInt32>>, blockGroups: Option<ArrayList<UInt32>>, owner: UInt32, resultLocalVar: UInt32, resultTy: UInt32): FlatBufferOffset {
    let operandsOffset = if (let Some(value) <- operands) { builder.CreateVectorU32(value) } else { 0u32 }
    let blockGroupsOffset = if (let Some(value) <- blockGroups) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateExpression(builder, base, kind, operandsOffset, blockGroupsOffset, owner, resultLocalVar, resultTy)
}

class UnaryExpressionBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_overflowStrategy(overflowStrategy: UInt8): Unit {
        builder.AddU8(1, overflowStrategy, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateUnaryExpressionBase(builder: FlatBufferBuilder, base: FlatBufferOffset, overflowStrategy: UInt8): FlatBufferOffset {
    let tableBuilder = UnaryExpressionBaseBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_overflowStrategy(overflowStrategy)
    return tableBuilder.Finish()
}

class BinaryExpressionBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_overflowStrategy(overflowStrategy: UInt8): Unit {
        builder.AddU8(1, overflowStrategy, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBinaryExpressionBase(builder: FlatBufferBuilder, base: FlatBufferOffset, overflowStrategy: UInt8): FlatBufferOffset {
    let tableBuilder = BinaryExpressionBaseBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_overflowStrategy(overflowStrategy)
    return tableBuilder.Finish()
}

class AllocateBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_allocatedType(allocatedType: UInt32): Unit {
        builder.AddU32(1, allocatedType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateAllocateBase(builder: FlatBufferBuilder, base: FlatBufferOffset, allocatedType: UInt32): FlatBufferOffset {
    let tableBuilder = AllocateBaseBuilder(builder)
    tableBuilder.add_allocatedType(allocatedType)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class FuncCallBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_instantiatedTypeArgs(instantiatedTypeArgs: FlatBufferOffset): Unit {
        builder.AddOffset(1, instantiatedTypeArgs)
    }

    public func add_objType(objType: UInt32): Unit {
        builder.AddU32(2, objType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFuncCall(builder: FlatBufferBuilder, base: FlatBufferOffset, instantiatedTypeArgs: FlatBufferOffset, objType: UInt32): FlatBufferOffset {
    let tableBuilder = FuncCallBuilder(builder)
    tableBuilder.add_objType(objType)
    tableBuilder.add_instantiatedTypeArgs(instantiatedTypeArgs)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateFuncCallDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, instantiatedTypeArgs: Option<ArrayList<UInt32>>, objType: UInt32): FlatBufferOffset {
    let instantiatedTypeArgsOffset = if (let Some(value) <- instantiatedTypeArgs) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateFuncCall(builder, base, instantiatedTypeArgsOffset, objType)
}

class ApplyBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_isSuperCall(isSuperCall: Bool): Unit {
        builder.AddBool(1, isSuperCall, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateApplyBase(builder: FlatBufferBuilder, base: FlatBufferOffset, isSuperCall: Bool): FlatBufferOffset {
    let tableBuilder = ApplyBaseBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_isSuperCall(isSuperCall)
    return tableBuilder.Finish()
}

class InvokeBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_virMethodCtx(virMethodCtx: FlatBufferOffset): Unit {
        builder.AddOffset(1, virMethodCtx)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateInvokeBase(builder: FlatBufferBuilder, base: FlatBufferOffset, virMethodCtx: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = InvokeBaseBuilder(builder)
    tableBuilder.add_virMethodCtx(virMethodCtx)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class IntrinsicBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_intrinsicKind(intrinsicKind: UInt16): Unit {
        builder.AddU16(1, intrinsicKind, defaultValue: 0u16)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateIntrinsicBase(builder: FlatBufferBuilder, base: FlatBufferOffset, intrinsicKind: UInt16): FlatBufferOffset {
    let tableBuilder = IntrinsicBaseBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_intrinsicKind(intrinsicKind)
    return tableBuilder.Finish()
}

class NumericCastBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_overflowStrategy(overflowStrategy: UInt8): Unit {
        builder.AddU8(1, overflowStrategy, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateNumericCastBase(builder: FlatBufferBuilder, base: FlatBufferOffset, overflowStrategy: UInt8): FlatBufferOffset {
    let tableBuilder = NumericCastBaseBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_overflowStrategy(overflowStrategy)
    return tableBuilder.Finish()
}

class BranchBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_sourceExpr(sourceExpr: UInt8): Unit {
        builder.AddU8(1, sourceExpr, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBranch(builder: FlatBufferBuilder, base: FlatBufferOffset, sourceExpr: UInt8): FlatBufferOffset {
    let tableBuilder = BranchBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_sourceExpr(sourceExpr)
    return tableBuilder.Finish()
}

class MultiBranchBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_caseValues(caseValues: FlatBufferOffset): Unit {
        builder.AddOffset(1, caseValues)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateMultiBranch(builder: FlatBufferBuilder, base: FlatBufferOffset, caseValues: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = MultiBranchBuilder(builder)
    tableBuilder.add_caseValues(caseValues)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateMultiBranchDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, caseValues: Option<ArrayList<UInt64>>): FlatBufferOffset {
    let caseValuesOffset = if (let Some(value) <- caseValues) { builder.CreateVectorU64(value) } else { 0u32 }
    return CreateMultiBranch(builder, base, caseValuesOffset)
}

class GetElementRefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_path(path: FlatBufferOffset): Unit {
        builder.AddOffset(1, path)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGetElementRef(builder: FlatBufferBuilder, base: FlatBufferOffset, path: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = GetElementRefBuilder(builder)
    tableBuilder.add_path(path)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateGetElementRefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, path: Option<ArrayList<UInt64>>): FlatBufferOffset {
    let pathOffset = if (let Some(value) <- path) { builder.CreateVectorU64(value) } else { 0u32 }
    return CreateGetElementRef(builder, base, pathOffset)
}

class GetElementByNameBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_fieldNames(fieldNames: FlatBufferOffset): Unit {
        builder.AddOffset(1, fieldNames)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGetElementByName(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = GetElementByNameBuilder(builder)
    tableBuilder.add_fieldNames(fieldNames)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateGetElementByNameDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let fieldNamesOffset = if (let Some(value) <- fieldNames) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateGetElementByName(builder, base, fieldNamesOffset)
}

class StoreElementRefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_path(path: FlatBufferOffset): Unit {
        builder.AddOffset(1, path)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateStoreElementRef(builder: FlatBufferBuilder, base: FlatBufferOffset, path: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = StoreElementRefBuilder(builder)
    tableBuilder.add_path(path)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateStoreElementRefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, path: Option<ArrayList<UInt64>>): FlatBufferOffset {
    let pathOffset = if (let Some(value) <- path) { builder.CreateVectorU64(value) } else { 0u32 }
    return CreateStoreElementRef(builder, base, pathOffset)
}

class StoreElementByNameBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_fieldNames(fieldNames: FlatBufferOffset): Unit {
        builder.AddOffset(1, fieldNames)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateStoreElementByName(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = StoreElementByNameBuilder(builder)
    tableBuilder.add_fieldNames(fieldNames)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateStoreElementByNameDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let fieldNamesOffset = if (let Some(value) <- fieldNames) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateStoreElementByName(builder, base, fieldNamesOffset)
}

class InstanceOfBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_targetType(targetType: UInt32): Unit {
        builder.AddU32(1, targetType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateInstanceOf(builder: FlatBufferBuilder, base: FlatBufferOffset, targetType: UInt32): FlatBufferOffset {
    let tableBuilder = InstanceOfBuilder(builder)
    tableBuilder.add_targetType(targetType)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class FieldBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_path(path: FlatBufferOffset): Unit {
        builder.AddOffset(1, path)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateField(builder: FlatBufferBuilder, base: FlatBufferOffset, path: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = FieldBuilder(builder)
    tableBuilder.add_path(path)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateFieldDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, path: Option<ArrayList<UInt64>>): FlatBufferOffset {
    let pathOffset = if (let Some(value) <- path) { builder.CreateVectorU64(value) } else { 0u32 }
    return CreateField(builder, base, pathOffset)
}

class FieldByNameBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_fieldNames(fieldNames: FlatBufferOffset): Unit {
        builder.AddOffset(1, fieldNames)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFieldByName(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = FieldByNameBuilder(builder)
    tableBuilder.add_fieldNames(fieldNames)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateFieldByNameDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, fieldNames: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let fieldNamesOffset = if (let Some(value) <- fieldNames) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateFieldByName(builder, base, fieldNamesOffset)
}

class RawArrayAllocateBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_elementType(elementType: UInt32): Unit {
        builder.AddU32(1, elementType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateRawArrayAllocateBase(builder: FlatBufferBuilder, base: FlatBufferOffset, elementType: UInt32): FlatBufferOffset {
    let tableBuilder = RawArrayAllocateBaseBuilder(builder)
    tableBuilder.add_elementType(elementType)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class DebugBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_srcCodeName(srcCodeName: FlatBufferOffset): Unit {
        builder.AddOffset(1, srcCodeName)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateDebug(builder: FlatBufferBuilder, base: FlatBufferOffset, srcCodeName: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = DebugBuilder(builder)
    tableBuilder.add_srcCodeName(srcCodeName)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateDebugDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, srcCodeName: Option<String>): FlatBufferOffset {
    let srcCodeNameOffset = if (let Some(value) <- srcCodeName) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateDebug(builder, base, srcCodeNameOffset)
}

class SpawnBaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_executeClosure(executeClosure: UInt32): Unit {
        builder.AddU32(1, executeClosure, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateSpawnBase(builder: FlatBufferBuilder, base: FlatBufferOffset, executeClosure: UInt32): FlatBufferOffset {
    let tableBuilder = SpawnBaseBuilder(builder)
    tableBuilder.add_executeClosure(executeClosure)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class LambdaBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(10)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_funcTy(funcTy: UInt32): Unit {
        builder.AddU32(1, funcTy, defaultValue: 0u32)
    }

    public func add_isLocalFunc(isLocalFunc: Bool): Unit {
        builder.AddBool(2, isLocalFunc, defaultValue: false)
    }

    public func add_identifier(identifier: FlatBufferOffset): Unit {
        builder.AddOffset(3, identifier)
    }

    public func add_srcCodeName(srcCodeName: FlatBufferOffset): Unit {
        builder.AddOffset(4, srcCodeName)
    }

    public func add_params(params: FlatBufferOffset): Unit {
        builder.AddOffset(5, params)
    }

    public func add_genericTypeParams(genericTypeParams: FlatBufferOffset): Unit {
        builder.AddOffset(6, genericTypeParams)
    }

    public func add_body(body: UInt32): Unit {
        builder.AddU32(7, body, defaultValue: 0u32)
    }

    public func add_retVal(retVal: UInt32): Unit {
        builder.AddU32(8, retVal, defaultValue: 0u32)
    }

    public func add_isCompileTimeValue(isCompileTimeValue: Bool): Unit {
        builder.AddBool(9, isCompileTimeValue, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateLambda(builder: FlatBufferBuilder, base: FlatBufferOffset, funcTy: UInt32, isLocalFunc: Bool, identifier: FlatBufferOffset, srcCodeName: FlatBufferOffset, params: FlatBufferOffset, genericTypeParams: FlatBufferOffset, body: UInt32, retVal: UInt32, isCompileTimeValue: Bool): FlatBufferOffset {
    let tableBuilder = LambdaBuilder(builder)
    tableBuilder.add_retVal(retVal)
    tableBuilder.add_body(body)
    tableBuilder.add_genericTypeParams(genericTypeParams)
    tableBuilder.add_params(params)
    tableBuilder.add_srcCodeName(srcCodeName)
    tableBuilder.add_identifier(identifier)
    tableBuilder.add_funcTy(funcTy)
    tableBuilder.add_base(base)
    tableBuilder.add_isCompileTimeValue(isCompileTimeValue)
    tableBuilder.add_isLocalFunc(isLocalFunc)
    return tableBuilder.Finish()
}

func CreateLambdaDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, funcTy: UInt32, isLocalFunc: Bool, identifier: Option<String>, srcCodeName: Option<String>, params: Option<ArrayList<UInt32>>, genericTypeParams: Option<ArrayList<UInt32>>, body: UInt32, retVal: UInt32, isCompileTimeValue: Bool): FlatBufferOffset {
    let identifierOffset = if (let Some(value) <- identifier) { builder.CreateSharedString(value) } else { 0u32 }
    let srcCodeNameOffset = if (let Some(value) <- srcCodeName) { builder.CreateSharedString(value) } else { 0u32 }
    let paramsOffset = if (let Some(value) <- params) { builder.CreateVectorU32(value) } else { 0u32 }
    let genericTypeParamsOffset = if (let Some(value) <- genericTypeParams) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateLambda(builder, base, funcTy, isLocalFunc, identifierOffset, srcCodeNameOffset, paramsOffset, genericTypeParamsOffset, body, retVal, isCompileTimeValue)
}

class GetInstantiateValueBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_instantiateTypes(instantiateTypes: FlatBufferOffset): Unit {
        builder.AddOffset(1, instantiateTypes)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGetInstantiateValue(builder: FlatBufferBuilder, base: FlatBufferOffset, instantiateTypes: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = GetInstantiateValueBuilder(builder)
    tableBuilder.add_instantiateTypes(instantiateTypes)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateGetInstantiateValueDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, instantiateTypes: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let instantiateTypesOffset = if (let Some(value) <- instantiateTypes) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateGetInstantiateValue(builder, base, instantiateTypesOffset)
}

class GetRTTIStaticBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_rttiType(rttiType: UInt32): Unit {
        builder.AddU32(1, rttiType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGetRTTIStatic(builder: FlatBufferBuilder, base: FlatBufferOffset, rttiType: UInt32): FlatBufferOffset {
    let tableBuilder = GetRTTIStaticBuilder(builder)
    tableBuilder.add_rttiType(rttiType)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}
