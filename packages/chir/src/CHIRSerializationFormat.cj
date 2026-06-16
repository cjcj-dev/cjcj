package cangjie_compiler::chir

import std.collection.*
import std.convert.*

let CHIR_TEXT_HEADER_V1: String = "CHIR-TEXT\t1"
let CHIR_TEXT_HEADER_V2: String = "CHIR-TEXT\t2"
let CHIR_FIELD_SEPARATOR: String = "|"
let CHIR_LIST_SEPARATOR: String = ","

func CHIRWireEncodeField(value: String): String {
    return value.replace("\\", "\\\\").replace("|", "\\p").replace("\n", "\\n").replace("\r", "\\r")
        .replace(",", "\\c").replace("\t", "\\t")
}

func CHIRWireDecodeField(value: String): String {
    var builder = StringBuilder()
    let bytes = value.toArray()
    var idx: Int64 = 0
    while (idx < bytes.size) {
        if (bytes[idx] == b'\\' && idx + 1 < bytes.size) {
            let next = bytes[idx + 1]
            if (next == b'p') {
                builder.append("|")
            } else if (next == b'n') {
                builder.append("\n")
            } else if (next == b'r') {
                builder.append("\r")
            } else if (next == b'c') {
                builder.append(",")
            } else if (next == b't') {
                builder.append("\t")
            } else {
                builder.append(String.fromUtf8([next]))
            }
            idx += 2
        } else {
            builder.append(String.fromUtf8([bytes[idx]]))
            idx++
        }
    }
    return builder.toString()
}

func CHIRWireJoinFields(fields: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (field in fields) {
        encoded.add(CHIRWireEncodeField(field))
    }
    return JoinStrings(encoded, CHIR_FIELD_SEPARATOR)
}

func CHIRWireSplitFields(line: String): ArrayList<String> {
    return CHIRWireSplit(line, b'|')
}

func CHIRWireJoinList(values: ArrayList<String>): String {
    let encoded = ArrayList<String>()
    for (value in values) {
        encoded.add(CHIRWireEncodeField(value))
    }
    return JoinStrings(encoded, CHIR_LIST_SEPARATOR)
}

func CHIRWireSplitList(value: String): ArrayList<String> {
    if (value.isEmpty()) {
        return ArrayList<String>()
    }
    return CHIRWireSplit(value, b',')
}

func CHIRWireSplit(value: String, separator: UInt8): ArrayList<String> {
    let out = ArrayList<String>()
    var builder = StringBuilder()
    let bytes = value.toArray()
    var idx: Int64 = 0
    var escaped = false
    while (idx < bytes.size) {
        let byte = bytes[idx]
        if (escaped) {
            builder.append("\\")
            builder.append(String.fromUtf8([byte]))
            escaped = false
        } else if (byte == b'\\') {
            escaped = true
        } else if (byte == separator) {
            out.add(CHIRWireDecodeField(builder.toString()))
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
        idx++
    }
    if (escaped) {
        builder.append("\\")
    }
    out.add(CHIRWireDecodeField(builder.toString()))
    return out
}

func CHIRBoolToWire(value: Bool): String {
    return if (value) { "1" } else { "0" }
}

func CHIRWireToBool(value: String): Bool {
    return value == "1" || value == "true"
}

func CHIRSafeI64(value: String): Int64 {
    if (value.isEmpty()) {
        return 0
    }
    return Int64.parse(value)
}

func CHIRSafeU64(value: String): UInt64 {
    if (value.isEmpty()) {
        return 0u64
    }
    return UInt64.parse(value)
}

func CHIRSafeU32(value: String): UInt32 {
    if (value.isEmpty()) {
        return 0u32
    }
    return UInt32.parse(value)
}

func CHIRLineFields(tag: String): ArrayList<String> {
    let fields = ArrayList<String>()
    fields.add(tag)
    return fields
}

func CHIRValueId(value: Value): String {
    return value.nodeId.toString()
}

func CHIRBaseId(base: Base): String {
    return base.nodeId.toString()
}

func CHIRSerializeDebugLocation(loc: DebugLocation): String {
    let fields = ArrayList<String>()
    fields.add(loc.fileId.toString())
    fields.add(loc.line.toString())
    fields.add(loc.column.toString())
    fields.add(loc.length.toString())
    return CHIRWireJoinFields(fields)
}

func CHIRParseDebugLocation(value: String): DebugLocation {
    let fields = CHIRWireSplitFields(value)
    if (fields.size < 4) {
        return DebugLocation()
    }
    return DebugLocation(CHIRSafeU32(fields[0]), CHIRSafeU32(fields[1]), CHIRSafeU32(fields[2]),
        length: CHIRSafeU32(fields[3]))
}

func CHIRSerializeAttributes(base: Base): String {
    let parts = ArrayList<String>()
    for (attr in CHIRKnownAttributes()) {
        if (base.TestAttr(attr)) {
            parts.add(AttributeIndex(attr).toString())
        }
    }
    return CHIRWireJoinList(parts)
}

func CHIRApplyBaseInfo(base: Base, locText: String, attrText: String, annotationText!: String = ""): Unit {
    if (!locText.isEmpty()) {
        base.SetDebugLocation(CHIRParseDebugLocation(locText))
    }
    CHIRApplyBaseAnnotations(base, annotationText)
    for (attrIndex in CHIRWireSplitList(attrText)) {
        if (attrIndex.isEmpty()) {
            continue
        }
        base.EnableAttr(CHIRAttributeFromIndex(CHIRSafeI64(attrIndex)))
    }
}

func CHIRSerializeBaseAnnotations(base: Base): String {
    return base.GetAnno().ToString()
}

func CHIRApplyBaseAnnotations(base: Base, value: String): Unit {
    if (value.isEmpty()) {
        return
    }
    base.GetAnno().Clear()
    for (rawLine in value.split("\n")) {
        let line = rawLine
        if (!line.startsWith("@")) {
            continue
        }
        if (let Some(openPos) <- line.indexOf("(")) {
            if (let Some(closePos) <- line.lastIndexOf(")")) {
                if (openPos > 1 && closePos > openPos) {
                    base.SetAnnotation(line[1..openPos], line[openPos + 1..closePos])
                }
            }
        }
    }
}

func CHIRKnownAttributes(): ArrayList<Attribute> {
    let attrs = ArrayList<Attribute>()
    attrs.add(Attribute.ABSTRACT)
    attrs.add(Attribute.ANNOTATION)
    attrs.add(Attribute.BOXED)
    attrs.add(Attribute.BUILTIN)
    attrs.add(Attribute.C)
    attrs.add(Attribute.CFFI_WRAPPER)
    attrs.add(Attribute.COMPILE_TIME_VALUE)
    attrs.add(Attribute.CONST)
    attrs.add(Attribute.EXTERN)
    attrs.add(Attribute.FAST_NATIVE)
    attrs.add(Attribute.FOREIGN)
    attrs.add(Attribute.GENERIC_INSTANTIATED)
    attrs.add(Attribute.IMPLICIT_ADD)
    attrs.add(Attribute.IMPORTED)
    attrs.add(Attribute.INLINED)
    attrs.add(Attribute.MUT)
    attrs.add(Attribute.NO_SIDE_EFFECT)
    attrs.add(Attribute.OPERATOR)
    attrs.add(Attribute.PREVIOUSLY_DESERIALIZED)
    attrs.add(Attribute.PRIVATE)
    attrs.add(Attribute.PROTECTED)
    attrs.add(Attribute.PUBLIC)
    attrs.add(Attribute.READONLY)
    attrs.add(Attribute.STATIC)
    attrs.add(Attribute.SRC_CODE_IMPORTED)
    attrs.add(Attribute.THIN)
    return attrs
}

func CHIRAttributeFromIndex(index: Int64): Attribute {
    return match (index) {
        case 0 => Attribute.ABSTRACT
        case 1 => Attribute.ANNOTATION
        case 2 => Attribute.BOXED
        case 3 => Attribute.BUILTIN
        case 4 => Attribute.C
        case 5 => Attribute.CFFI_WRAPPER
        case 6 => Attribute.COMPILE_TIME_VALUE
        case 7 => Attribute.CONST
        case 8 => Attribute.EXTERN
        case 9 => Attribute.FAST_NATIVE
        case 10 => Attribute.FOREIGN
        case 11 => Attribute.GENERIC_INSTANTIATED
        case 12 => Attribute.IMPLICIT_ADD
        case 13 => Attribute.IMPORTED
        case 14 => Attribute.INLINED
        case 15 => Attribute.MUT
        case 16 => Attribute.NO_SIDE_EFFECT
        case 17 => Attribute.OPERATOR
        case 18 => Attribute.PREVIOUSLY_DESERIALIZED
        case 19 => Attribute.PRIVATE
        case 20 => Attribute.PROTECTED
        case 21 => Attribute.PUBLIC
        case 22 => Attribute.READONLY
        case 23 => Attribute.STATIC
        case 24 => Attribute.SRC_CODE_IMPORTED
        case _ => Attribute.THIN
    }
}

func CHIRAccessLevelFromIndex(index: Int64): AccessLevel {
    return match (index) {
        case 1 => AccessLevel.INTERNAL
        case 2 => AccessLevel.PROTECTED
        case 3 => AccessLevel.PUBLIC
        case _ => AccessLevel.INVALID
    }
}

func CHIRFuncKindFromIndex(index: Int64): FuncKind {
    return match (index) {
        case 1 => FuncKind.GETTER
        case 2 => FuncKind.SETTER
        case 3 => FuncKind.LAMBDA
        case 4 => FuncKind.CLASS_CONSTRUCTOR
        case 5 => FuncKind.PRIMAL_CLASS_CONSTRUCTOR
        case 6 => FuncKind.STRUCT_CONSTRUCTOR
        case 7 => FuncKind.PRIMAL_STRUCT_CONSTRUCTOR
        case 8 => FuncKind.GLOBALVAR_INIT
        case 9 => FuncKind.FINALIZER
        case 10 => FuncKind.MAIN_ENTRY
        case 11 => FuncKind.ANNOFACTORY_FUNC
        case 12 => FuncKind.MACRO_FUNC
        case 13 => FuncKind.DEFAULT_PARAMETER_FUNC
        case 14 => FuncKind.INSTANCEVAR_INIT
        case _ => FuncKind.DEFAULT
    }
}

func CHIRExprKindFromIndex(index: Int64): ExprKind {
    return match (index) {
        case 1 => ExprKind.GOTO
        case 2 => ExprKind.BRANCH
        case 3 => ExprKind.MULTIBRANCH
        case 4 => ExprKind.EXIT
        case 5 => ExprKind.APPLY_WITH_EXCEPTION
        case 6 => ExprKind.INVOKE_WITH_EXCEPTION
        case 7 => ExprKind.INVOKESTATIC_WITH_EXCEPTION
        case 8 => ExprKind.RAISE_EXCEPTION
        case 9 => ExprKind.INT_OP_WITH_EXCEPTION
        case 10 => ExprKind.SPAWN_WITH_EXCEPTION
        case 11 => ExprKind.TYPECAST_WITH_EXCEPTION
        case 12 => ExprKind.INTRINSIC_WITH_EXCEPTION
        case 13 => ExprKind.ALLOCATE_WITH_EXCEPTION
        case 14 => ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION
        case 15 => ExprKind.NEG
        case 16 => ExprKind.NOT
        case 17 => ExprKind.BITNOT
        case 18 => ExprKind.ADD
        case 19 => ExprKind.SUB
        case 20 => ExprKind.MUL
        case 21 => ExprKind.DIV
        case 22 => ExprKind.MOD
        case 23 => ExprKind.EXP
        case 24 => ExprKind.LSHIFT
        case 25 => ExprKind.RSHIFT
        case 26 => ExprKind.BITAND
        case 27 => ExprKind.BITOR
        case 28 => ExprKind.BITXOR
        case 29 => ExprKind.LT
        case 30 => ExprKind.GT
        case 31 => ExprKind.LE
        case 32 => ExprKind.GE
        case 33 => ExprKind.EQUAL
        case 34 => ExprKind.NOTEQUAL
        case 35 => ExprKind.AND
        case 36 => ExprKind.OR
        case 37 => ExprKind.ALLOCATE
        case 38 => ExprKind.LOAD
        case 39 => ExprKind.STORE
        case 40 => ExprKind.GET_ELEMENT_REF
        case 41 => ExprKind.GET_ELEMENT_BY_NAME
        case 42 => ExprKind.STORE_ELEMENT_REF
        case 43 => ExprKind.STORE_ELEMENT_BY_NAME
        case 44 => ExprKind.FORIN_RANGE
        case 45 => ExprKind.FORIN_ITER
        case 46 => ExprKind.FORIN_CLOSED_RANGE
        case 47 => ExprKind.LAMBDA
        case 48 => ExprKind.CONSTANT
        case 49 => ExprKind.DEBUGEXPR
        case 50 => ExprKind.TUPLE
        case 51 => ExprKind.FIELD
        case 52 => ExprKind.FIELD_BY_NAME
        case 53 => ExprKind.APPLY
        case 54 => ExprKind.INVOKE
        case 55 => ExprKind.INVOKESTATIC
        case 56 => ExprKind.INSTANCEOF
        case 57 => ExprKind.TYPECAST
        case 58 => ExprKind.GET_EXCEPTION
        case 59 => ExprKind.RAW_ARRAY_ALLOCATE
        case 60 => ExprKind.RAW_ARRAY_LITERAL_INIT
        case 61 => ExprKind.RAW_ARRAY_INIT_BY_VALUE
        case 62 => ExprKind.VARRAY
        case 63 => ExprKind.VARRAY_BUILDER
        case 64 => ExprKind.INTRINSIC
        case 65 => ExprKind.SPAWN
        case 66 => ExprKind.GET_INSTANTIATE_VALUE
        case 67 => ExprKind.BOX
        case 68 => ExprKind.UNBOX
        case 69 => ExprKind.TRANSFORM_TO_GENERIC
        case 70 => ExprKind.TRANSFORM_TO_CONCRETE
        case 71 => ExprKind.UNBOX_TO_REF
        case 72 => ExprKind.GET_RTTI
        case 73 => ExprKind.GET_RTTI_STATIC
        case _ => ExprKind.INVALID
    }
}

func CHIRSerializeAnnoInfo(info: AnnoInfo): String {
    return CHIRWireJoinList(info.GetAnnotations())
}

func CHIRApplyAnnoInfo(info: AnnoInfo, value: String): Unit {
    info.Clear()
    for (annotation in CHIRWireSplitList(value)) {
        if (!annotation.isEmpty()) {
            info.Add(annotation)
        }
    }
}

func CHIRSerializeType(ty: Type): String {
    if (ty.IsTuple()) {
        if (let Some(tupleTy) <- (ty as TupleType)) {
            let args = ArrayList<String>()
            for (argTy in tupleTy.GetTypeArgs()) {
                args.add(CHIRSerializeType(argTy))
            }
            let fields = ArrayList<String>()
            fields.add("tuple")
            fields.add(CHIRWireJoinList(args))
            return CHIRWireJoinFields(fields)
        }
    }
    if (ty.IsFunc()) {
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = ArrayList<String>()
            for (paramTy in funcTy.GetParamTypes()) {
                params.add(CHIRSerializeType(paramTy))
            }
            let fields = ArrayList<String>()
            fields.add("func")
            fields.add(CHIRBoolToWire(funcTy.IsCFunc()))
            fields.add(CHIRBoolToWire(funcTy.HasVarArg()))
            fields.add(CHIRSerializeType(funcTy.GetReturnType()))
            fields.add(CHIRWireJoinList(params))
            return CHIRWireJoinFields(fields)
        }
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        let fields = ArrayList<String>()
        fields.add("rawarray")
        fields.add(CHIRSerializeType(rawArrayTy.GetElementType()))
        return CHIRWireJoinFields(fields)
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        let fields = ArrayList<String>()
        fields.add("varray")
        fields.add(CHIRSerializeType(varrayTy.GetElementType()))
        fields.add(varrayTy.size.toString())
        return CHIRWireJoinFields(fields)
    }
    if (let Some(refTy) <- (ty as RefType)) {
        let fields = ArrayList<String>()
        fields.add("ref")
        fields.add(CHIRSerializeType(refTy.GetBaseType()))
        return CHIRWireJoinFields(fields)
    }
    if (let Some(boxTy) <- (ty as BoxType)) {
        let fields = ArrayList<String>()
        fields.add("box")
        fields.add(CHIRSerializeType(boxTy.GetBaseType()))
        return CHIRWireJoinFields(fields)
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        let bounds = ArrayList<String>()
        for (boundTy in genericTy.GetUpperBounds()) {
            bounds.add(CHIRSerializeType(boundTy))
        }
        let fields = ArrayList<String>()
        fields.add("generic")
        fields.add(genericTy.GetIdentifier())
        fields.add(genericTy.GetSrcCodeIdentifier())
        fields.add(CHIRWireJoinList(bounds))
        return CHIRWireJoinFields(fields)
    }
    if (let Some(thisTy) <- (ty as ThisType)) {
        let fields = ArrayList<String>()
        fields.add("this")
        fields.add(thisTy.name)
        return CHIRWireJoinFields(fields)
    }
    if (let Some(customTy) <- (ty as CustomType)) {
        let args = ArrayList<String>()
        for (argTy in customTy.GetGenericArgs()) {
            args.add(CHIRSerializeType(argTy))
        }
        let fields = ArrayList<String>()
        fields.add(CHIRCustomTypeKindName(customTy.GetCustomTypeDef()))
        fields.add(customTy.GetCustomTypeDef().GetPackageName())
        fields.add(customTy.GetCustomTypeDef().GetIdentifier())
        fields.add(CHIRWireJoinList(args))
        return CHIRWireJoinFields(fields)
    }
    let fields = ArrayList<String>()
    fields.add("builtin")
    fields.add(TypeKindIndex(ty.GetTypeKind()).toString())
    return CHIRWireJoinFields(fields)
}

func CHIRParseType(value: String, builder: CHIRBuilder, customDefs: HashMap<String, CustomTypeDef>): Type {
    if (value.isEmpty()) {
        return builder.context.GetInvalidTy()
    }
    let fields = CHIRWireSplitFields(value)
    if (fields.isEmpty()) {
        return builder.context.GetInvalidTy()
    }
    return match (fields[0]) {
        case "builtin" => CHIRBuiltinTypeFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 1)), builder)
        case "tuple" => builder.context.GetTupleTy(CHIRParseTypeList(CHIRFieldAt(fields, 1), builder, customDefs))
        case "func" => CHIRParseFuncType(fields, builder, customDefs)
        case "rawarray" => builder.context.GetRawArrayTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "varray" => builder.context.GetVArrayTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs),
            CHIRSafeU64(CHIRFieldAt(fields, 2)))
        case "ref" => builder.context.GetRefTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "box" => builder.context.GetBoxTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "generic" => CHIRParseGenericType(fields, builder, customDefs)
        case "this" => ThisType(name: CHIRFieldAt(fields, 1))
        case "struct" => CHIRParseCustomType(fields, builder, customDefs)
        case "class" => CHIRParseCustomType(fields, builder, customDefs)
        case "enum" => CHIRParseCustomType(fields, builder, customDefs)
        case _ => CHIRParseLegacyType(value, builder)
    }
}

func CHIRParseFuncType(fields: ArrayList<String>, builder: CHIRBuilder,
    customDefs: HashMap<String, CustomTypeDef>): FuncType {
    let returnTy = CHIRParseType(CHIRFieldAt(fields, 3), builder, customDefs)
    let paramTys = CHIRParseTypeList(CHIRFieldAt(fields, 4), builder, customDefs)
    return builder.context.GetFuncTy(paramTys, returnTy, hasVarLenParam: CHIRWireToBool(CHIRFieldAt(fields, 2)),
        isCFunc: CHIRWireToBool(CHIRFieldAt(fields, 1)))
}

func CHIRParseGenericType(fields: ArrayList<String>, builder: CHIRBuilder,
    customDefs: HashMap<String, CustomTypeDef>): GenericType {
    let genericTy = builder.context.GetGenericTy(CHIRFieldAt(fields, 1))
    genericTy.SetSrcCodeIdentifier(CHIRFieldAt(fields, 2))
    let bounds = CHIRParseTypeList(CHIRFieldAt(fields, 3), builder, customDefs)
    if (!bounds.isEmpty()) {
        genericTy.SetUpperBounds(bounds)
    }
    return genericTy
}

func CHIRParseCustomType(fields: ArrayList<String>, builder: CHIRBuilder,
    customDefs: HashMap<String, CustomTypeDef>): Type {
    let kind = CHIRFieldAt(fields, 0)
    let packageName = CHIRFieldAt(fields, 1)
    let identifier = CHIRFieldAt(fields, 2)
    let args = CHIRParseTypeList(CHIRFieldAt(fields, 3), builder, customDefs)
    let key = CHIRCustomDefKey(kind, packageName, identifier)
    let def = if (let Some(found) <- customDefs.get(key)) {
        found
    } else {
        CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
    }
    if (kind == "struct") {
        if (let Some(structDef) <- (def as StructDef)) {
            return builder.context.GetStructTy(structDef, args)
        }
    } else if (kind == "class") {
        if (let Some(classDef) <- (def as ClassDef)) {
            return builder.context.GetClassTy(classDef, args)
        }
    } else if (kind == "enum") {
        if (let Some(enumDef) <- (def as EnumDef)) {
            return builder.context.GetEnumTy(enumDef, args)
        }
    }
    return builder.context.GetInvalidTy()
}

func CHIRParseTypeList(value: String, builder: CHIRBuilder, customDefs: HashMap<String, CustomTypeDef>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (item in CHIRWireSplitList(value)) {
        if (!item.isEmpty()) {
            out.add(CHIRParseType(item, builder, customDefs))
        }
    }
    return out
}

func CHIRBuiltinTypeFromIndex(index: Int64, builder: CHIRBuilder): Type {
    return match (index) {
        case 1 => builder.context.GetInt8Ty()
        case 2 => builder.context.GetInt16Ty()
        case 3 => builder.context.GetInt32Ty()
        case 4 => builder.context.GetInt64Ty()
        case 5 => builder.context.GetIntNativeTy()
        case 6 => builder.context.GetUInt8Ty()
        case 7 => builder.context.GetUInt16Ty()
        case 8 => builder.context.GetUInt32Ty()
        case 9 => builder.context.GetUInt64Ty()
        case 10 => builder.context.GetUIntNativeTy()
        case 11 => builder.context.GetFloat16Ty()
        case 12 => builder.context.GetFloat32Ty()
        case 13 => builder.context.GetFloat64Ty()
        case 14 => builder.context.GetRuneTy()
        case 15 => builder.context.GetBoolTy()
        case 16 => builder.context.GetUnitTy()
        case 17 => builder.context.GetNothingType()
        case 18 => builder.context.GetVoidTy()
        case 27 => builder.context.GetCStringTy()
        case _ => builder.context.GetInvalidTy()
    }
}

func CHIRParseLegacyType(text: String, builder: CHIRBuilder): Type {
    return match (text) {
        case "Invalid" => builder.context.GetInvalidTy()
        case "Int8" => builder.context.GetInt8Ty()
        case "Int16" => builder.context.GetInt16Ty()
        case "Int32" => builder.context.GetInt32Ty()
        case "Int64" => builder.context.GetInt64Ty()
        case "IntNative" => builder.context.GetIntNativeTy()
        case "UInt8" => builder.context.GetUInt8Ty()
        case "UInt16" => builder.context.GetUInt16Ty()
        case "UInt32" => builder.context.GetUInt32Ty()
        case "UInt64" => builder.context.GetUInt64Ty()
        case "UIntNative" => builder.context.GetUIntNativeTy()
        case "Float16" => builder.context.GetFloat16Ty()
        case "Float32" => builder.context.GetFloat32Ty()
        case "Float64" => builder.context.GetFloat64Ty()
        case "Rune" => builder.context.GetRuneTy()
        case "Bool" => builder.context.GetBoolTy()
        case "Unit" => builder.context.GetUnitTy()
        case "Nothing" => builder.context.GetNothingType()
        case "Void" => builder.context.GetVoidTy()
        case "CString" => builder.context.GetCStringTy()
        case _ => builder.context.GetInvalidTy()
    }
}

func CHIRCustomDefKey(kind: String, packageName: String, identifier: String): String {
    return kind + ":" + packageName + ":" + identifier
}

func CHIRCustomTypeKindName(def: CustomTypeDef): String {
    if ((def as StructDef).isSome()) {
        return "struct"
    }
    if ((def as ClassDef).isSome()) {
        return "class"
    }
    if ((def as EnumDef).isSome()) {
        return "enum"
    }
    return "extend"
}

func CHIRCreateDetachedCustomDef(kind: String, packageName: String, identifier: String, builder: CHIRBuilder,
    customDefs: HashMap<String, CustomTypeDef>): CustomTypeDef {
    let def = if (kind == "struct") {
        builder.CreateStructDef(packageName, identifier)
    } else if (kind == "class") {
        builder.CreateClassDef(packageName, identifier)
    } else if (kind == "enum") {
        builder.CreateEnumDef(packageName, identifier)
    } else {
        builder.CreateExtendDef(packageName, identifier)
    }
    customDefs[CHIRCustomDefKey(kind, packageName, identifier)] = def
    return def
}

func CHIRFieldAt(fields: ArrayList<String>, index: Int64): String {
    if (index < fields.size) {
        return fields[index]
    }
    return ""
}
