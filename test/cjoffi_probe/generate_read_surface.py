#!/usr/bin/env python3
"""Generate official/manual CJO walkers and the schema-field inventory.

The generator consumes the compiler's authoritative ModuleFormat.fbs.  It does
not modify the compiler or SDK tree; all generated files live in this probe.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


SCALARS = {
    "bool": (1, False),
    "int8": (1, True), "uint8": (1, False),
    "int16": (2, True), "uint16": (2, False),
    "int32": (4, True), "uint32": (4, False),
    "int64": (8, True), "uint64": (8, False),
    "float32": (4, False), "float64": (8, False),
}

# Audited against the live handwritten reads in FrontendModel.cj.  These are
# source-schema fields, so a union plus its generated discriminator is one item.
UNREAD = {
    "Position.ignore",
    "Constraint.begin", "Constraint.end",
    "Int8Value.val", "UInt8Value.val", "Int16Value.val", "UInt16Value.val",
    "Int32Value.val", "UInt32Value.val", "Int64Value.val", "UInt64Value.val",
    "Float32Value.val", "Float64Value.val", "ArrayValue.val",
    "CompositeValueIndex.idx", "MemberValue.field", "MemberValue.type",
    "MemberValue.value", "CompositeValue.type", "CompositeValue.fields",
    "AutoDiffInfo.isDiff", "AutoDiffInfo.isAdj", "AutoDiffInfo.primal",
    "AutoDiffInfo.excepts", "AutoDiffInfo.includes", "AutoDiffInfo.stage",
    "ClassInfo.adInfo", "ClassInfo.isAnno", "StructInfo.adInfo",
    "EnumInfo.adInfo", "EnumInfo.ellipsisPos", "VarInfo.value",
    "FuncInfo.adInfo", "Pattern.values",
    "CjoVersion.major_num", "CjoVersion.minor_num", "CjoVersion.patch_num",
    "Package.version", "Package.cjoVersion", "Package.allValues",
    "Package.moduleName",
}


@dataclass
class Field:
    owner: str
    name: str
    type_name: str
    default: str | None
    line: int
    field_id: int = -1
    slot: int = -1
    struct_offset: int = -1

    @property
    def full_name(self) -> str:
        return f"{self.owner}.{self.name}"


@dataclass
class Block:
    kind: str
    name: str
    fields: list[Field]
    align: int = 1
    size: int = 0


def strip_comments(text: str) -> str:
    return re.sub(r"//[^\n]*", lambda match: " " * len(match.group(0)), text)


def parse_schema(path: Path):
    original = path.read_text()
    text = strip_comments(original)
    line_for = lambda offset: original.count("\n", 0, offset) + 1

    enums: dict[str, list[str]] = {}
    for match in re.finditer(r"\benum\s+(\w+)\s*:\s*\w+\s*\{(.*?)\}", text, re.S):
        names = []
        for item in match.group(2).split(","):
            name = item.strip().split("=")[0].strip()
            if name:
                names.append(name)
        enums[match.group(1)] = names

    unions: dict[str, list[str]] = {}
    for match in re.finditer(r"\bunion\s+(\w+)\s*\{(.*?)\}", text, re.S):
        variants = []
        for item in match.group(2).split(","):
            item = item.strip()
            if not item:
                continue
            variants.append(item.split(":")[-1].strip())
        unions[match.group(1)] = variants

    blocks: dict[str, Block] = {}
    all_fields: list[Field] = []
    for match in re.finditer(r"\b(table|struct)\s+(\w+)\s*\{(.*?)\}", text, re.S):
        kind, name, body = match.group(1), match.group(2), match.group(3)
        fields = []
        for fm in re.finditer(r"\b(\w+)\s*:\s*([^;]+);", body):
            raw_type = fm.group(2).strip()
            raw_type = re.sub(r"\s*\(required\)\s*", "", raw_type)
            default = None
            if "=" in raw_type:
                raw_type, default = (part.strip() for part in raw_type.split("=", 1))
            absolute = match.start(3) + fm.start()
            field = Field(name, fm.group(1), raw_type, default, line_for(absolute))
            field.field_id = len(all_fields)
            fields.append(field)
            all_fields.append(field)
        blocks[name] = Block(kind, name, fields)

    if len(blocks) != 72 or len(all_fields) != 217:
        raise SystemExit(f"schema shape changed: blocks={len(blocks)} fields={len(all_fields)}")

    for block in blocks.values():
        if block.kind == "table":
            slot = 4
            for field in block.fields:
                field.slot = slot
                slot += 4 if base_type(field.type_name) in unions else 2

    compute_struct_layouts(blocks, enums)
    return original, blocks, all_fields, enums, unions


def base_type(type_name: str) -> str:
    return type_name[1:-1].strip() if type_name.startswith("[") else type_name


def is_vector(type_name: str) -> bool:
    return type_name.startswith("[")


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def compute_struct_layouts(blocks: dict[str, Block], enums: dict[str, list[str]]) -> None:
    pending = {name for name, block in blocks.items() if block.kind == "struct"}
    while pending:
        progressed = False
        for name in list(pending):
            block = blocks[name]
            layout = []
            okay = True
            for field in block.fields:
                ty = base_type(field.type_name)
                if ty in SCALARS or ty in enums:
                    size = SCALARS.get(ty, (1, False))[0]
                    alignment = size
                elif ty in blocks and blocks[ty].kind == "struct" and ty not in pending:
                    size, alignment = blocks[ty].size, blocks[ty].align
                else:
                    okay = False
                    break
                layout.append((field, size, alignment))
            if not okay:
                continue
            offset = 0
            block.align = max((alignment for _, _, alignment in layout), default=1)
            for field, size, alignment in layout:
                offset = align_up(offset, alignment)
                field.struct_offset = offset
                offset += size
            block.size = align_up(offset, block.align)
            pending.remove(name)
            progressed = True
        if not progressed:
            raise SystemExit(f"cannot resolve struct layouts: {sorted(pending)}")


def cpp_default(field: Field, enums: dict[str, list[str]]) -> int:
    ty = base_type(field.type_name)
    if field.default is None:
        return 0
    if ty == "bool":
        return 1 if field.default == "true" else 0
    if ty in enums:
        return enums[ty].index(field.default)
    return int(field.default, 0)


def selected(field: Field) -> bool:
    return field.full_name not in UNREAD


def emit_official(blocks, fields, enums, unions) -> str:
    out = ["// Generated by generate_read_surface.py; do not edit.", ""]
    reachable = reachable_blocks(blocks, unions)
    for name in reachable:
        out.append(f"void CJOFWalkOfficial_{name}(const PackageFormat::{name} *, CJOFReadSurfaceFingerprint &);")
    out.append("")
    for name in reachable:
        block = blocks[name]
        out.append(f"void CJOFWalkOfficial_{name}(const PackageFormat::{name} *value, CJOFReadSurfaceFingerprint &out)")
        out.append("{")
        out.append("    if (value == nullptr) return;")
        for field in block.fields:
            if not selected(field):
                continue
            emit_official_field(out, field, blocks, enums, unions)
        out.append("}")
        out.append("")
    return "\n".join(out)


def emit_official_field(out, field, blocks, enums, unions):
    fid = field.field_id
    ty = base_type(field.type_name)
    getter = field.name
    out.append(f"    CJOFReadSurfaceBegin(out, {fid}); // {field.full_name}")
    if is_vector(field.type_name):
        out.append(f"    if (const auto *items = value->{getter}()) {{")
        out.append(f"        CJOFReadSurfaceAdd(out, {fid}, 1); CJOFReadSurfaceAdd(out, {fid}, items->size());")
        if ty == "string":
            out.append(f"        for (const auto *item : *items) CJOFReadSurfaceString(out, {fid}, item);")
        elif ty in SCALARS or ty in enums:
            out.append(f"        for (auto item : *items) CJOFReadSurfaceAdd(out, {fid}, static_cast<uint64_t>(item));")
        elif ty in blocks:
            out.append(f"        for (const auto *item : *items) {{ CJOFReadSurfaceAdd(out, {fid}, item != nullptr); CJOFWalkOfficial_{ty}(item, out); }}")
        else:
            raise SystemExit(f"unsupported official vector {field.full_name}: {ty}")
        out.append("    } else {")
        out.append(f"        CJOFReadSurfaceAdd(out, {fid}, 0); CJOFReadSurfaceAdd(out, {fid}, 0);")
        out.append("    }")
    elif ty == "string":
        out.append(f"    CJOFReadSurfaceString(out, {fid}, value->{getter}());")
    elif ty in SCALARS or ty in enums:
        out.append(f"    CJOFReadSurfaceAdd(out, {fid}, static_cast<uint64_t>(value->{getter}()));")
    elif ty in unions:
        out.append(f"    const auto unionType = static_cast<unsigned int>(value->{getter}_type());")
        out.append(f"    CJOFReadSurfaceAdd(out, {fid}, unionType);")
        out.append("    switch (unionType) {")
        for index, variant in enumerate(unions[ty], 1):
            out.append(f"        case {index}: {{ const auto *item = value->{getter}_as_{variant}(); CJOFReadSurfaceAdd(out, {fid}, item != nullptr); CJOFWalkOfficial_{variant}(item, out); break; }}")
        out.append("        default: break;")
        out.append("    }")
    elif ty in blocks:
        out.append(f"    const auto *item_{fid} = value->{getter}();")
        out.append(f"    CJOFReadSurfaceAdd(out, {fid}, item_{fid} != nullptr);")
        out.append(f"    CJOFWalkOfficial_{ty}(item_{fid}, out);")
    else:
        raise SystemExit(f"unsupported official field {field.full_name}: {ty}")


def emit_manual(blocks, fields, enums, unions) -> str:
    out = ["// Generated by generate_read_surface.py; do not edit.", ""]
    reachable = reachable_blocks(blocks, unions)
    for name in reachable:
        out.append(f"void WalkManual_{name}(const ManualFlatBuffer &, int64_t, ReadSurfaceFingerprint &);")
    out.append("")
    for name in reachable:
        block = blocks[name]
        out.append(f"void WalkManual_{name}(const ManualFlatBuffer &reader, int64_t value, ReadSurfaceFingerprint &out)")
        out.append("{")
        out.append("    if (value < 0) return;")
        for field in block.fields:
            if not selected(field):
                continue
            emit_manual_field(out, field, blocks, enums, unions)
        out.append("}")
        out.append("")
    return "\n".join(out)


def manual_scalar_expr(field, enums, position: str) -> str:
    ty = base_type(field.type_name)
    size, signed = SCALARS.get(ty, (1, False))
    default = cpp_default(field, enums)
    if ty == "bool":
        return f"reader.U8({position}, {default})"
    prefix = "I" if signed else "U"
    return f"reader.{prefix}{size * 8}({position}, {default})"


def emit_manual_field(out, field, blocks, enums, unions):
    fid = field.field_id
    ty = base_type(field.type_name)
    owner = blocks[field.owner]
    if owner.kind == "struct":
        position = f"value + {field.struct_offset}"
        slot_expr = None
    else:
        position = f"reader.TableField(value, {field.slot})"
        slot_expr = position
    out.append(f"    ReadSurfaceBegin(out, {fid}); // {field.full_name}")
    if is_vector(field.type_name):
        out.append(f"    const int64_t vector_{fid} = reader.VectorField(value, {field.slot});")
        out.append(f"    ReadSurfaceAdd(out, {fid}, vector_{fid} >= 0);")
        out.append(f"    const uint64_t count_{fid} = reader.VectorLength(vector_{fid}); ReadSurfaceAdd(out, {fid}, count_{fid});")
        out.append(f"    for (uint64_t i = 0; i < count_{fid}; ++i) {{")
        if ty == "string":
            out.append(f"        ReadSurfaceString(out, {fid}, reader.StringAt(reader.VectorOffsetElement(vector_{fid}, i)));")
        elif ty in SCALARS or ty in enums:
            size, signed = SCALARS.get(ty, (1, False))
            method = ("I" if signed else "U") + str(size * 8)
            out.append(f"        ReadSurfaceAdd(out, {fid}, reader.Vector{method}(vector_{fid}, i));")
        elif ty in blocks:
            if blocks[ty].kind == "struct":
                out.append(f"        const int64_t item = reader.VectorStructElement(vector_{fid}, i, {blocks[ty].size});")
            else:
                out.append(f"        const int64_t item = reader.VectorOffsetElement(vector_{fid}, i);")
            out.append(f"        ReadSurfaceAdd(out, {fid}, item >= 0); WalkManual_{ty}(reader, item, out);")
        else:
            raise SystemExit(f"unsupported manual vector {field.full_name}: {ty}")
        out.append("    }")
    elif ty == "string":
        out.append(f"    ReadSurfaceString(out, {fid}, reader.StringField(value, {field.slot}));")
    elif ty in SCALARS or ty in enums:
        if owner.kind == "table":
            pos = f"reader.TableField(value, {field.slot})"
        else:
            pos = position
        out.append(f"    ReadSurfaceAdd(out, {fid}, {manual_scalar_expr(field, enums, pos)});")
    elif ty in unions:
        type_slot = field.slot
        value_slot = field.slot + 2
        out.append(f"    const uint64_t unionType_{fid} = reader.U8(reader.TableField(value, {type_slot}), 0); ReadSurfaceAdd(out, {fid}, unionType_{fid});")
        out.append(f"    const int64_t unionValue_{fid} = reader.OffsetField(value, {value_slot});")
        out.append(f"    switch (unionType_{fid}) {{")
        for index, variant in enumerate(unions[ty], 1):
            out.append(f"        case {index}: ReadSurfaceAdd(out, {fid}, unionValue_{fid} >= 0); WalkManual_{variant}(reader, unionValue_{fid}, out); break;")
        out.append("        default: break;")
        out.append("    }")
    elif ty in blocks:
        if owner.kind == "struct":
            child = position
        elif blocks[ty].kind == "struct":
            child = f"reader.TableField(value, {field.slot})"
        else:
            child = f"reader.OffsetField(value, {field.slot})"
        out.append(f"    const int64_t item_{fid} = {child}; ReadSurfaceAdd(out, {fid}, item_{fid} >= 0); WalkManual_{ty}(reader, item_{fid}, out);")
    else:
        raise SystemExit(f"unsupported manual field {field.full_name}: {ty}")


def reachable_blocks(blocks, unions):
    selected_names = {field.owner for block in blocks.values() for field in block.fields if selected(field)}
    changed = True
    while changed:
        changed = False
        for name in list(selected_names):
            for field in blocks[name].fields:
                if not selected(field):
                    continue
                ty = base_type(field.type_name)
                targets = unions.get(ty, [ty])
                for target in targets:
                    if target in blocks and target not in selected_names:
                        selected_names.add(target)
                        changed = True
    # Definitions must precede users only via prototypes, so schema order is fine.
    return [name for name in blocks if name in selected_names]


def emit_inventory(fields: list[Field]) -> str:
    lines = ["field_id\tfield\tstatus\tschema_line"]
    for field in fields:
        status = "NOT_READ" if field.full_name in UNREAD else "READ"
        lines.append(f"{field.field_id}\t{field.full_name}\t{status}\t{field.line}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("schema", type=Path)
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--manual", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()
    _, blocks, fields, enums, unions = parse_schema(args.schema)
    if len(UNREAD) != 41:
        raise SystemExit(f"UNREAD audit changed: {len(UNREAD)}")
    unknown = UNREAD - {field.full_name for field in fields}
    if unknown:
        raise SystemExit(f"unknown UNREAD fields: {sorted(unknown)}")
    args.official.write_text(emit_official(blocks, fields, enums, unions))
    args.manual.write_text(emit_manual(blocks, fields, enums, unions))
    args.inventory.write_text(emit_inventory(fields))
    print(f"SUMMARY schema_fields={len(fields)} read={len(fields) - len(UNREAD)} not_read={len(UNREAD)}")


if __name__ == "__main__":
    main()
