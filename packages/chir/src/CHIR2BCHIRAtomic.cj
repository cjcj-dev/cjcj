package cjcj::chir

import cjcj::utils.CJC_ASSERT

public func BCHIRMangledName(value: Value): String {
    let identifier = value.GetIdentifier()
    if (identifier.size > 0) {
        let first = identifier[0]
        if (first == b'@' || first == b'%' || first == b'$') {
            return identifier[1..]
        }
    }
    return identifier
}

public func BCHIRMangledName(def: CustomTypeDef): String {
    return def.GetIdentifierWithoutPrefix()
}

public func BCHIRPrimitiveTypeKindToOpCode(kind: TypeKind): OpCode {
    return match (kind) {
        case TypeKind.TYPE_INT8 => OpCode.INT8
        case TypeKind.TYPE_INT16 => OpCode.INT16
        case TypeKind.TYPE_INT32 => OpCode.INT32
        case TypeKind.TYPE_INT64 => OpCode.INT64
        case TypeKind.TYPE_INT_NATIVE => OpCode.INTNAT
        case TypeKind.TYPE_UINT8 => OpCode.UINT8
        case TypeKind.TYPE_UINT16 => OpCode.UINT16
        case TypeKind.TYPE_UINT32 => OpCode.UINT32
        case TypeKind.TYPE_UINT64 => OpCode.UINT64
        case TypeKind.TYPE_UINT_NATIVE => OpCode.UINTNAT
        case TypeKind.TYPE_FLOAT16 => OpCode.FLOAT16
        case TypeKind.TYPE_FLOAT32 => OpCode.FLOAT32
        case TypeKind.TYPE_FLOAT64 => OpCode.FLOAT64
        case TypeKind.TYPE_BOOLEAN => OpCode.BOOL
        case TypeKind.TYPE_RUNE => OpCode.RUNE
        case TypeKind.TYPE_UNIT => OpCode.UNIT
        case _ => OpCode.INVALID
    }
}

public func BCHIRUnaryExprKindToOpCode(kind: ExprKind): OpCode {
    return match (kind) {
        case ExprKind.NEG => OpCode.UN_NEG
        case ExprKind.NOT => OpCode.UN_NOT
        case ExprKind.BITNOT => OpCode.UN_BITNOT
        case _ => CJC_ASSERT(false); OpCode.INVALID
    }
}

public func BCHIRBinaryExprKindToOpCode(kind: ExprKind): OpCode {
    return match (kind) {
        case ExprKind.ADD => OpCode.BIN_ADD
        case ExprKind.SUB => OpCode.BIN_SUB
        case ExprKind.MUL => OpCode.BIN_MUL
        case ExprKind.DIV => OpCode.BIN_DIV
        case ExprKind.MOD => OpCode.BIN_MOD
        case ExprKind.EXP => OpCode.BIN_EXP
        case ExprKind.LSHIFT => OpCode.BIN_LSHIFT
        case ExprKind.RSHIFT => OpCode.BIN_RSHIFT
        case ExprKind.BITAND => OpCode.BIN_BITAND
        case ExprKind.BITOR => OpCode.BIN_BITOR
        case ExprKind.BITXOR => OpCode.BIN_BITXOR
        case ExprKind.LT => OpCode.BIN_LT
        case ExprKind.GT => OpCode.BIN_GT
        case ExprKind.LE => OpCode.BIN_LE
        case ExprKind.GE => OpCode.BIN_GE
        case ExprKind.EQUAL => OpCode.BIN_EQUAL
        case ExprKind.NOTEQUAL => OpCode.BIN_NOTEQ
        case ExprKind.AND => CJC_ASSERT(false); OpCode.INVALID
        case ExprKind.OR => CJC_ASSERT(false); OpCode.INVALID
        case _ => CJC_ASSERT(false); OpCode.INVALID
    }
}

public func BCHIRBinaryExprKindWithExceptionToOpCode(kind: ExprKind): OpCode {
    return match (kind) {
        case ExprKind.ADD => OpCode.BIN_ADD_EXC
        case ExprKind.SUB => OpCode.BIN_SUB_EXC
        case ExprKind.MUL => OpCode.BIN_MUL_EXC
        case ExprKind.DIV => OpCode.BIN_DIV_EXC
        case ExprKind.MOD => OpCode.BIN_MOD_EXC
        case ExprKind.EXP => OpCode.BIN_EXP_EXC
        case ExprKind.LSHIFT => OpCode.BIN_LSHIFT_EXC
        case ExprKind.RSHIFT => OpCode.BIN_RSHIFT_EXC
        case ExprKind.NEG => OpCode.UN_NEG_EXC
        case _ => OpCode.INVALID
    }
}

public func BCHIRTypeKindCell(ty: Option<Type>): Int64 {
    if (let Some(valueTy) <- ty) {
        return TypeKindIndex(valueTy.GetTypeKind())
    }
    return TypeKindIndex(TypeKind.TYPE_INVALID)
}

public func BCHIRTypeKindCell(ty: Type): Int64 {
    return TypeKindIndex(ty.GetTypeKind())
}

public func BCHIRClassMangledNameForType(ty: Type): String {
    if (let Some(classTy) <- (ty as ClassType)) {
        return BCHIRMangledName(classTy.GetClassDef())
    }
    if (let Some(structTy) <- (ty as StructType)) {
        return BCHIRMangledName(structTy.GetStructDef())
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        return BCHIRMangledName(enumTy.GetEnumDef())
    }
    if (let Some(customTy) <- (ty as CustomType)) {
        return BCHIRMangledName(customTy.GetCustomTypeDef())
    }
    return ty.ToString()
}

public func BCHIRCellFromUInt64(value: UInt64): Int64 {
    if (value <= UInt64(Int64.Max)) {
        return Int64(value)
    }
    return -Int64(UInt64.Max - value) - 1
}

public func BCHIRIsWideIntegerOp(opCode: OpCode): Bool {
    return opCode == OpCode.INT64 || opCode == OpCode.INTNAT || opCode == OpCode.UINT64 ||
        opCode == OpCode.UINTNAT
}

public func BCHIRPushOpWithName(definition: BCHIRDefinition, opCode: OpCode, name: String): Int64 {
    let index = definition.NextIndex()
    definition.PushOp(opCode)
    if (!name.isEmpty()) {
        definition.AddMangledNameAnnotation(index, name)
    }
    return index
}
