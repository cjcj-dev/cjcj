package cangjie_compiler::chir

import std.collection.*
import std.convert.*

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

func CHIRSafeU64(value: String, defaultValue: UInt64): UInt64 {
    if (value.isEmpty()) {
        return defaultValue
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
    let beginPos = loc.GetBeginPos()
    let endPos = loc.GetEndPos()
    fields.add(loc.GetAbsPath())
    fields.add(loc.GetFileID().toString())
    fields.add(beginPos.line.toString())
    fields.add(beginPos.column.toString())
    fields.add(endPos.line.toString())
    fields.add(endPos.column.toString())
    let scopeInfo = ArrayList<String>()
    for (scope in loc.GetScopeInfo()) {
        scopeInfo.add(scope.toString())
    }
    fields.add(CHIRWireJoinList(scopeInfo))
    return CHIRWireJoinFields(fields)
}

func CHIRParseDebugLocation(value: String): DebugLocation {
    let fields = CHIRWireSplitFields(value)
    if (fields.size < 7) {
        return DebugLocation()
    }
    let beginPos = Position(CHIRSafeU32(fields[2]), CHIRSafeU32(fields[3]))
    let endPos = Position(CHIRSafeU32(fields[4]), CHIRSafeU32(fields[5]))
    let scopeInfo = ArrayList<Int64>()
    for (scope in CHIRWireSplitList(fields[6])) {
        scopeInfo.add(CHIRSafeI64(scope))
    }
    return DebugLocation(fields[0], CHIRSafeU32(fields[1]), beginPos, endPos, scopeInfo: scopeInfo)
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

func CHIRSerializeAttributeInfo(info: AttributeInfo): String {
    let parts = ArrayList<String>()
    for (attr in CHIRKnownAttributes()) {
        if (info.Test(attr)) {
            parts.add(AttributeIndex(attr).toString())
        }
    }
    return CHIRWireJoinList(parts)
}

func CHIRApplyAttributeInfo(info: AttributeInfo, value: String): Unit {
    info.Clear()
    for (attrIndex in CHIRWireSplitList(value)) {
        if (attrIndex.isEmpty()) {
            continue
        }
        info.Enable(CHIRAttributeFromIndex(CHIRSafeI64(attrIndex)))
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
    attrs.add(Attribute.STATIC)
    attrs.add(Attribute.PUBLIC)
    attrs.add(Attribute.PRIVATE)
    attrs.add(Attribute.PROTECTED)
    attrs.add(Attribute.ABSTRACT)
    attrs.add(Attribute.VIRTUAL)
    attrs.add(Attribute.OVERRIDE)
    attrs.add(Attribute.REDEF)
    attrs.add(Attribute.SEALED)
    attrs.add(Attribute.FOREIGN)
    attrs.add(Attribute.MUT)
    attrs.add(Attribute.FINAL)
    attrs.add(Attribute.OPERATOR)
    attrs.add(Attribute.READONLY)
    attrs.add(Attribute.CONST)
    attrs.add(Attribute.IMPORTED)
    attrs.add(Attribute.GENERIC_INSTANTIATED)
    attrs.add(Attribute.NO_DEBUG_INFO)
    attrs.add(Attribute.GENERIC)
    attrs.add(Attribute.INTERNAL)
    attrs.add(Attribute.COMPILER_ADD)
    attrs.add(Attribute.NO_REFLECT_INFO)
    attrs.add(Attribute.NO_INLINE)
    attrs.add(Attribute.NON_RECOMPILE)
    attrs.add(Attribute.UNREACHABLE)
    attrs.add(Attribute.NO_SIDE_EFFECT)
    attrs.add(Attribute.COMMON)
    attrs.add(Attribute.SPECIFIC)
    attrs.add(Attribute.SKIP_ANALYSIS)
    attrs.add(Attribute.DESERIALIZED)
    attrs.add(Attribute.INITIALIZER)
    attrs.add(Attribute.UNSAFE)
    attrs.add(Attribute.JAVA_MIRROR)
    attrs.add(Attribute.JAVA_IMPL)
    attrs.add(Attribute.OBJ_C_MIRROR)
    attrs.add(Attribute.HAS_INITED_FIELD)
    attrs.add(Attribute.JAVA_HAS_DEFAULT)
    attrs.add(Attribute.PREVIOUSLY_DESERIALIZED)
    attrs.add(Attribute.ANNOTATION)
    attrs.add(Attribute.BUILTIN)
    attrs.add(Attribute.C)
    attrs.add(Attribute.CFFI_WRAPPER)
    attrs.add(Attribute.COMPILE_TIME_VALUE)
    attrs.add(Attribute.EXTERN)
    attrs.add(Attribute.FAST_NATIVE)
    attrs.add(Attribute.IMPLICIT_ADD)
    attrs.add(Attribute.INLINED)
    attrs.add(Attribute.SRC_CODE_IMPORTED)
    attrs.add(Attribute.THIN)
    return attrs
}

func CHIRAttributeFromIndex(index: Int64): Attribute {
    return match (index) {
        case 0 => Attribute.STATIC
        case 1 => Attribute.PUBLIC
        case 2 => Attribute.PRIVATE
        case 3 => Attribute.PROTECTED
        case 4 => Attribute.ABSTRACT
        case 5 => Attribute.VIRTUAL
        case 6 => Attribute.OVERRIDE
        case 7 => Attribute.REDEF
        case 8 => Attribute.SEALED
        case 9 => Attribute.FOREIGN
        case 10 => Attribute.MUT
        case 11 => Attribute.FINAL
        case 12 => Attribute.OPERATOR
        case 13 => Attribute.READONLY
        case 14 => Attribute.CONST
        case 15 => Attribute.IMPORTED
        case 16 => Attribute.GENERIC_INSTANTIATED
        case 17 => Attribute.NO_DEBUG_INFO
        case 18 => Attribute.GENERIC
        case 19 => Attribute.INTERNAL
        case 20 => Attribute.COMPILER_ADD
        case 21 => Attribute.NO_REFLECT_INFO
        case 22 => Attribute.NO_INLINE
        case 23 => Attribute.NON_RECOMPILE
        case 24 => Attribute.UNREACHABLE
        case 25 => Attribute.NO_SIDE_EFFECT
        case 26 => Attribute.COMMON
        case 27 => Attribute.SPECIFIC
        case 28 => Attribute.SKIP_ANALYSIS
        case 29 => Attribute.DESERIALIZED
        case 30 => Attribute.INITIALIZER
        case 31 => Attribute.UNSAFE
        case 32 => Attribute.JAVA_MIRROR
        case 33 => Attribute.JAVA_IMPL
        case 34 => Attribute.OBJ_C_MIRROR
        case 35 => Attribute.HAS_INITED_FIELD
        case 36 => Attribute.JAVA_HAS_DEFAULT
        case 37 => Attribute.PREVIOUSLY_DESERIALIZED
        case 64 => Attribute.ANNOTATION
        case 66 => Attribute.BUILTIN
        case 67 => Attribute.C
        case 68 => Attribute.CFFI_WRAPPER
        case 69 => Attribute.COMPILE_TIME_VALUE
        case 70 => Attribute.EXTERN
        case 71 => Attribute.FAST_NATIVE
        case 72 => Attribute.IMPLICIT_ADD
        case 73 => Attribute.INLINED
        case 74 => Attribute.SRC_CODE_IMPORTED
        case 75 => Attribute.THIN
        case _ => throw IllegalArgumentException("invalid CHIR attribute index")
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

func CHIRSourceExprFromIndex(index: Int64): SourceExpr {
    return match (index) {
        case 0 => SourceExpr.IF_EXPR
        case 1 => SourceExpr.WHILE_EXPR
        case 2 => SourceExpr.DO_WHILE_EXPR
        case 3 => SourceExpr.MATCH_EXPR
        case 4 => SourceExpr.IF_LET_OR_WHILE_LET
        case 5 => SourceExpr.QUEST
        case 6 => SourceExpr.BINARY
        case 7 => SourceExpr.FOR_IN_EXPR
        case _ => SourceExpr.OTHER
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
        fields.add(rawArrayTy.GetDims().toString())
        return CHIRWireJoinFields(fields)
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        let fields = ArrayList<String>()
        fields.add("varray")
        fields.add(CHIRSerializeType(varrayTy.GetElementType()))
        fields.add(varrayTy.size.toString())
        return CHIRWireJoinFields(fields)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        let fields = ArrayList<String>()
        fields.add("cpointer")
        fields.add(CHIRSerializeType(pointerTy.GetElementType()))
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
        let _ = thisTy
        let fields = ArrayList<String>()
        fields.add("this")
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
        case "rawarray" => builder.context.GetRawArrayTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs),
            dims: CHIRSafeU64(CHIRFieldAt(fields, 2), 1u64))
        case "varray" => builder.context.GetVArrayTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs),
            CHIRSafeU64(CHIRFieldAt(fields, 2)))
        case "cpointer" => builder.context.GetCPointerTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "ref" => builder.context.GetRefTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "box" => builder.context.GetBoxTy(CHIRParseType(CHIRFieldAt(fields, 1), builder, customDefs))
        case "generic" => CHIRParseGenericType(fields, builder, customDefs)
        case "this" => builder.context.GetThisTy()
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
    let genericTy = builder.context.GetGenericTy(CHIRFieldAt(fields, 1), CHIRFieldAt(fields, 2))
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

func CHIRSerializeTypeList(values: ArrayList<Type>): String {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(CHIRSerializeType(value))
    }
    return CHIRWireJoinList(out)
}

func CHIRSerializeGenericTypeList(values: ArrayList<GenericType>): String {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(CHIRSerializeType(value))
    }
    return CHIRWireJoinList(out)
}

func CHIRParseGenericTypeList(value: String, builder: CHIRBuilder,
    customDefs: HashMap<String, CustomTypeDef>): ArrayList<GenericType> {
    let out = ArrayList<GenericType>()
    for (ty in CHIRParseTypeList(value, builder, customDefs)) {
        if (let Some(genericTy) <- (ty as GenericType)) {
            out.add(genericTy)
        }
    }
    return out
}

func CHIRSerializeUInt64List(values: ArrayList<UInt64>): String {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value.toString())
    }
    return CHIRWireJoinList(out)
}

func CHIRParseUInt64List(value: String): ArrayList<UInt64> {
    let out = ArrayList<UInt64>()
    for (item in CHIRWireSplitList(value)) {
        if (!item.isEmpty()) {
            out.add(UInt64.parse(item))
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


func CHIRIntrinsicKindFromName(name: String): IntrinsicKind {
    return match (name) {
        case "NOT_INTRINSIC" => IntrinsicKind.NOT_INTRINSIC
        case "NOT_IMPLEMENTED" => IntrinsicKind.NOT_IMPLEMENTED
        case "ARRAY_INIT" => IntrinsicKind.ARRAY_INIT
        case "SIZE_OF" => IntrinsicKind.SIZE_OF
        case "ALIGN_OF" => IntrinsicKind.ALIGN_OF
        case "ARRAY_ACQUIRE_RAW_DATA" => IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA
        case "ARRAY_RELEASE_RAW_DATA" => IntrinsicKind.ARRAY_RELEASE_RAW_DATA
        case "ARRAY_BUILT_IN_COPY_TO" => IntrinsicKind.ARRAY_BUILT_IN_COPY_TO
        case "ARRAY_GET" => IntrinsicKind.ARRAY_GET
        case "ARRAY_SET" => IntrinsicKind.ARRAY_SET
        case "ARRAY_GET_UNCHECKED" => IntrinsicKind.ARRAY_GET_UNCHECKED
        case "ARRAY_GET_REF_UNCHECKED" => IntrinsicKind.ARRAY_GET_REF_UNCHECKED
        case "ARRAY_SET_UNCHECKED" => IntrinsicKind.ARRAY_SET_UNCHECKED
        case "ARRAY_SIZE" => IntrinsicKind.ARRAY_SIZE
        case "ARRAY_CLONE" => IntrinsicKind.ARRAY_CLONE
        case "ARRAY_SLICE_INIT" => IntrinsicKind.ARRAY_SLICE_INIT
        case "ARRAY_SLICE" => IntrinsicKind.ARRAY_SLICE
        case "ARRAY_SLICE_RAWARRAY" => IntrinsicKind.ARRAY_SLICE_RAWARRAY
        case "ARRAY_SLICE_START" => IntrinsicKind.ARRAY_SLICE_START
        case "ARRAY_SLICE_SIZE" => IntrinsicKind.ARRAY_SLICE_SIZE
        case "ARRAY_SLICE_GET_ELEMENT" => IntrinsicKind.ARRAY_SLICE_GET_ELEMENT
        case "ARRAY_SLICE_GET_ELEMENT_UNCHECKED" => IntrinsicKind.ARRAY_SLICE_GET_ELEMENT_UNCHECKED
        case "ARRAY_SLICE_SET_ELEMENT" => IntrinsicKind.ARRAY_SLICE_SET_ELEMENT
        case "ARRAY_SLICE_SET_ELEMENT_UNCHECKED" => IntrinsicKind.ARRAY_SLICE_SET_ELEMENT_UNCHECKED
        case "FILL_IN_STACK_TRACE" => IntrinsicKind.FILL_IN_STACK_TRACE
        case "DECODE_STACK_TRACE" => IntrinsicKind.DECODE_STACK_TRACE
        case "DUMP_CURRENT_THREAD_INFO" => IntrinsicKind.DUMP_CURRENT_THREAD_INFO
        case "DUMP_ALL_THREADS_INFO" => IntrinsicKind.DUMP_ALL_THREADS_INFO
        case "CHR" => IntrinsicKind.CHR
        case "ORD" => IntrinsicKind.ORD
        case "CPOINTER_GET_POINTER_ADDRESS" => IntrinsicKind.CPOINTER_GET_POINTER_ADDRESS
        case "CPOINTER_INIT0" => IntrinsicKind.CPOINTER_INIT0
        case "CPOINTER_INIT1" => IntrinsicKind.CPOINTER_INIT1
        case "CPOINTER_READ" => IntrinsicKind.CPOINTER_READ
        case "CPOINTER_WRITE" => IntrinsicKind.CPOINTER_WRITE
        case "CPOINTER_ADD" => IntrinsicKind.CPOINTER_ADD
        case "CSTRING_INIT" => IntrinsicKind.CSTRING_INIT
        case "CSTRING_CONVERT_CSTR_TO_PTR" => IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR
        case "INOUT_PARAM" => IntrinsicKind.INOUT_PARAM
        case "REGISTER_WATCHED_OBJECT" => IntrinsicKind.REGISTER_WATCHED_OBJECT
        case "OBJECT_REFEQ" => IntrinsicKind.OBJECT_REFEQ
        case "RAW_ARRAY_REFEQ" => IntrinsicKind.RAW_ARRAY_REFEQ
        case "FUNC_REFEQ" => IntrinsicKind.FUNC_REFEQ
        case "OBJECT_ZERO_VALUE" => IntrinsicKind.OBJECT_ZERO_VALUE
        case "INVOKE_GC" => IntrinsicKind.INVOKE_GC
        case "SET_GC_THRESHOLD" => IntrinsicKind.SET_GC_THRESHOLD
        case "DUMP_CJ_HEAP_DATA" => IntrinsicKind.DUMP_CJ_HEAP_DATA
        case "GET_GC_COUNT" => IntrinsicKind.GET_GC_COUNT
        case "GET_GC_TIME_US" => IntrinsicKind.GET_GC_TIME_US
        case "GET_GC_FREED_SIZE" => IntrinsicKind.GET_GC_FREED_SIZE
        case "START_CJ_CPU_PROFILING" => IntrinsicKind.START_CJ_CPU_PROFILING
        case "STOP_CJ_CPU_PROFILING" => IntrinsicKind.STOP_CJ_CPU_PROFILING
        case "BLACK_BOX" => IntrinsicKind.BLACK_BOX
        case "GET_MAX_HEAP_SIZE" => IntrinsicKind.GET_MAX_HEAP_SIZE
        case "GET_ALLOCATE_HEAP_SIZE" => IntrinsicKind.GET_ALLOCATE_HEAP_SIZE
        case "GET_REAL_HEAP_SIZE" => IntrinsicKind.GET_REAL_HEAP_SIZE
        case "GET_THREAD_NUMBER" => IntrinsicKind.GET_THREAD_NUMBER
        case "GET_BLOCKING_THREAD_NUMBER" => IntrinsicKind.GET_BLOCKING_THREAD_NUMBER
        case "GET_NATIVE_THREAD_NUMBER" => IntrinsicKind.GET_NATIVE_THREAD_NUMBER
        case "VARRAY_SET" => IntrinsicKind.VARRAY_SET
        case "VARRAY_GET" => IntrinsicKind.VARRAY_GET
        case "FUTURE_INIT" => IntrinsicKind.FUTURE_INIT
        case "FUTURE_IS_COMPLETE" => IntrinsicKind.FUTURE_IS_COMPLETE
        case "FUTURE_WAIT" => IntrinsicKind.FUTURE_WAIT
        case "FUTURE_NOTIFYALL" => IntrinsicKind.FUTURE_NOTIFYALL
        case "IS_THREAD_OBJECT_INITED" => IntrinsicKind.IS_THREAD_OBJECT_INITED
        case "GET_THREAD_OBJECT" => IntrinsicKind.GET_THREAD_OBJECT
        case "SET_THREAD_OBJECT" => IntrinsicKind.SET_THREAD_OBJECT
        case "OVERFLOW_CHECKED_ADD" => IntrinsicKind.OVERFLOW_CHECKED_ADD
        case "OVERFLOW_CHECKED_SUB" => IntrinsicKind.OVERFLOW_CHECKED_SUB
        case "OVERFLOW_CHECKED_MUL" => IntrinsicKind.OVERFLOW_CHECKED_MUL
        case "OVERFLOW_CHECKED_DIV" => IntrinsicKind.OVERFLOW_CHECKED_DIV
        case "OVERFLOW_CHECKED_MOD" => IntrinsicKind.OVERFLOW_CHECKED_MOD
        case "OVERFLOW_CHECKED_POW" => IntrinsicKind.OVERFLOW_CHECKED_POW
        case "OVERFLOW_CHECKED_INC" => IntrinsicKind.OVERFLOW_CHECKED_INC
        case "OVERFLOW_CHECKED_DEC" => IntrinsicKind.OVERFLOW_CHECKED_DEC
        case "OVERFLOW_CHECKED_NEG" => IntrinsicKind.OVERFLOW_CHECKED_NEG
        case "OVERFLOW_THROWING_ADD" => IntrinsicKind.OVERFLOW_THROWING_ADD
        case "OVERFLOW_THROWING_SUB" => IntrinsicKind.OVERFLOW_THROWING_SUB
        case "OVERFLOW_THROWING_MUL" => IntrinsicKind.OVERFLOW_THROWING_MUL
        case "OVERFLOW_THROWING_DIV" => IntrinsicKind.OVERFLOW_THROWING_DIV
        case "OVERFLOW_THROWING_MOD" => IntrinsicKind.OVERFLOW_THROWING_MOD
        case "OVERFLOW_THROWING_POW" => IntrinsicKind.OVERFLOW_THROWING_POW
        case "OVERFLOW_THROWING_INC" => IntrinsicKind.OVERFLOW_THROWING_INC
        case "OVERFLOW_THROWING_DEC" => IntrinsicKind.OVERFLOW_THROWING_DEC
        case "OVERFLOW_THROWING_NEG" => IntrinsicKind.OVERFLOW_THROWING_NEG
        case "OVERFLOW_SATURATING_ADD" => IntrinsicKind.OVERFLOW_SATURATING_ADD
        case "OVERFLOW_SATURATING_SUB" => IntrinsicKind.OVERFLOW_SATURATING_SUB
        case "OVERFLOW_SATURATING_MUL" => IntrinsicKind.OVERFLOW_SATURATING_MUL
        case "OVERFLOW_SATURATING_DIV" => IntrinsicKind.OVERFLOW_SATURATING_DIV
        case "OVERFLOW_SATURATING_MOD" => IntrinsicKind.OVERFLOW_SATURATING_MOD
        case "OVERFLOW_SATURATING_POW" => IntrinsicKind.OVERFLOW_SATURATING_POW
        case "OVERFLOW_SATURATING_INC" => IntrinsicKind.OVERFLOW_SATURATING_INC
        case "OVERFLOW_SATURATING_DEC" => IntrinsicKind.OVERFLOW_SATURATING_DEC
        case "OVERFLOW_SATURATING_NEG" => IntrinsicKind.OVERFLOW_SATURATING_NEG
        case "OVERFLOW_WRAPPING_ADD" => IntrinsicKind.OVERFLOW_WRAPPING_ADD
        case "OVERFLOW_WRAPPING_SUB" => IntrinsicKind.OVERFLOW_WRAPPING_SUB
        case "OVERFLOW_WRAPPING_MUL" => IntrinsicKind.OVERFLOW_WRAPPING_MUL
        case "OVERFLOW_WRAPPING_DIV" => IntrinsicKind.OVERFLOW_WRAPPING_DIV
        case "OVERFLOW_WRAPPING_MOD" => IntrinsicKind.OVERFLOW_WRAPPING_MOD
        case "OVERFLOW_WRAPPING_POW" => IntrinsicKind.OVERFLOW_WRAPPING_POW
        case "OVERFLOW_WRAPPING_INC" => IntrinsicKind.OVERFLOW_WRAPPING_INC
        case "OVERFLOW_WRAPPING_DEC" => IntrinsicKind.OVERFLOW_WRAPPING_DEC
        case "OVERFLOW_WRAPPING_NEG" => IntrinsicKind.OVERFLOW_WRAPPING_NEG
        case "VECTOR_COMPARE_32" => IntrinsicKind.VECTOR_COMPARE_32
        case "VECTOR_INDEX_BYTE_32" => IntrinsicKind.VECTOR_INDEX_BYTE_32
        case "CJ_CORE_CAN_USE_SIMD" => IntrinsicKind.CJ_CORE_CAN_USE_SIMD
        case "CJ_TLS_DYN_SET_SESSION_CALLBACK" => IntrinsicKind.CJ_TLS_DYN_SET_SESSION_CALLBACK
        case "CJ_TLS_DYN_SSL_INIT" => IntrinsicKind.CJ_TLS_DYN_SSL_INIT
        case "REFLECTION_INTRINSIC_START_FLAG" => IntrinsicKind.REFLECTION_INTRINSIC_START_FLAG
        case "IS_INTERFACE" => IntrinsicKind.IS_INTERFACE
        case "IS_CLASS" => IntrinsicKind.IS_CLASS
        case "IS_PRIMITIVE" => IntrinsicKind.IS_PRIMITIVE
        case "IS_STRUCT" => IntrinsicKind.IS_STRUCT
        case "IS_GENERIC" => IntrinsicKind.IS_GENERIC
        case "IS_TUPLE" => IntrinsicKind.IS_TUPLE
        case "IS_FUNCTION" => IntrinsicKind.IS_FUNCTION
        case "IS_ENUM" => IntrinsicKind.IS_ENUM
        case "IS_BOX" => IntrinsicKind.IS_BOX
        case "GET_OR_CREATE_TYPEINFO_FOR_REFLECT" => IntrinsicKind.GET_OR_CREATE_TYPEINFO_FOR_REFLECT
        case "GET_TYPETEMPLATE" => IntrinsicKind.GET_TYPETEMPLATE
        case "CHECK_METHOD_ACTUAL_ARGS" => IntrinsicKind.CHECK_METHOD_ACTUAL_ARGS
        case "METHOD_ENTRYPOINT_IS_NULL" => IntrinsicKind.METHOD_ENTRYPOINT_IS_NULL
        case "IS_RELECT_UNSUPPORTED_TYPE" => IntrinsicKind.IS_RELECT_UNSUPPORTED_TYPE
        case "GET_TYPE_FOR_ANY" => IntrinsicKind.GET_TYPE_FOR_ANY
        case "GET_TYPE_BY_MANGLED_NAME" => IntrinsicKind.GET_TYPE_BY_MANGLED_NAME
        case "GET_TYPE_NAME" => IntrinsicKind.GET_TYPE_NAME
        case "GET_TYPE_BY_QUALIFIED_NAME" => IntrinsicKind.GET_TYPE_BY_QUALIFIED_NAME
        case "GET_TYPE_QUALIFIED_NAME_LENGTH" => IntrinsicKind.GET_TYPE_QUALIFIED_NAME_LENGTH
        case "GET_TYPE_QUALIFIED_NAME" => IntrinsicKind.GET_TYPE_QUALIFIED_NAME
        case "GET_NUM_OF_INTERFACE" => IntrinsicKind.GET_NUM_OF_INTERFACE
        case "GET_INTERFACE" => IntrinsicKind.GET_INTERFACE
        case "IS_SUBTYPE" => IntrinsicKind.IS_SUBTYPE
        case "GET_TYPE_INFO_MODIFIER" => IntrinsicKind.GET_TYPE_INFO_MODIFIER
        case "GET_TYPE_INFO_ANNOTATIONS" => IntrinsicKind.GET_TYPE_INFO_ANNOTATIONS
        case "GET_OBJ_CLASS" => IntrinsicKind.GET_OBJ_CLASS
        case "GET_SUPER_TYPE_INFO" => IntrinsicKind.GET_SUPER_TYPE_INFO
        case "GET_TYPE_ARGS" => IntrinsicKind.GET_TYPE_ARGS
        case "GET_NUM_OF_INSTANCE_METHOD_INFOS" => IntrinsicKind.GET_NUM_OF_INSTANCE_METHOD_INFOS
        case "GET_INSTANCE_METHOD_INFO" => IntrinsicKind.GET_INSTANCE_METHOD_INFO
        case "GET_NUM_OF_STATIC_METHOD_INFOS" => IntrinsicKind.GET_NUM_OF_STATIC_METHOD_INFOS
        case "GET_STATIC_METHOD_INFO" => IntrinsicKind.GET_STATIC_METHOD_INFO
        case "GET_METHOD_NAME" => IntrinsicKind.GET_METHOD_NAME
        case "GET_METHOD_RETURN_TYPE" => IntrinsicKind.GET_METHOD_RETURN_TYPE
        case "GET_METHOD_MODIFIER" => IntrinsicKind.GET_METHOD_MODIFIER
        case "GET_METHOD_ANNOTATIONS" => IntrinsicKind.GET_METHOD_ANNOTATIONS
        case "APPLY_CJ_METHOD" => IntrinsicKind.APPLY_CJ_METHOD
        case "APPLY_CJ_STATIC_METHOD" => IntrinsicKind.APPLY_CJ_STATIC_METHOD
        case "APPLY_CJ_GENERIC_METHOD" => IntrinsicKind.APPLY_CJ_GENERIC_METHOD
        case "APPLY_CJ_GENERIC_STATIC_METHOD" => IntrinsicKind.APPLY_CJ_GENERIC_STATIC_METHOD
        case "GET_NUM_OF_ACTUAL_PARAMETERS" => IntrinsicKind.GET_NUM_OF_ACTUAL_PARAMETERS
        case "GET_NUM_OF_GENERIC_PARAMETERS" => IntrinsicKind.GET_NUM_OF_GENERIC_PARAMETERS
        case "GET_ACTUAL_PARAMETER_INFO" => IntrinsicKind.GET_ACTUAL_PARAMETER_INFO
        case "GET_GENERIC_PARAMETER_INFO" => IntrinsicKind.GET_GENERIC_PARAMETER_INFO
        case "GET_NUM_OF_INSTANCE_FIELD_INFOS" => IntrinsicKind.GET_NUM_OF_INSTANCE_FIELD_INFOS
        case "GET_INSTANCE_FIELD_INFO" => IntrinsicKind.GET_INSTANCE_FIELD_INFO
        case "GET_NUM_OF_STATIC_FIELD_INFOS" => IntrinsicKind.GET_NUM_OF_STATIC_FIELD_INFOS
        case "GET_STATIC_FIELD_INFO" => IntrinsicKind.GET_STATIC_FIELD_INFO
        case "GET_STATIC_FIELD_NAME" => IntrinsicKind.GET_STATIC_FIELD_NAME
        case "GET_STATIC_FIELD_TYPE" => IntrinsicKind.GET_STATIC_FIELD_TYPE
        case "GET_STATIC_FIELD_ANNOTATIONS" => IntrinsicKind.GET_STATIC_FIELD_ANNOTATIONS
        case "GET_INSTANCE_FIELD_NAME" => IntrinsicKind.GET_INSTANCE_FIELD_NAME
        case "GET_INSTANCE_FIELD_TYPE" => IntrinsicKind.GET_INSTANCE_FIELD_TYPE
        case "GET_INSTANCE_FIELD_ANNOTATIONS" => IntrinsicKind.GET_INSTANCE_FIELD_ANNOTATIONS
        case "GET_INSTANCE_FIELD_MODIFIER" => IntrinsicKind.GET_INSTANCE_FIELD_MODIFIER
        case "GET_STATIC_FIELD_MODIFIER" => IntrinsicKind.GET_STATIC_FIELD_MODIFIER
        case "GET_FIELD_VALUE" => IntrinsicKind.GET_FIELD_VALUE
        case "SET_FIELD_VALUE" => IntrinsicKind.SET_FIELD_VALUE
        case "GET_STATIC_FIELD_VALUE" => IntrinsicKind.GET_STATIC_FIELD_VALUE
        case "SET_STATIC_FIELD_VALUE" => IntrinsicKind.SET_STATIC_FIELD_VALUE
        case "GET_FIELD_DECLARING_TYPE" => IntrinsicKind.GET_FIELD_DECLARING_TYPE
        case "GET_PARAMETER_INDEX" => IntrinsicKind.GET_PARAMETER_INDEX
        case "GET_PARAMETER_NAME" => IntrinsicKind.GET_PARAMETER_NAME
        case "GET_PARAMETER_TYPE" => IntrinsicKind.GET_PARAMETER_TYPE
        case "GET_PARAMETER_ANNOTATIONS" => IntrinsicKind.GET_PARAMETER_ANNOTATIONS
        case "GET_RELATED_PACKAGE_INF" => IntrinsicKind.GET_RELATED_PACKAGE_INF
        case "GET_PACKAGE_NAME" => IntrinsicKind.GET_PACKAGE_NAME
        case "GET_PACKAGE_NUM_OF_TYPE_INFOS" => IntrinsicKind.GET_PACKAGE_NUM_OF_TYPE_INFOS
        case "GET_PACKAGE_TYPE_INFO" => IntrinsicKind.GET_PACKAGE_TYPE_INFO
        case "GET_PACKAGE_NUM_OF_GLOBAL_METHODS" => IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_METHODS
        case "GET_PACKAGE_GLOBAL_METHOD_INFO" => IntrinsicKind.GET_PACKAGE_GLOBAL_METHOD_INFO
        case "GET_PACKAGE_NUM_OF_GLOBAL_FIELD_INFOS" => IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_FIELD_INFOS
        case "GET_PACKAGE_GLOBAL_FIELD_INFO" => IntrinsicKind.GET_PACKAGE_GLOBAL_FIELD_INFO
        case "LOAD_PACKAGE" => IntrinsicKind.LOAD_PACKAGE
        case "GET_PACKAGE_BY_QUALIFIEDNAME" => IntrinsicKind.GET_PACKAGE_BY_QUALIFIEDNAME
        case "GET_PACKAGE_VERSION" => IntrinsicKind.GET_PACKAGE_VERSION
        case "GET_SUB_PACKAGES" => IntrinsicKind.GET_SUB_PACKAGES
        case "GET_NUM_OF_FIELD_TYPES" => IntrinsicKind.GET_NUM_OF_FIELD_TYPES
        case "GET_FIELD_TYPES" => IntrinsicKind.GET_FIELD_TYPES
        case "NEW_AND_INIT_OBJECT" => IntrinsicKind.NEW_AND_INIT_OBJECT
        case "GET_ASSOCIATED_VALUES" => IntrinsicKind.GET_ASSOCIATED_VALUES
        case "GET_NUM_OF_FUNCTION_SIGNATURETYPES" => IntrinsicKind.GET_NUM_OF_FUNCTION_SIGNATURETYPES
        case "GET_FUNCTION_SIGNATURE_TYPES" => IntrinsicKind.GET_FUNCTION_SIGNATURE_TYPES
        case "GET_NUM_OF_ENUM_CONSTRUCTOR_INFOS" => IntrinsicKind.GET_NUM_OF_ENUM_CONSTRUCTOR_INFOS
        case "GET_ENUM_CONSTRUCTOR_INFO" => IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO
        case "GET_ENUM_CONSTRUCTOR_NAME" => IntrinsicKind.GET_ENUM_CONSTRUCTOR_NAME
        case "GET_ENUM_CONSTRUCTOR_INFO_FROM_ANY" => IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO_FROM_ANY
        case "REFLECTION_INTRINSIC_END_FLAG" => IntrinsicKind.REFLECTION_INTRINSIC_END_FLAG
        case "SLEEP" => IntrinsicKind.SLEEP
        case "SOURCE_FILE" => IntrinsicKind.SOURCE_FILE
        case "SOURCE_LINE" => IntrinsicKind.SOURCE_LINE
        case "IDENTITY_HASHCODE" => IntrinsicKind.IDENTITY_HASHCODE
        case "IDENTITY_HASHCODE_FOR_ARRAY" => IntrinsicKind.IDENTITY_HASHCODE_FOR_ARRAY
        case "ATOMIC_LOAD" => IntrinsicKind.ATOMIC_LOAD
        case "ATOMIC_STORE" => IntrinsicKind.ATOMIC_STORE
        case "ATOMIC_SWAP" => IntrinsicKind.ATOMIC_SWAP
        case "ATOMIC_COMPARE_AND_SWAP" => IntrinsicKind.ATOMIC_COMPARE_AND_SWAP
        case "ATOMIC_FETCH_ADD" => IntrinsicKind.ATOMIC_FETCH_ADD
        case "ATOMIC_FETCH_SUB" => IntrinsicKind.ATOMIC_FETCH_SUB
        case "ATOMIC_FETCH_AND" => IntrinsicKind.ATOMIC_FETCH_AND
        case "ATOMIC_FETCH_OR" => IntrinsicKind.ATOMIC_FETCH_OR
        case "ATOMIC_FETCH_XOR" => IntrinsicKind.ATOMIC_FETCH_XOR
        case "MUTEX_INIT" => IntrinsicKind.MUTEX_INIT
        case "CJ_MUTEX_LOCK" => IntrinsicKind.CJ_MUTEX_LOCK
        case "MUTEX_TRY_LOCK" => IntrinsicKind.MUTEX_TRY_LOCK
        case "MUTEX_CHECK_STATUS" => IntrinsicKind.MUTEX_CHECK_STATUS
        case "MUTEX_UNLOCK" => IntrinsicKind.MUTEX_UNLOCK
        case "WAITQUEUE_INIT" => IntrinsicKind.WAITQUEUE_INIT
        case "MONITOR_INIT" => IntrinsicKind.MONITOR_INIT
        case "MOITIOR_WAIT" => IntrinsicKind.MOITIOR_WAIT
        case "MOITIOR_NOTIFY" => IntrinsicKind.MOITIOR_NOTIFY
        case "MOITIOR_NOTIFY_ALL" => IntrinsicKind.MOITIOR_NOTIFY_ALL
        case "MULTICONDITION_WAIT" => IntrinsicKind.MULTICONDITION_WAIT
        case "MULTICONDITION_NOTIFY" => IntrinsicKind.MULTICONDITION_NOTIFY
        case "MULTICONDITION_NOTIFY_ALL" => IntrinsicKind.MULTICONDITION_NOTIFY_ALL
        case "CROSS_ACCESS_BARRIER" => IntrinsicKind.CROSS_ACCESS_BARRIER
        case "CREATE_EXPORT_HANDLE" => IntrinsicKind.CREATE_EXPORT_HANDLE
        case "GET_EXPORTED_REF" => IntrinsicKind.GET_EXPORTED_REF
        case "REMOVE_EXPORTED_REF" => IntrinsicKind.REMOVE_EXPORTED_REF
        case "GET_JSLAMBDA_ADDR" => IntrinsicKind.GET_JSLAMBDA_ADDR
        case "FFI_CJ_AST_LEX" => IntrinsicKind.FFI_CJ_AST_LEX
        case "FFI_CJ_AST_PARSEEXPR" => IntrinsicKind.FFI_CJ_AST_PARSEEXPR
        case "FFI_CJ_AST_PARSEDECL" => IntrinsicKind.FFI_CJ_AST_PARSEDECL
        case "FFI_CJ_AST_PARSE_PROPMEMBERDECL" => IntrinsicKind.FFI_CJ_AST_PARSE_PROPMEMBERDECL
        case "FFI_CJ_AST_PARSE_PRICONSTRUCTOR" => IntrinsicKind.FFI_CJ_AST_PARSE_PRICONSTRUCTOR
        case "FFI_CJ_AST_PARSE_PATTERN" => IntrinsicKind.FFI_CJ_AST_PARSE_PATTERN
        case "FFI_CJ_AST_PARSE_TYPE" => IntrinsicKind.FFI_CJ_AST_PARSE_TYPE
        case "FFI_CJ_AST_PARSETOPLEVEL" => IntrinsicKind.FFI_CJ_AST_PARSETOPLEVEL
        case "FFI_CJ_AST_DIAGREPORT" => IntrinsicKind.FFI_CJ_AST_DIAGREPORT
        case "FFI_CJ_PARENT_CONTEXT" => IntrinsicKind.FFI_CJ_PARENT_CONTEXT
        case "FFI_CJ_MACRO_ITEM_INFO" => IntrinsicKind.FFI_CJ_MACRO_ITEM_INFO
        case "FFI_CJ_GET_CHILD_MESSAGES" => IntrinsicKind.FFI_CJ_GET_CHILD_MESSAGES
        case "FFI_CJ_CHECK_ADD_SPACE" => IntrinsicKind.FFI_CJ_CHECK_ADD_SPACE
        case "CG_UNSAFE_BEGIN" => IntrinsicKind.CG_UNSAFE_BEGIN
        case "CG_UNSAFE_END" => IntrinsicKind.CG_UNSAFE_END
        case "STRLEN" => IntrinsicKind.STRLEN
        case "MEMCPY_S" => IntrinsicKind.MEMCPY_S
        case "MEMSET_S" => IntrinsicKind.MEMSET_S
        case "FREE" => IntrinsicKind.FREE
        case "MALLOC" => IntrinsicKind.MALLOC
        case "STRCMP" => IntrinsicKind.STRCMP
        case "MEMCMP" => IntrinsicKind.MEMCMP
        case "STRNCMP" => IntrinsicKind.STRNCMP
        case "STRCASECMP" => IntrinsicKind.STRCASECMP
        case "ATOMIC_INT8_LOAD" => IntrinsicKind.ATOMIC_INT8_LOAD
        case "ATOMIC_INT8_STORE" => IntrinsicKind.ATOMIC_INT8_STORE
        case "ATOMIC_INT8_SWAP" => IntrinsicKind.ATOMIC_INT8_SWAP
        case "ATOMIC_INT8_CAS" => IntrinsicKind.ATOMIC_INT8_CAS
        case "ATOMIC_INT8_FETCH_ADD" => IntrinsicKind.ATOMIC_INT8_FETCH_ADD
        case "ATOMIC_INT8_FETCH_SUB" => IntrinsicKind.ATOMIC_INT8_FETCH_SUB
        case "ATOMIC_INT8_FETCH_AND" => IntrinsicKind.ATOMIC_INT8_FETCH_AND
        case "ATOMIC_INT8_FETCH_OR" => IntrinsicKind.ATOMIC_INT8_FETCH_OR
        case "ATOMIC_INT8_FETCH_XOR" => IntrinsicKind.ATOMIC_INT8_FETCH_XOR
        case "ATOMIC_INT16_LOAD" => IntrinsicKind.ATOMIC_INT16_LOAD
        case "ATOMIC_INT16_STORE" => IntrinsicKind.ATOMIC_INT16_STORE
        case "ATOMIC_INT16_SWAP" => IntrinsicKind.ATOMIC_INT16_SWAP
        case "ATOMIC_INT16_CAS" => IntrinsicKind.ATOMIC_INT16_CAS
        case "ATOMIC_INT16_FETCH_ADD" => IntrinsicKind.ATOMIC_INT16_FETCH_ADD
        case "ATOMIC_INT16_FETCH_SUB" => IntrinsicKind.ATOMIC_INT16_FETCH_SUB
        case "ATOMIC_INT16_FETCH_AND" => IntrinsicKind.ATOMIC_INT16_FETCH_AND
        case "ATOMIC_INT16_FETCH_OR" => IntrinsicKind.ATOMIC_INT16_FETCH_OR
        case "ATOMIC_INT16_FETCH_XOR" => IntrinsicKind.ATOMIC_INT16_FETCH_XOR
        case "ATOMIC_INT32_LOAD" => IntrinsicKind.ATOMIC_INT32_LOAD
        case "ATOMIC_INT32_STORE" => IntrinsicKind.ATOMIC_INT32_STORE
        case "ATOMIC_INT32_SWAP" => IntrinsicKind.ATOMIC_INT32_SWAP
        case "ATOMIC_INT32_CAS" => IntrinsicKind.ATOMIC_INT32_CAS
        case "ATOMIC_INT32_FETCH_ADD" => IntrinsicKind.ATOMIC_INT32_FETCH_ADD
        case "ATOMIC_INT32_FETCH_SUB" => IntrinsicKind.ATOMIC_INT32_FETCH_SUB
        case "ATOMIC_INT32_FETCH_AND" => IntrinsicKind.ATOMIC_INT32_FETCH_AND
        case "ATOMIC_INT32_FETCH_OR" => IntrinsicKind.ATOMIC_INT32_FETCH_OR
        case "ATOMIC_INT32_FETCH_XOR" => IntrinsicKind.ATOMIC_INT32_FETCH_XOR
        case "ATOMIC_INT64_LOAD" => IntrinsicKind.ATOMIC_INT64_LOAD
        case "ATOMIC_INT64_STORE" => IntrinsicKind.ATOMIC_INT64_STORE
        case "ATOMIC_INT64_SWAP" => IntrinsicKind.ATOMIC_INT64_SWAP
        case "ATOMIC_INT64_CAS" => IntrinsicKind.ATOMIC_INT64_CAS
        case "ATOMIC_INT64_FETCH_ADD" => IntrinsicKind.ATOMIC_INT64_FETCH_ADD
        case "ATOMIC_INT64_FETCH_SUB" => IntrinsicKind.ATOMIC_INT64_FETCH_SUB
        case "ATOMIC_INT64_FETCH_AND" => IntrinsicKind.ATOMIC_INT64_FETCH_AND
        case "ATOMIC_INT64_FETCH_OR" => IntrinsicKind.ATOMIC_INT64_FETCH_OR
        case "ATOMIC_INT64_FETCH_XOR" => IntrinsicKind.ATOMIC_INT64_FETCH_XOR
        case "ATOMIC_UINT8_LOAD" => IntrinsicKind.ATOMIC_UINT8_LOAD
        case "ATOMIC_UINT8_STORE" => IntrinsicKind.ATOMIC_UINT8_STORE
        case "ATOMIC_UINT8_SWAP" => IntrinsicKind.ATOMIC_UINT8_SWAP
        case "ATOMIC_UINT8_CAS" => IntrinsicKind.ATOMIC_UINT8_CAS
        case "ATOMIC_UINT8_FETCH_ADD" => IntrinsicKind.ATOMIC_UINT8_FETCH_ADD
        case "ATOMIC_UINT8_FETCH_SUB" => IntrinsicKind.ATOMIC_UINT8_FETCH_SUB
        case "ATOMIC_UINT8_FETCH_AND" => IntrinsicKind.ATOMIC_UINT8_FETCH_AND
        case "ATOMIC_UINT8_FETCH_OR" => IntrinsicKind.ATOMIC_UINT8_FETCH_OR
        case "ATOMIC_UINT8_FETCH_XOR" => IntrinsicKind.ATOMIC_UINT8_FETCH_XOR
        case "ATOMIC_UINT16_LOAD" => IntrinsicKind.ATOMIC_UINT16_LOAD
        case "ATOMIC_UINT16_STORE" => IntrinsicKind.ATOMIC_UINT16_STORE
        case "ATOMIC_UINT16_SWAP" => IntrinsicKind.ATOMIC_UINT16_SWAP
        case "ATOMIC_UINT16_CAS" => IntrinsicKind.ATOMIC_UINT16_CAS
        case "ATOMIC_UINT16_FETCH_ADD" => IntrinsicKind.ATOMIC_UINT16_FETCH_ADD
        case "ATOMIC_UINT16_FETCH_SUB" => IntrinsicKind.ATOMIC_UINT16_FETCH_SUB
        case "ATOMIC_UINT16_FETCH_AND" => IntrinsicKind.ATOMIC_UINT16_FETCH_AND
        case "ATOMIC_UINT16_FETCH_OR" => IntrinsicKind.ATOMIC_UINT16_FETCH_OR
        case "ATOMIC_UINT16_FETCH_XOR" => IntrinsicKind.ATOMIC_UINT16_FETCH_XOR
        case "ATOMIC_UINT32_LOAD" => IntrinsicKind.ATOMIC_UINT32_LOAD
        case "ATOMIC_UINT32_STORE" => IntrinsicKind.ATOMIC_UINT32_STORE
        case "ATOMIC_UINT32_SWAP" => IntrinsicKind.ATOMIC_UINT32_SWAP
        case "ATOMIC_UINT32_CAS" => IntrinsicKind.ATOMIC_UINT32_CAS
        case "ATOMIC_UINT32_FETCH_ADD" => IntrinsicKind.ATOMIC_UINT32_FETCH_ADD
        case "ATOMIC_UINT32_FETCH_SUB" => IntrinsicKind.ATOMIC_UINT32_FETCH_SUB
        case "ATOMIC_UINT32_FETCH_AND" => IntrinsicKind.ATOMIC_UINT32_FETCH_AND
        case "ATOMIC_UINT32_FETCH_OR" => IntrinsicKind.ATOMIC_UINT32_FETCH_OR
        case "ATOMIC_UINT32_FETCH_XOR" => IntrinsicKind.ATOMIC_UINT32_FETCH_XOR
        case "ATOMIC_UINT64_LOAD" => IntrinsicKind.ATOMIC_UINT64_LOAD
        case "ATOMIC_UINT64_STORE" => IntrinsicKind.ATOMIC_UINT64_STORE
        case "ATOMIC_UINT64_SWAP" => IntrinsicKind.ATOMIC_UINT64_SWAP
        case "ATOMIC_UINT64_CAS" => IntrinsicKind.ATOMIC_UINT64_CAS
        case "ATOMIC_UINT64_FETCH_ADD" => IntrinsicKind.ATOMIC_UINT64_FETCH_ADD
        case "ATOMIC_UINT64_FETCH_SUB" => IntrinsicKind.ATOMIC_UINT64_FETCH_SUB
        case "ATOMIC_UINT64_FETCH_AND" => IntrinsicKind.ATOMIC_UINT64_FETCH_AND
        case "ATOMIC_UINT64_FETCH_OR" => IntrinsicKind.ATOMIC_UINT64_FETCH_OR
        case "ATOMIC_UINT64_FETCH_XOR" => IntrinsicKind.ATOMIC_UINT64_FETCH_XOR
        case "ATOMIC_BOOL_LOAD" => IntrinsicKind.ATOMIC_BOOL_LOAD
        case "ATOMIC_BOOL_STORE" => IntrinsicKind.ATOMIC_BOOL_STORE
        case "ATOMIC_BOOL_SWAP" => IntrinsicKind.ATOMIC_BOOL_SWAP
        case "ATOMIC_BOOL_CAS" => IntrinsicKind.ATOMIC_BOOL_CAS
        case "ATOMIC_REFERENCEBASE_LOAD" => IntrinsicKind.ATOMIC_REFERENCEBASE_LOAD
        case "ATOMIC_REFERENCEBASE_STORE" => IntrinsicKind.ATOMIC_REFERENCEBASE_STORE
        case "ATOMIC_REFERENCEBASE_SWAP" => IntrinsicKind.ATOMIC_REFERENCEBASE_SWAP
        case "ATOMIC_REFERENCEBASE_CAS" => IntrinsicKind.ATOMIC_REFERENCEBASE_CAS
        case "ATOMIC_OPTIONREFERENCE_LOAD" => IntrinsicKind.ATOMIC_OPTIONREFERENCE_LOAD
        case "ATOMIC_OPTIONREFERENCE_STORE" => IntrinsicKind.ATOMIC_OPTIONREFERENCE_STORE
        case "ATOMIC_OPTIONREFERENCE_SWAP" => IntrinsicKind.ATOMIC_OPTIONREFERENCE_SWAP
        case "ATOMIC_OPTIONREFERENCE_CAS" => IntrinsicKind.ATOMIC_OPTIONREFERENCE_CAS
        case "BEGIN_CATCH" => IntrinsicKind.BEGIN_CATCH
        case "ABS" => IntrinsicKind.ABS
        case "FABS" => IntrinsicKind.FABS
        case "FLOOR" => IntrinsicKind.FLOOR
        case "CEIL" => IntrinsicKind.CEIL
        case "TRUNC" => IntrinsicKind.TRUNC
        case "SIN" => IntrinsicKind.SIN
        case "COS" => IntrinsicKind.COS
        case "EXP" => IntrinsicKind.EXP
        case "EXP2" => IntrinsicKind.EXP2
        case "LOG" => IntrinsicKind.LOG
        case "LOG2" => IntrinsicKind.LOG2
        case "LOG10" => IntrinsicKind.LOG10
        case "SQRT" => IntrinsicKind.SQRT
        case "ROUND" => IntrinsicKind.ROUND
        case "POW" => IntrinsicKind.POW
        case "POWI" => IntrinsicKind.POWI
        case "BIT_CAST" => IntrinsicKind.BIT_CAST
        case "PREINITIALIZE" => IntrinsicKind.PREINITIALIZE
        case "OBJECT_AS" => IntrinsicKind.OBJECT_AS
        case "IS_NULL" => IntrinsicKind.IS_NULL
        case "GET_TYPE_FOR_TYPE_PARAMETER" => IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER
        case "IS_SUBTYPE_TYPES" => IntrinsicKind.IS_SUBTYPE_TYPES
        case "EXCLUSIVE_SCOPE" => IntrinsicKind.EXCLUSIVE_SCOPE
        case _ => IntrinsicKind.NOT_INTRINSIC
    }
}

func CHIRFieldAt(fields: ArrayList<String>, index: Int64): String {
    if (index < fields.size) {
        return fields[index]
    }
    return ""
}
