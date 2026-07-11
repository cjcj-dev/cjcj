package cjcj::chir

import std.collection.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

class TypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_kind(kind: UInt8): Unit {
        builder.AddU8(0, kind, defaultValue: 0u8)
    }

    public func add_argTys(argTys: FlatBufferOffset): Unit {
        builder.AddOffset(1, argTys)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateType(builder: FlatBufferBuilder, kind: UInt8, argTys: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = TypeBuilder(builder)
    tableBuilder.add_argTys(argTys)
    tableBuilder.add_kind(kind)
    return tableBuilder.Finish()
}

func CreateTypeDirect(builder: FlatBufferBuilder, kind: UInt8, argTys: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let argTysOffset = if (let Some(value) <- argTys) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateType(builder, kind, argTysOffset)
}

class RawArrayTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_dims(dims: UInt32): Unit {
        builder.AddU32(1, dims, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateRawArrayType(builder: FlatBufferBuilder, base: FlatBufferOffset, dims: UInt32): FlatBufferOffset {
    let tableBuilder = RawArrayTypeBuilder(builder)
    tableBuilder.add_dims(dims)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class VArrayTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_size(size: Int64): Unit {
        builder.AddI64(1, size, defaultValue: 0)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateVArrayType(builder: FlatBufferBuilder, base: FlatBufferOffset, size: Int64): FlatBufferOffset {
    let tableBuilder = VArrayTypeBuilder(builder)
    tableBuilder.add_size(size)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class FuncTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_isCFuncType(isCFuncType: Bool): Unit {
        builder.AddBool(1, isCFuncType, defaultValue: false)
    }

    public func add_hasVarArg(hasVarArg: Bool): Unit {
        builder.AddBool(2, hasVarArg, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateFuncType(builder: FlatBufferBuilder, base: FlatBufferOffset, isCFuncType: Bool, hasVarArg: Bool): FlatBufferOffset {
    let tableBuilder = FuncTypeBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_hasVarArg(hasVarArg)
    tableBuilder.add_isCFuncType(isCFuncType)
    return tableBuilder.Finish()
}

class CustomTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_customTypeDef(customTypeDef: UInt32): Unit {
        builder.AddU32(1, customTypeDef, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateCustomType(builder: FlatBufferBuilder, base: FlatBufferOffset, customTypeDef: UInt32): FlatBufferOffset {
    let tableBuilder = CustomTypeBuilder(builder)
    tableBuilder.add_customTypeDef(customTypeDef)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

class GenericTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(4)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_identifier(identifier: FlatBufferOffset): Unit {
        builder.AddOffset(1, identifier)
    }

    public func add_srcCodeIdentifier(srcCodeIdentifier: FlatBufferOffset): Unit {
        builder.AddOffset(2, srcCodeIdentifier)
    }

    public func add_upperBounds(upperBounds: FlatBufferOffset): Unit {
        builder.AddOffset(3, upperBounds)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGenericType(builder: FlatBufferBuilder, base: FlatBufferOffset, identifier: FlatBufferOffset, srcCodeIdentifier: FlatBufferOffset, upperBounds: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = GenericTypeBuilder(builder)
    tableBuilder.add_upperBounds(upperBounds)
    tableBuilder.add_srcCodeIdentifier(srcCodeIdentifier)
    tableBuilder.add_identifier(identifier)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateGenericTypeDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, identifier: Option<String>, srcCodeIdentifier: Option<String>, upperBounds: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let identifierOffset = if (let Some(value) <- identifier) { builder.CreateSharedString(value) } else { 0u32 }
    let srcCodeIdentifierOffset = if (let Some(value) <- srcCodeIdentifier) { builder.CreateSharedString(value) } else { 0u32 }
    let upperBoundsOffset = if (let Some(value) <- upperBounds) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateGenericType(builder, base, identifierOffset, srcCodeIdentifierOffset, upperBoundsOffset)
}

class PosBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_line(line: UInt32): Unit {
        builder.AddU32(0, line, defaultValue: 0u32)
    }

    public func add_column(column: UInt32): Unit {
        builder.AddU32(1, column, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreatePos(builder: FlatBufferBuilder, line: UInt32, column: UInt32): FlatBufferOffset {
    let tableBuilder = PosBuilder(builder)
    tableBuilder.add_column(column)
    tableBuilder.add_line(line)
    return tableBuilder.Finish()
}

class DebugLocationBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(5)
    }

    public func add_filePath(filePath: FlatBufferOffset): Unit {
        builder.AddOffset(0, filePath)
    }

    public func add_fileId(fileId: UInt32): Unit {
        builder.AddU32(1, fileId, defaultValue: 0u32)
    }

    public func add_beginPos(beginPos: FlatBufferOffset): Unit {
        builder.AddOffset(2, beginPos)
    }

    public func add_endPos(endPos: FlatBufferOffset): Unit {
        builder.AddOffset(3, endPos)
    }

    public func add_scope(scope: FlatBufferOffset): Unit {
        builder.AddOffset(4, scope)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateDebugLocation(builder: FlatBufferBuilder, filePath: FlatBufferOffset, fileId: UInt32, beginPos: FlatBufferOffset, endPos: FlatBufferOffset, scope: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = DebugLocationBuilder(builder)
    tableBuilder.add_scope(scope)
    tableBuilder.add_endPos(endPos)
    tableBuilder.add_beginPos(beginPos)
    tableBuilder.add_fileId(fileId)
    tableBuilder.add_filePath(filePath)
    return tableBuilder.Finish()
}

func CreateDebugLocationDirect(builder: FlatBufferBuilder, filePath: Option<String>, fileId: UInt32, beginPos: FlatBufferOffset, endPos: FlatBufferOffset, scope: Option<ArrayList<Int64>>): FlatBufferOffset {
    let filePathOffset = if (let Some(value) <- filePath) { builder.CreateSharedString(value) } else { 0u32 }
    let scopeOffset = if (let Some(value) <- scope) { builder.CreateVectorI32(value) } else { 0u32 }
    return CreateDebugLocation(builder, filePathOffset, fileId, beginPos, endPos, scopeOffset)
}

class LinkTypeInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_linkage(linkage: Int16): Unit {
        builder.AddI16(0, linkage, defaultValue: 0i16)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateLinkTypeInfo(builder: FlatBufferBuilder, linkage: Int16): FlatBufferOffset {
    let tableBuilder = LinkTypeInfoBuilder(builder)
    tableBuilder.add_linkage(linkage)
    return tableBuilder.Finish()
}

class SkipCheckBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_skipKind(skipKind: UInt8): Unit {
        builder.AddU8(0, skipKind, defaultValue: 0u8)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateSkipCheck(builder: FlatBufferBuilder, skipKind: UInt8): FlatBufferOffset {
    let tableBuilder = SkipCheckBuilder(builder)
    tableBuilder.add_skipKind(skipKind)
    return tableBuilder.Finish()
}

class NeedCheckArrayBoundBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_need(need: Bool): Unit {
        builder.AddBool(0, need, defaultValue: true)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateNeedCheckArrayBound(builder: FlatBufferBuilder, need: Bool): FlatBufferOffset {
    let tableBuilder = NeedCheckArrayBoundBuilder(builder)
    tableBuilder.add_need(need)
    return tableBuilder.Finish()
}

class NeedCheckCastBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_need(need: Bool): Unit {
        builder.AddBool(0, need, defaultValue: true)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateNeedCheckCast(builder: FlatBufferBuilder, need: Bool): FlatBufferOffset {
    let tableBuilder = NeedCheckCastBuilder(builder)
    tableBuilder.add_need(need)
    return tableBuilder.Finish()
}

class NeverOverflowInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_neverOverflow(neverOverflow: Bool): Unit {
        builder.AddBool(0, neverOverflow, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateNeverOverflowInfo(builder: FlatBufferBuilder, neverOverflow: Bool): FlatBufferOffset {
    let tableBuilder = NeverOverflowInfoBuilder(builder)
    tableBuilder.add_neverOverflow(neverOverflow)
    return tableBuilder.Finish()
}

class GeneratedFromForInBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_value(value: Bool): Unit {
        builder.AddBool(0, value, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateGeneratedFromForIn(builder: FlatBufferBuilder, value: Bool): FlatBufferOffset {
    let tableBuilder = GeneratedFromForInBuilder(builder)
    tableBuilder.add_value(value)
    return tableBuilder.Finish()
}

class IsAutoEnvClassBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_value(value: Bool): Unit {
        builder.AddBool(0, value, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateIsAutoEnvClass(builder: FlatBufferBuilder, value: Bool): FlatBufferOffset {
    let tableBuilder = IsAutoEnvClassBuilder(builder)
    tableBuilder.add_value(value)
    return tableBuilder.Finish()
}

class IsCapturedClassInCCBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_value(value: Bool): Unit {
        builder.AddBool(0, value, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateIsCapturedClassInCC(builder: FlatBufferBuilder, value: Bool): FlatBufferOffset {
    let tableBuilder = IsCapturedClassInCCBuilder(builder)
    tableBuilder.add_value(value)
    return tableBuilder.Finish()
}

class EnumCaseIndexBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_index(index: Int64): Unit {
        builder.AddI64(0, index, defaultValue: -1)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateEnumCaseIndex(builder: FlatBufferBuilder, index: Int64): FlatBufferOffset {
    let tableBuilder = EnumCaseIndexBuilder(builder)
    tableBuilder.add_index(index)
    return tableBuilder.Finish()
}

class VirMethodOffsetBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_offset(offset: Int64): Unit {
        builder.AddI64(0, offset, defaultValue: -1)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateVirMethodOffset(builder: FlatBufferBuilder, offset: Int64): FlatBufferOffset {
    let tableBuilder = VirMethodOffsetBuilder(builder)
    tableBuilder.add_offset(offset)
    return tableBuilder.Finish()
}

class WrappedRawMethodBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_rawMethod(rawMethod: UInt32): Unit {
        builder.AddU32(0, rawMethod, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateWrappedRawMethod(builder: FlatBufferBuilder, rawMethod: UInt32): FlatBufferOffset {
    let tableBuilder = WrappedRawMethodBuilder(builder)
    tableBuilder.add_rawMethod(rawMethod)
    return tableBuilder.Finish()
}

class OverrideSrcFuncTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(1)
    }

    public func add_type(`type`: UInt32): Unit {
        builder.AddU32(0, `type`, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateOverrideSrcFuncType(builder: FlatBufferBuilder, `type`: UInt32): FlatBufferOffset {
    let tableBuilder = OverrideSrcFuncTypeBuilder(builder)
    tableBuilder.add_type(`type`)
    return tableBuilder.Finish()
}

class BaseBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(4)
    }

    public func add_annos_type(annos_type: FlatBufferOffset): Unit {
        builder.AddOffset(0, annos_type)
    }

    public func add_annos(annos: FlatBufferOffset): Unit {
        builder.AddOffset(1, annos)
    }

    public func add_loc(loc: FlatBufferOffset): Unit {
        builder.AddOffset(2, loc)
    }

    public func add_attributes(attributes: UInt64): Unit {
        builder.AddU64(3, attributes, defaultValue: 0u64)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateBase(builder: FlatBufferBuilder, annos_type: FlatBufferOffset, annos: FlatBufferOffset, loc: FlatBufferOffset, attributes: UInt64): FlatBufferOffset {
    let tableBuilder = BaseBuilder(builder)
    tableBuilder.add_attributes(attributes)
    tableBuilder.add_loc(loc)
    tableBuilder.add_annos(annos)
    tableBuilder.add_annos_type(annos_type)
    return tableBuilder.Finish()
}

func CreateBaseDirect(builder: FlatBufferBuilder, annos_type: Option<ArrayList<UInt8>>, annos: Option<ArrayList<FlatBufferOffset>>, loc: FlatBufferOffset, attributes: UInt64): FlatBufferOffset {
    let annos_typeOffset = if (let Some(value) <- annos_type) { builder.CreateVectorU8(value) } else { 0u32 }
    let annosOffset = if (let Some(value) <- annos) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateBase(builder, annos_typeOffset, annosOffset, loc, attributes)
}

class CustomAnnoInstanceBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_annoClassName(annoClassName: FlatBufferOffset): Unit {
        builder.AddOffset(0, annoClassName)
    }

    public func add_argValues(argValues: FlatBufferOffset): Unit {
        builder.AddOffset(1, argValues)
    }

    public func add_loc(loc: FlatBufferOffset): Unit {
        builder.AddOffset(2, loc)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateCustomAnnoInstance(builder: FlatBufferBuilder, annoClassName: FlatBufferOffset, argValues: FlatBufferOffset, loc: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = CustomAnnoInstanceBuilder(builder)
    tableBuilder.add_loc(loc)
    tableBuilder.add_argValues(argValues)
    tableBuilder.add_annoClassName(annoClassName)
    return tableBuilder.Finish()
}

func CreateCustomAnnoInstanceDirect(builder: FlatBufferBuilder, annoClassName: Option<String>, argValues: Option<ArrayList<FlatBufferOffset>>, loc: FlatBufferOffset): FlatBufferOffset {
    let annoClassNameOffset = if (let Some(value) <- annoClassName) { builder.CreateSharedString(value) } else { 0u32 }
    let argValuesOffset = if (let Some(value) <- argValues) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateCustomAnnoInstance(builder, annoClassNameOffset, argValuesOffset, loc)
}

class AnnoInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_mangledName(mangledName: FlatBufferOffset): Unit {
        builder.AddOffset(0, mangledName)
    }

    public func add_annoInstances(annoInstances: FlatBufferOffset): Unit {
        builder.AddOffset(1, annoInstances)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateAnnoInfo(builder: FlatBufferBuilder, mangledName: FlatBufferOffset, annoInstances: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = AnnoInfoBuilder(builder)
    tableBuilder.add_annoInstances(annoInstances)
    tableBuilder.add_mangledName(mangledName)
    return tableBuilder.Finish()
}

func CreateAnnoInfoDirect(builder: FlatBufferBuilder, mangledName: Option<String>, annoInstances: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let mangledNameOffset = if (let Some(value) <- mangledName) { builder.CreateSharedString(value) } else { 0u32 }
    let annoInstancesOffset = if (let Some(value) <- annoInstances) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateAnnoInfo(builder, mangledNameOffset, annoInstancesOffset)
}

class MemberVarInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(8)
    }

    public func add_name(name: FlatBufferOffset): Unit {
        builder.AddOffset(0, name)
    }

    public func add_rawMangledName(rawMangledName: FlatBufferOffset): Unit {
        builder.AddOffset(1, rawMangledName)
    }

    public func add_type(`type`: UInt32): Unit {
        builder.AddU32(2, `type`, defaultValue: 0u32)
    }

    public func add_attributes(attributes: UInt64): Unit {
        builder.AddU64(3, attributes, defaultValue: 0u64)
    }

    public func add_loc(loc: FlatBufferOffset): Unit {
        builder.AddOffset(4, loc)
    }

    public func add_annoInfo(annoInfo: FlatBufferOffset): Unit {
        builder.AddOffset(5, annoInfo)
    }

    public func add_initializerFunc(initializerFunc: UInt32): Unit {
        builder.AddU32(6, initializerFunc, defaultValue: 0u32)
    }

    public func add_outerDef(outerDef: UInt32): Unit {
        builder.AddU32(7, outerDef, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateMemberVarInfo(builder: FlatBufferBuilder, name: FlatBufferOffset, rawMangledName: FlatBufferOffset, `type`: UInt32, attributes: UInt64, loc: FlatBufferOffset, annoInfo: FlatBufferOffset, initializerFunc: UInt32, outerDef: UInt32): FlatBufferOffset {
    let tableBuilder = MemberVarInfoBuilder(builder)
    tableBuilder.add_attributes(attributes)
    tableBuilder.add_outerDef(outerDef)
    tableBuilder.add_initializerFunc(initializerFunc)
    tableBuilder.add_annoInfo(annoInfo)
    tableBuilder.add_loc(loc)
    tableBuilder.add_type(`type`)
    tableBuilder.add_rawMangledName(rawMangledName)
    tableBuilder.add_name(name)
    return tableBuilder.Finish()
}

func CreateMemberVarInfoDirect(builder: FlatBufferBuilder, name: Option<String>, rawMangledName: Option<String>, `type`: UInt32, attributes: UInt64, loc: FlatBufferOffset, annoInfo: FlatBufferOffset, initializerFunc: UInt32, outerDef: UInt32): FlatBufferOffset {
    let nameOffset = if (let Some(value) <- name) { builder.CreateSharedString(value) } else { 0u32 }
    let rawMangledNameOffset = if (let Some(value) <- rawMangledName) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateMemberVarInfo(builder, nameOffset, rawMangledNameOffset, `type`, attributes, loc, annoInfo, initializerFunc, outerDef)
}

class VirtualMethodInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(8)
    }

    public func add_funcName(funcName: FlatBufferOffset): Unit {
        builder.AddOffset(0, funcName)
    }

    public func add_sigType(sigType: UInt32): Unit {
        builder.AddU32(1, sigType, defaultValue: 0u32)
    }

    public func add_methodGenericTypeParams(methodGenericTypeParams: FlatBufferOffset): Unit {
        builder.AddOffset(2, methodGenericTypeParams)
    }

    public func add_instance(instance: UInt32): Unit {
        builder.AddU32(3, instance, defaultValue: 0u32)
    }

    public func add_attributes(attributes: UInt64): Unit {
        builder.AddU64(4, attributes, defaultValue: 0u64)
    }

    public func add_originalType(originalType: UInt32): Unit {
        builder.AddU32(5, originalType, defaultValue: 0u32)
    }

    public func add_parentType(parentType: UInt32): Unit {
        builder.AddU32(6, parentType, defaultValue: 0u32)
    }

    public func add_returnType(returnType: UInt32): Unit {
        builder.AddU32(7, returnType, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateVirtualMethodInfo(builder: FlatBufferBuilder, funcName: FlatBufferOffset, sigType: UInt32, methodGenericTypeParams: FlatBufferOffset, instance: UInt32, attributes: UInt64, originalType: UInt32, parentType: UInt32, returnType: UInt32): FlatBufferOffset {
    let tableBuilder = VirtualMethodInfoBuilder(builder)
    tableBuilder.add_attributes(attributes)
    tableBuilder.add_returnType(returnType)
    tableBuilder.add_parentType(parentType)
    tableBuilder.add_originalType(originalType)
    tableBuilder.add_instance(instance)
    tableBuilder.add_methodGenericTypeParams(methodGenericTypeParams)
    tableBuilder.add_sigType(sigType)
    tableBuilder.add_funcName(funcName)
    return tableBuilder.Finish()
}

func CreateVirtualMethodInfoDirect(builder: FlatBufferBuilder, funcName: Option<String>, sigType: UInt32, methodGenericTypeParams: Option<ArrayList<UInt32>>, instance: UInt32, attributes: UInt64, originalType: UInt32, parentType: UInt32, returnType: UInt32): FlatBufferOffset {
    let funcNameOffset = if (let Some(value) <- funcName) { builder.CreateSharedString(value) } else { 0u32 }
    let methodGenericTypeParamsOffset = if (let Some(value) <- methodGenericTypeParams) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateVirtualMethodInfo(builder, funcNameOffset, sigType, methodGenericTypeParamsOffset, instance, attributes, originalType, parentType, returnType)
}

class VTableInTypeBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_srcParentType(srcParentType: UInt32): Unit {
        builder.AddU32(0, srcParentType, defaultValue: 0u32)
    }

    public func add_virtualMethods(virtualMethods: FlatBufferOffset): Unit {
        builder.AddOffset(1, virtualMethods)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateVTableInType(builder: FlatBufferBuilder, srcParentType: UInt32, virtualMethods: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = VTableInTypeBuilder(builder)
    tableBuilder.add_virtualMethods(virtualMethods)
    tableBuilder.add_srcParentType(srcParentType)
    return tableBuilder.Finish()
}

func CreateVTableInTypeDirect(builder: FlatBufferBuilder, srcParentType: UInt32, virtualMethods: Option<ArrayList<FlatBufferOffset>>): FlatBufferOffset {
    let virtualMethodsOffset = if (let Some(value) <- virtualMethods) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateVTableInType(builder, srcParentType, virtualMethodsOffset)
}

class CustomTypeDefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(15)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_kind(kind: UInt8): Unit {
        builder.AddU8(1, kind, defaultValue: 0u8)
    }

    public func add_customTypeDefID(customTypeDefID: UInt32): Unit {
        builder.AddU32(2, customTypeDefID, defaultValue: 0u32)
    }

    public func add_srcCodeIdentifier(srcCodeIdentifier: FlatBufferOffset): Unit {
        builder.AddOffset(3, srcCodeIdentifier)
    }

    public func add_identifier(identifier: FlatBufferOffset): Unit {
        builder.AddOffset(4, identifier)
    }

    public func add_packageName(packageName: FlatBufferOffset): Unit {
        builder.AddOffset(5, packageName)
    }

    public func add_type(`type`: UInt32): Unit {
        builder.AddU32(6, `type`, defaultValue: 0u32)
    }

    public func add_genericDecl(genericDecl: UInt32): Unit {
        builder.AddU32(7, genericDecl, defaultValue: 0u32)
    }

    public func add_methods(methods: FlatBufferOffset): Unit {
        builder.AddOffset(8, methods)
    }

    public func add_implementedInterfaces(implementedInterfaces: FlatBufferOffset): Unit {
        builder.AddOffset(9, implementedInterfaces)
    }

    public func add_instanceMemberVars(instanceMemberVars: FlatBufferOffset): Unit {
        builder.AddOffset(10, instanceMemberVars)
    }

    public func add_staticMemberVars(staticMemberVars: FlatBufferOffset): Unit {
        builder.AddOffset(11, staticMemberVars)
    }

    public func add_annoInfo(annoInfo: FlatBufferOffset): Unit {
        builder.AddOffset(12, annoInfo)
    }

    public func add_vtable(vtable: FlatBufferOffset): Unit {
        builder.AddOffset(13, vtable)
    }

    public func add_instanceVarInitFunc(instanceVarInitFunc: UInt32): Unit {
        builder.AddU32(14, instanceVarInitFunc, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateCustomTypeDef(builder: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt8, customTypeDefID: UInt32, srcCodeIdentifier: FlatBufferOffset, identifier: FlatBufferOffset, packageName: FlatBufferOffset, `type`: UInt32, genericDecl: UInt32, methods: FlatBufferOffset, implementedInterfaces: FlatBufferOffset, instanceMemberVars: FlatBufferOffset, staticMemberVars: FlatBufferOffset, annoInfo: FlatBufferOffset, vtable: FlatBufferOffset, instanceVarInitFunc: UInt32): FlatBufferOffset {
    let tableBuilder = CustomTypeDefBuilder(builder)
    tableBuilder.add_instanceVarInitFunc(instanceVarInitFunc)
    tableBuilder.add_vtable(vtable)
    tableBuilder.add_annoInfo(annoInfo)
    tableBuilder.add_staticMemberVars(staticMemberVars)
    tableBuilder.add_instanceMemberVars(instanceMemberVars)
    tableBuilder.add_implementedInterfaces(implementedInterfaces)
    tableBuilder.add_methods(methods)
    tableBuilder.add_genericDecl(genericDecl)
    tableBuilder.add_type(`type`)
    tableBuilder.add_packageName(packageName)
    tableBuilder.add_identifier(identifier)
    tableBuilder.add_srcCodeIdentifier(srcCodeIdentifier)
    tableBuilder.add_customTypeDefID(customTypeDefID)
    tableBuilder.add_base(base)
    tableBuilder.add_kind(kind)
    return tableBuilder.Finish()
}

func CreateCustomTypeDefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt8, customTypeDefID: UInt32, srcCodeIdentifier: Option<String>, identifier: Option<String>, packageName: Option<String>, `type`: UInt32, genericDecl: UInt32, methods: Option<ArrayList<UInt32>>, implementedInterfaces: Option<ArrayList<UInt32>>, instanceMemberVars: Option<ArrayList<FlatBufferOffset>>, staticMemberVars: Option<ArrayList<UInt32>>, annoInfo: FlatBufferOffset, vtable: Option<ArrayList<FlatBufferOffset>>, instanceVarInitFunc: UInt32): FlatBufferOffset {
    let srcCodeIdentifierOffset = if (let Some(value) <- srcCodeIdentifier) { builder.CreateSharedString(value) } else { 0u32 }
    let identifierOffset = if (let Some(value) <- identifier) { builder.CreateSharedString(value) } else { 0u32 }
    let packageNameOffset = if (let Some(value) <- packageName) { builder.CreateSharedString(value) } else { 0u32 }
    let methodsOffset = if (let Some(value) <- methods) { builder.CreateVectorU32(value) } else { 0u32 }
    let implementedInterfacesOffset = if (let Some(value) <- implementedInterfaces) { builder.CreateVectorU32(value) } else { 0u32 }
    let instanceMemberVarsOffset = if (let Some(value) <- instanceMemberVars) { builder.CreateVectorOffsets(value) } else { 0u32 }
    let staticMemberVarsOffset = if (let Some(value) <- staticMemberVars) { builder.CreateVectorU32(value) } else { 0u32 }
    let vtableOffset = if (let Some(value) <- vtable) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateCustomTypeDef(builder, base, kind, customTypeDefID, srcCodeIdentifierOffset, identifierOffset, packageNameOffset, `type`, genericDecl, methodsOffset, implementedInterfacesOffset, instanceMemberVarsOffset, staticMemberVarsOffset, annoInfo, vtableOffset, instanceVarInitFunc)
}

class EnumCtorInfoBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(4)
    }

    public func add_srcCodeName(srcCodeName: FlatBufferOffset): Unit {
        builder.AddOffset(0, srcCodeName)
    }

    public func add_mangledName(mangledName: FlatBufferOffset): Unit {
        builder.AddOffset(1, mangledName)
    }

    public func add_funcType(funcType: UInt32): Unit {
        builder.AddU32(2, funcType, defaultValue: 0u32)
    }

    public func add_annoInfo(annoInfo: FlatBufferOffset): Unit {
        builder.AddOffset(3, annoInfo)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateEnumCtorInfo(builder: FlatBufferBuilder, srcCodeName: FlatBufferOffset, mangledName: FlatBufferOffset, funcType: UInt32, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = EnumCtorInfoBuilder(builder)
    tableBuilder.add_annoInfo(annoInfo)
    tableBuilder.add_funcType(funcType)
    tableBuilder.add_mangledName(mangledName)
    tableBuilder.add_srcCodeName(srcCodeName)
    return tableBuilder.Finish()
}

func CreateEnumCtorInfoDirect(builder: FlatBufferBuilder, srcCodeName: Option<String>, mangledName: Option<String>, funcType: UInt32, annoInfo: FlatBufferOffset): FlatBufferOffset {
    let srcCodeNameOffset = if (let Some(value) <- srcCodeName) { builder.CreateSharedString(value) } else { 0u32 }
    let mangledNameOffset = if (let Some(value) <- mangledName) { builder.CreateSharedString(value) } else { 0u32 }
    return CreateEnumCtorInfo(builder, srcCodeNameOffset, mangledNameOffset, funcType, annoInfo)
}

class EnumDefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_ctors(ctors: FlatBufferOffset): Unit {
        builder.AddOffset(1, ctors)
    }

    public func add_nonExhaustive(nonExhaustive: Bool): Unit {
        builder.AddBool(2, nonExhaustive, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateEnumDef(builder: FlatBufferBuilder, base: FlatBufferOffset, ctors: FlatBufferOffset, nonExhaustive: Bool): FlatBufferOffset {
    let tableBuilder = EnumDefBuilder(builder)
    tableBuilder.add_ctors(ctors)
    tableBuilder.add_base(base)
    tableBuilder.add_nonExhaustive(nonExhaustive)
    return tableBuilder.Finish()
}

func CreateEnumDefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, ctors: Option<ArrayList<FlatBufferOffset>>, nonExhaustive: Bool): FlatBufferOffset {
    let ctorsOffset = if (let Some(value) <- ctors) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateEnumDef(builder, base, ctorsOffset, nonExhaustive)
}

class StructDefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(2)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_isCStruct(isCStruct: Bool): Unit {
        builder.AddBool(1, isCStruct, defaultValue: false)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateStructDef(builder: FlatBufferBuilder, base: FlatBufferOffset, isCStruct: Bool): FlatBufferOffset {
    let tableBuilder = StructDefBuilder(builder)
    tableBuilder.add_base(base)
    tableBuilder.add_isCStruct(isCStruct)
    return tableBuilder.Finish()
}

class ExtendDefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(3)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_extendedType(extendedType: UInt32): Unit {
        builder.AddU32(1, extendedType, defaultValue: 0u32)
    }

    public func add_genericParams(genericParams: FlatBufferOffset): Unit {
        builder.AddOffset(2, genericParams)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateExtendDef(builder: FlatBufferBuilder, base: FlatBufferOffset, extendedType: UInt32, genericParams: FlatBufferOffset): FlatBufferOffset {
    let tableBuilder = ExtendDefBuilder(builder)
    tableBuilder.add_genericParams(genericParams)
    tableBuilder.add_extendedType(extendedType)
    tableBuilder.add_base(base)
    return tableBuilder.Finish()
}

func CreateExtendDefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, extendedType: UInt32, genericParams: Option<ArrayList<UInt32>>): FlatBufferOffset {
    let genericParamsOffset = if (let Some(value) <- genericParams) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateExtendDef(builder, base, extendedType, genericParamsOffset)
}

class ClassDefBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(5)
    }

    public func add_base(base: FlatBufferOffset): Unit {
        builder.AddOffset(0, base)
    }

    public func add_isClass(isClass: Bool): Unit {
        builder.AddBool(1, isClass, defaultValue: false)
    }

    public func add_isAnnotation(isAnnotation: Bool): Unit {
        builder.AddBool(2, isAnnotation, defaultValue: false)
    }

    public func add_annotationTargets(annotationTargets: FlatBufferOffset): Unit {
        builder.AddOffset(3, annotationTargets)
    }

    public func add_superClass(superClass: UInt32): Unit {
        builder.AddU32(4, superClass, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateClassDef(builder: FlatBufferBuilder, base: FlatBufferOffset, isClass: Bool, isAnnotation: Bool, annotationTargets: FlatBufferOffset, superClass: UInt32): FlatBufferOffset {
    let tableBuilder = ClassDefBuilder(builder)
    tableBuilder.add_superClass(superClass)
    tableBuilder.add_annotationTargets(annotationTargets)
    tableBuilder.add_base(base)
    tableBuilder.add_isAnnotation(isAnnotation)
    tableBuilder.add_isClass(isClass)
    return tableBuilder.Finish()
}

func CreateClassDefDirect(builder: FlatBufferBuilder, base: FlatBufferOffset, isClass: Bool, isAnnotation: Bool, annotationTargets: Option<ArrayList<UInt32>>, superClass: UInt32): FlatBufferOffset {
    let annotationTargetsOffset = if (let Some(value) <- annotationTargets) { builder.CreateVectorU32(value) } else { 0u32 }
    return CreateClassDef(builder, base, isClass, isAnnotation, annotationTargetsOffset, superClass)
}
