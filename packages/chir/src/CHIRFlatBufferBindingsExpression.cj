package cjcj::chir

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// PackageFormat_generated.h:6359-6405. Expression read accessors and Verify.
class PackageFormat_Expression <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Base> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_EXPRESSION_VT_BASE)) { Some(PackageFormat_Base(data, pointerPos)) } else { None }
    }

    func GetKind(): UInt8 {
        return GetField(CHIRFB_EXPRESSION_VT_KIND, 0u8)
    }

    func GetOperands(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_EXPRESSION_VT_OPERANDS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetBlockGroups(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_EXPRESSION_VT_BLOCKGROUPS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetOwner(): UInt32 {
        return GetField(CHIRFB_EXPRESSION_VT_OWNER, 0u32)
    }

    func GetResultLocalVar(): UInt32 {
        return GetField(CHIRFB_EXPRESSION_VT_RESULTLOCALVAR, 0u32)
    }

    func GetResultTy(): UInt32 {
        return GetField(CHIRFB_EXPRESSION_VT_RESULTTY, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_EXPRESSION_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_EXPRESSION_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Base(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_EXPRESSION_VT_KIND, 1) &&
            VerifyOffset(verifier, CHIRFB_EXPRESSION_VT_OPERANDS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_EXPRESSION_VT_OPERANDS), 4) &&
            VerifyOffset(verifier, CHIRFB_EXPRESSION_VT_BLOCKGROUPS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_EXPRESSION_VT_BLOCKGROUPS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_EXPRESSION_VT_OWNER, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_EXPRESSION_VT_RESULTLOCALVAR, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_EXPRESSION_VT_RESULTTY, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6485-6504. UnaryExpressionBase read accessors and Verify.
class PackageFormat_UnaryExpressionBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_UNARY_EXPRESSION_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetOverflowStrategy(): UInt8 {
        return GetField(CHIRFB_UNARY_EXPRESSION_BASE_VT_OVERFLOWSTRATEGY, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_UNARY_EXPRESSION_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_UNARY_EXPRESSION_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_UNARY_EXPRESSION_BASE_VT_OVERFLOWSTRATEGY, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6537-6556. BinaryExpressionBase read accessors and Verify.
class PackageFormat_BinaryExpressionBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BINARY_EXPRESSION_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetOverflowStrategy(): UInt8 {
        return GetField(CHIRFB_BINARY_EXPRESSION_BASE_VT_OVERFLOWSTRATEGY, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BINARY_EXPRESSION_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BINARY_EXPRESSION_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_BINARY_EXPRESSION_BASE_VT_OVERFLOWSTRATEGY, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6589-6608. AllocateBase read accessors and Verify.
class PackageFormat_AllocateBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ALLOCATE_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetAllocatedType(): UInt32 {
        return GetField(CHIRFB_ALLOCATE_BASE_VT_ALLOCATEDTYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_ALLOCATE_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_ALLOCATE_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_ALLOCATE_BASE_VT_ALLOCATEDTYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6641-6666. FuncCall read accessors and Verify.
class PackageFormat_FuncCall <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNC_CALL_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetInstantiatedTypeArgs(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNC_CALL_VT_INSTANTIATEDTYPEARGS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetObjType(): UInt32 {
        return GetField(CHIRFB_FUNC_CALL_VT_OBJTYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FUNC_CALL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FUNC_CALL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_FUNC_CALL_VT_INSTANTIATEDTYPEARGS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FUNC_CALL_VT_INSTANTIATEDTYPEARGS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNC_CALL_VT_OBJTYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6717-6736. ApplyBase read accessors and Verify.
class PackageFormat_ApplyBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_FuncCall> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_APPLY_BASE_VT_BASE)) { Some(PackageFormat_FuncCall(data, pointerPos)) } else { None }
    }

    func GetIsSuperCall(): Bool {
        return GetField(CHIRFB_APPLY_BASE_VT_ISSUPERCALL, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_APPLY_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_APPLY_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncCall(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_APPLY_BASE_VT_ISSUPERCALL, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6769-6789. InvokeBase read accessors and Verify.
class PackageFormat_InvokeBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_FuncCall> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_INVOKE_BASE_VT_BASE)) { Some(PackageFormat_FuncCall(data, pointerPos)) } else { None }
    }

    func GetVirMethodCtx(): Option<PackageFormat_FuncSigInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_INVOKE_BASE_VT_VIRMETHODCTX)) { Some(PackageFormat_FuncSigInfo(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_INVOKE_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_INVOKE_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncCall(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_INVOKE_BASE_VT_VIRMETHODCTX) &&
            verifier.VerifyTable(GetPointer(CHIRFB_INVOKE_BASE_VT_VIRMETHODCTX), {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncSigInfo(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6822-6841. IntrinsicBase read accessors and Verify.
class PackageFormat_IntrinsicBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_FuncCall> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_INTRINSIC_BASE_VT_BASE)) { Some(PackageFormat_FuncCall(data, pointerPos)) } else { None }
    }

    func GetIntrinsicKind(): UInt16 {
        return GetField(CHIRFB_INTRINSIC_BASE_VT_INTRINSICKIND, 0u16)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_INTRINSIC_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_INTRINSIC_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncCall(data, tablePos).Verify(active)}) &&
            VerifyField<UInt16>(verifier, CHIRFB_INTRINSIC_BASE_VT_INTRINSICKIND, 2) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6874-6893. NumericCastBase read accessors and Verify.
class PackageFormat_NumericCastBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_NUMERIC_CAST_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetOverflowStrategy(): UInt8 {
        return GetField(CHIRFB_NUMERIC_CAST_BASE_VT_OVERFLOWSTRATEGY, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_NUMERIC_CAST_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_NUMERIC_CAST_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_NUMERIC_CAST_BASE_VT_OVERFLOWSTRATEGY, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6926-6945. Branch read accessors and Verify.
class PackageFormat_Branch <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BRANCH_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetSourceExpr(): UInt8 {
        return GetField(CHIRFB_BRANCH_VT_SOURCEEXPR, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BRANCH_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BRANCH_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_BRANCH_VT_SOURCEEXPR, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6978-6998. MultiBranch read accessors and Verify.
class PackageFormat_MultiBranch <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MULTI_BRANCH_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetCaseValues(): Option<Vector<UInt64>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MULTI_BRANCH_VT_CASEVALUES)) { Some(Vector<UInt64>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_MULTI_BRANCH_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_MULTI_BRANCH_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_MULTI_BRANCH_VT_CASEVALUES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_MULTI_BRANCH_VT_CASEVALUES), 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7042-7062. GetElementRef read accessors and Verify.
class PackageFormat_GetElementRef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_ELEMENT_REF_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetPath(): Option<Vector<UInt64>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_ELEMENT_REF_VT_PATH)) { Some(Vector<UInt64>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GET_ELEMENT_REF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GET_ELEMENT_REF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_GET_ELEMENT_REF_VT_PATH) &&
            verifier.VerifyVector(GetPointer(CHIRFB_GET_ELEMENT_REF_VT_PATH), 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7106-7127. GetElementByName read accessors and Verify.
class PackageFormat_GetElementByName <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_ELEMENT_BY_NAME_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetFieldNames(): Option<Vector<Offset<FlatBufferString>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_ELEMENT_BY_NAME_VT_FIELDNAMES)) { Some(Vector<Offset<FlatBufferString>>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GET_ELEMENT_BY_NAME_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GET_ELEMENT_BY_NAME_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_GET_ELEMENT_BY_NAME_VT_FIELDNAMES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_GET_ELEMENT_BY_NAME_VT_FIELDNAMES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(CHIRFB_GET_ELEMENT_BY_NAME_VT_FIELDNAMES)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7171-7191. StoreElementRef read accessors and Verify.
class PackageFormat_StoreElementRef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STORE_ELEMENT_REF_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetPath(): Option<Vector<UInt64>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STORE_ELEMENT_REF_VT_PATH)) { Some(Vector<UInt64>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_STORE_ELEMENT_REF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_STORE_ELEMENT_REF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_STORE_ELEMENT_REF_VT_PATH) &&
            verifier.VerifyVector(GetPointer(CHIRFB_STORE_ELEMENT_REF_VT_PATH), 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7235-7256. StoreElementByName read accessors and Verify.
class PackageFormat_StoreElementByName <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STORE_ELEMENT_BY_NAME_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetFieldNames(): Option<Vector<Offset<FlatBufferString>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STORE_ELEMENT_BY_NAME_VT_FIELDNAMES)) { Some(Vector<Offset<FlatBufferString>>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_STORE_ELEMENT_BY_NAME_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_STORE_ELEMENT_BY_NAME_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_STORE_ELEMENT_BY_NAME_VT_FIELDNAMES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_STORE_ELEMENT_BY_NAME_VT_FIELDNAMES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(CHIRFB_STORE_ELEMENT_BY_NAME_VT_FIELDNAMES)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7300-7319. InstanceOf read accessors and Verify.
class PackageFormat_InstanceOf <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_INSTANCE_OF_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetTargetType(): UInt32 {
        return GetField(CHIRFB_INSTANCE_OF_VT_TARGETTYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_INSTANCE_OF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_INSTANCE_OF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_INSTANCE_OF_VT_TARGETTYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7352-7372. Field read accessors and Verify.
class PackageFormat_Field <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FIELD_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetPath(): Option<Vector<UInt64>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FIELD_VT_PATH)) { Some(Vector<UInt64>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FIELD_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FIELD_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_FIELD_VT_PATH) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FIELD_VT_PATH), 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7416-7437. FieldByName read accessors and Verify.
class PackageFormat_FieldByName <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FIELD_BY_NAME_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetFieldNames(): Option<Vector<Offset<FlatBufferString>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FIELD_BY_NAME_VT_FIELDNAMES)) { Some(Vector<Offset<FlatBufferString>>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FIELD_BY_NAME_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FIELD_BY_NAME_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_FIELD_BY_NAME_VT_FIELDNAMES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FIELD_BY_NAME_VT_FIELDNAMES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(CHIRFB_FIELD_BY_NAME_VT_FIELDNAMES)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7481-7500. RawArrayAllocateBase read accessors and Verify.
class PackageFormat_RawArrayAllocateBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_RAW_ARRAY_ALLOCATE_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetElementType(): UInt32 {
        return GetField(CHIRFB_RAW_ARRAY_ALLOCATE_BASE_VT_ELEMENTTYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_RAW_ARRAY_ALLOCATE_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_RAW_ARRAY_ALLOCATE_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_RAW_ARRAY_ALLOCATE_BASE_VT_ELEMENTTYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7533-7553. Debug read accessors and Verify.
class PackageFormat_Debug <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetSrcCodeName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_VT_SRCCODENAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_DEBUG_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_VT_SRCCODENAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_DEBUG_VT_SRCCODENAME)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7597-7616. SpawnBase read accessors and Verify.
class PackageFormat_SpawnBase <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_SPAWN_BASE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetExecuteClosure(): UInt32 {
        return GetField(CHIRFB_SPAWN_BASE_VT_EXECUTECLOSURE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_SPAWN_BASE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_SPAWN_BASE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_SPAWN_BASE_VT_EXECUTECLOSURE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7649-7712. Lambda read accessors and Verify.
class PackageFormat_Lambda <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LAMBDA_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetFuncTy(): UInt32 {
        return GetField(CHIRFB_LAMBDA_VT_FUNCTY, 0u32)
    }

    func GetIsLocalFunc(): Bool {
        return GetField(CHIRFB_LAMBDA_VT_ISLOCALFUNC, false)
    }

    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LAMBDA_VT_IDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetSrcCodeName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LAMBDA_VT_SRCCODENAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LAMBDA_VT_PARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetGenericTypeParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LAMBDA_VT_GENERICTYPEPARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetBody(): UInt32 {
        return GetField(CHIRFB_LAMBDA_VT_BODY, 0u32)
    }

    func GetRetVal(): UInt32 {
        return GetField(CHIRFB_LAMBDA_VT_RETVAL, 0u32)
    }

    func GetIsCompileTimeValue(): Bool {
        return GetField(CHIRFB_LAMBDA_VT_ISCOMPILETIMEVALUE, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_LAMBDA_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_LAMBDA_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_LAMBDA_VT_FUNCTY, 4) &&
            VerifyField<Bool>(verifier, CHIRFB_LAMBDA_VT_ISLOCALFUNC, 1) &&
            VerifyOffset(verifier, CHIRFB_LAMBDA_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_LAMBDA_VT_IDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_LAMBDA_VT_SRCCODENAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_LAMBDA_VT_SRCCODENAME)) &&
            VerifyOffset(verifier, CHIRFB_LAMBDA_VT_PARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_LAMBDA_VT_PARAMS), 4) &&
            VerifyOffset(verifier, CHIRFB_LAMBDA_VT_GENERICTYPEPARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_LAMBDA_VT_GENERICTYPEPARAMS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_LAMBDA_VT_BODY, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_LAMBDA_VT_RETVAL, 4) &&
            VerifyField<Bool>(verifier, CHIRFB_LAMBDA_VT_ISCOMPILETIMEVALUE, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7815-7835. GetInstantiateValue read accessors and Verify.
class PackageFormat_GetInstantiateValue <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_INSTANTIATE_VALUE_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetInstantiateTypes(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_INSTANTIATE_VALUE_VT_INSTANTIATETYPES)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GET_INSTANTIATE_VALUE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GET_INSTANTIATE_VALUE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_GET_INSTANTIATE_VALUE_VT_INSTANTIATETYPES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_GET_INSTANTIATE_VALUE_VT_INSTANTIATETYPES), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:7879-7898. GetRTTIStatic read accessors and Verify.
class PackageFormat_GetRTTIStatic <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Expression> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GET_RTTI_STATIC_VT_BASE)) { Some(PackageFormat_Expression(data, pointerPos)) } else { None }
    }

    func GetRttiType(): UInt32 {
        return GetField(CHIRFB_GET_RTTI_STATIC_VT_RTTITYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GET_RTTI_STATIC_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GET_RTTI_STATIC_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_GET_RTTI_STATIC_VT_RTTITYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h union verifier switch for ExpressionElem.
func VerifyExpressionElem(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, kind: UInt8): Bool {
    return match (kind) {
        case 0u8 => true
        case 1u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Expression(data, tablePos).Verify(active)})
        case 2u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_AllocateBase(data, tablePos).Verify(active)})
        case 3u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_ApplyBase(data, tablePos).Verify(active)})
        case 4u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_BinaryExpressionBase(data, tablePos).Verify(active)})
        case 5u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Branch(data, tablePos).Verify(active)})
        case 6u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Debug(data, tablePos).Verify(active)})
        case 7u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Field(data, tablePos).Verify(active)})
        case 8u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_FieldByName(data, tablePos).Verify(active)})
        case 9u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GetElementByName(data, tablePos).Verify(active)})
        case 10u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GetElementRef(data, tablePos).Verify(active)})
        case 11u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GetInstantiateValue(data, tablePos).Verify(active)})
        case 12u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GetRTTIStatic(data, tablePos).Verify(active)})
        case 13u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_InstanceOf(data, tablePos).Verify(active)})
        case 14u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_IntrinsicBase(data, tablePos).Verify(active)})
        case 15u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_InvokeBase(data, tablePos).Verify(active)})
        case 16u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Lambda(data, tablePos).Verify(active)})
        case 17u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_MultiBranch(data, tablePos).Verify(active)})
        case 18u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_NumericCastBase(data, tablePos).Verify(active)})
        case 19u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_RawArrayAllocateBase(data, tablePos).Verify(active)})
        case 20u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_SpawnBase(data, tablePos).Verify(active)})
        case 21u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_StoreElementByName(data, tablePos).Verify(active)})
        case 22u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_StoreElementRef(data, tablePos).Verify(active)})
        case 23u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_UnaryExpressionBase(data, tablePos).Verify(active)})
        case _ => true
    }
}

func VerifyExpressionElemVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
    if (let None <- values) {
        return if (let None <- types) { true } else { false }
    }
    if (let None <- types) {
        return false
    }
    let valueVector = Vector<Offset<Any>>(data, values.getOrThrow())
    let typeVector = Vector<UInt8>(data, types.getOrThrow())
    if (valueVector.size() != typeVector.size()) {
        return false
    }
    var index = 0u32
    while (index < valueVector.size()) {
        if (!VerifyExpressionElem(data, verifier, Some((valueVector.Get(index) as Int64).getOrThrow()), typeVector.Get(index, 0u8))) {
            return false
        }
        index++
    }
    return true
}
