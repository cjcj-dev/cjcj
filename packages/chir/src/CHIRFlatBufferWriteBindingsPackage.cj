package cjcj::chir

import std.collection.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

class CHIRPackageBuilder {
    private let builder: FlatBufferBuilder

    public init(builder: FlatBufferBuilder) {
        this.builder = builder
        builder.StartTable(14)
    }

    public func add_name(name: FlatBufferOffset): Unit {
        builder.AddOffset(0, name)
    }

    public func add_path(path: FlatBufferOffset): Unit {
        builder.AddOffset(1, path)
    }

    public func add_pkgAccessLevel(pkgAccessLevel: UInt8): Unit {
        builder.AddU8(2, pkgAccessLevel, defaultValue: 0u8)
    }

    public func add_types_type(types_type: FlatBufferOffset): Unit {
        builder.AddOffset(3, types_type)
    }

    public func add_types(types: FlatBufferOffset): Unit {
        builder.AddOffset(4, types)
    }

    public func add_values_type(values_type: FlatBufferOffset): Unit {
        builder.AddOffset(5, values_type)
    }

    public func add_values(values: FlatBufferOffset): Unit {
        builder.AddOffset(6, values)
    }

    public func add_exprs_type(exprs_type: FlatBufferOffset): Unit {
        builder.AddOffset(7, exprs_type)
    }

    public func add_exprs(exprs: FlatBufferOffset): Unit {
        builder.AddOffset(8, exprs)
    }

    public func add_defs_type(defs_type: FlatBufferOffset): Unit {
        builder.AddOffset(9, defs_type)
    }

    public func add_defs(defs: FlatBufferOffset): Unit {
        builder.AddOffset(10, defs)
    }

    public func add_packageInitFunc(packageInitFunc: UInt32): Unit {
        builder.AddU32(11, packageInitFunc, defaultValue: 0u32)
    }

    public func add_phase(phase: UInt8): Unit {
        builder.AddU8(12, phase, defaultValue: 0u8)
    }

    public func add_packageLiteralInitFunc(packageLiteralInitFunc: UInt32): Unit {
        builder.AddU32(13, packageLiteralInitFunc, defaultValue: 0u32)
    }

    public func Finish(): FlatBufferOffset {
        return builder.EndTable()
    }
}

func CreateCHIRPackage(builder: FlatBufferBuilder, name: FlatBufferOffset, path: FlatBufferOffset, pkgAccessLevel: UInt8, types_type: FlatBufferOffset, types: FlatBufferOffset, values_type: FlatBufferOffset, values: FlatBufferOffset, exprs_type: FlatBufferOffset, exprs: FlatBufferOffset, defs_type: FlatBufferOffset, defs: FlatBufferOffset, packageInitFunc: UInt32, phase: UInt8, packageLiteralInitFunc: UInt32): FlatBufferOffset {
    let tableBuilder = CHIRPackageBuilder(builder)
    tableBuilder.add_packageLiteralInitFunc(packageLiteralInitFunc)
    tableBuilder.add_packageInitFunc(packageInitFunc)
    tableBuilder.add_defs(defs)
    tableBuilder.add_defs_type(defs_type)
    tableBuilder.add_exprs(exprs)
    tableBuilder.add_exprs_type(exprs_type)
    tableBuilder.add_values(values)
    tableBuilder.add_values_type(values_type)
    tableBuilder.add_types(types)
    tableBuilder.add_types_type(types_type)
    tableBuilder.add_path(path)
    tableBuilder.add_name(name)
    tableBuilder.add_phase(phase)
    tableBuilder.add_pkgAccessLevel(pkgAccessLevel)
    return tableBuilder.Finish()
}

func CreateCHIRPackageDirect(builder: FlatBufferBuilder, name: Option<String>, path: Option<String>, pkgAccessLevel: UInt8, types_type: Option<ArrayList<UInt8>>, types: Option<ArrayList<FlatBufferOffset>>, values_type: Option<ArrayList<UInt8>>, values: Option<ArrayList<FlatBufferOffset>>, exprs_type: Option<ArrayList<UInt8>>, exprs: Option<ArrayList<FlatBufferOffset>>, defs_type: Option<ArrayList<UInt8>>, defs: Option<ArrayList<FlatBufferOffset>>, packageInitFunc: UInt32, phase: UInt8, packageLiteralInitFunc: UInt32): FlatBufferOffset {
    let nameOffset = if (let Some(value) <- name) { builder.CreateSharedString(value) } else { 0u32 }
    let pathOffset = if (let Some(value) <- path) { builder.CreateSharedString(value) } else { 0u32 }
    let types_typeOffset = if (let Some(value) <- types_type) { builder.CreateVectorU8(value) } else { 0u32 }
    let typesOffset = if (let Some(value) <- types) { builder.CreateVectorOffsets(value) } else { 0u32 }
    let values_typeOffset = if (let Some(value) <- values_type) { builder.CreateVectorU8(value) } else { 0u32 }
    let valuesOffset = if (let Some(value) <- values) { builder.CreateVectorOffsets(value) } else { 0u32 }
    let exprs_typeOffset = if (let Some(value) <- exprs_type) { builder.CreateVectorU8(value) } else { 0u32 }
    let exprsOffset = if (let Some(value) <- exprs) { builder.CreateVectorOffsets(value) } else { 0u32 }
    let defs_typeOffset = if (let Some(value) <- defs_type) { builder.CreateVectorU8(value) } else { 0u32 }
    let defsOffset = if (let Some(value) <- defs) { builder.CreateVectorOffsets(value) } else { 0u32 }
    return CreateCHIRPackage(builder, nameOffset, pathOffset, pkgAccessLevel, types_typeOffset, typesOffset, values_typeOffset, valuesOffset, exprs_typeOffset, exprsOffset, defs_typeOffset, defsOffset, packageInitFunc, phase, packageLiteralInitFunc)
}
