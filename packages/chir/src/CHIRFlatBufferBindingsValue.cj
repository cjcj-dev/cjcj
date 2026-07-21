package cjcj::chir

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// PackageFormat_generated.h:3856-3886. Value read accessors and Verify.
class PackageFormat_Value <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Base> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_VALUE_VT_BASE)) { Some(PackageFormat_Base(data, pointerPos)) } else { None }
    }

    func GetType(): UInt32 {
        return GetField(CHIRFB_VALUE_VT_TYPE, 0u32)
    }

    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_VALUE_VT_IDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetKind(): UInt8 {
        return GetField(CHIRFB_VALUE_VT_KIND, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_VALUE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_VALUE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Base(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_VALUE_VT_TYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_VALUE_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_VALUE_VT_IDENTIFIER)) &&
            VerifyField<UInt8>(verifier, CHIRFB_VALUE_VT_KIND, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3944-3963. LiteralValue read accessors and Verify.
class PackageFormat_LiteralValue <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LITERAL_VALUE_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetLiteralKind(): UInt8 {
        return GetField(CHIRFB_LITERAL_VALUE_VT_LITERALKIND, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_LITERAL_VALUE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_LITERAL_VALUE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_LITERAL_VALUE_VT_LITERALKIND, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3996-4015. BoolLiteral read accessors and Verify.
class PackageFormat_BoolLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BOOL_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func GetVal(): Bool {
        return GetField(CHIRFB_BOOL_LITERAL_VT_VAL, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BOOL_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BOOL_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_BOOL_LITERAL_VT_VAL, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4048-4068. StringLiteral read accessors and Verify.
class PackageFormat_StringLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STRING_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func GetVal(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STRING_LITERAL_VT_VAL)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_STRING_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_STRING_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_STRING_LITERAL_VT_VAL) &&
            verifier.VerifyString(GetPointer(CHIRFB_STRING_LITERAL_VT_VAL)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4112-4131. RuneLiteral read accessors and Verify.
class PackageFormat_RuneLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_RUNE_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func GetVal(): UInt32 {
        return GetField(CHIRFB_RUNE_LITERAL_VT_VAL, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_RUNE_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_RUNE_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_RUNE_LITERAL_VT_VAL, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4164-4183. IntLiteral read accessors and Verify.
class PackageFormat_IntLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_INT_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func GetVal(): UInt64 {
        return GetField(CHIRFB_INT_LITERAL_VT_VAL, 0u64)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_INT_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_INT_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            VerifyField<UInt64>(verifier, CHIRFB_INT_LITERAL_VT_VAL, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4216-4235. FloatLiteral read accessors and Verify.
class PackageFormat_FloatLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FLOAT_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func GetVal(): Float64 {
        return GetField(CHIRFB_FLOAT_LITERAL_VT_VAL, 1.0f64)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FLOAT_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FLOAT_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            VerifyField<Float64>(verifier, CHIRFB_FLOAT_LITERAL_VT_VAL, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4268-4282. UnitLiteral read accessors and Verify.
class PackageFormat_UnitLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_UNIT_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_UNIT_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_UNIT_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4310-4324. NullLiteral read accessors and Verify.
class PackageFormat_NullLiteral <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_LiteralValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_NULL_LITERAL_VT_BASE)) { Some(PackageFormat_LiteralValue(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_NULL_LITERAL_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_NULL_LITERAL_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_LiteralValue(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4352-4388. Parameter read accessors and Verify.
class PackageFormat_Parameter <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_PARAMETER_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetOwnedFunc(): UInt32 {
        return GetField(CHIRFB_PARAMETER_VT_OWNEDFUNC, 0u32)
    }

    func GetOwnedLambda(): UInt32 {
        return GetField(CHIRFB_PARAMETER_VT_OWNEDLAMBDA, 0u32)
    }

    func GetSrcCodeIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_PARAMETER_VT_SRCCODEIDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetAnnoInfo(): Option<PackageFormat_AnnoInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_PARAMETER_VT_ANNOINFO)) { Some(PackageFormat_AnnoInfo(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_PARAMETER_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_PARAMETER_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_PARAMETER_VT_OWNEDFUNC, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_PARAMETER_VT_OWNEDLAMBDA, 4) &&
            VerifyOffset(verifier, CHIRFB_PARAMETER_VT_SRCCODEIDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_PARAMETER_VT_SRCCODEIDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_PARAMETER_VT_ANNOINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_PARAMETER_VT_ANNOINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_AnnoInfo(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4453-4483. LocalVar read accessors and Verify.
class PackageFormat_LocalVar <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LOCAL_VAR_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetAssociatedExpr(): UInt32 {
        return GetField(CHIRFB_LOCAL_VAR_VT_ASSOCIATEDEXPR, 0u32)
    }

    func GetIsRetVal(): Bool {
        return GetField(CHIRFB_LOCAL_VAR_VT_ISRETVAL, false)
    }

    func GetSrcCodeIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_LOCAL_VAR_VT_SRCCODEIDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_LOCAL_VAR_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_LOCAL_VAR_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_LOCAL_VAR_VT_ASSOCIATEDEXPR, 4) &&
            VerifyField<Bool>(verifier, CHIRFB_LOCAL_VAR_VT_ISRETVAL, 1) &&
            VerifyOffset(verifier, CHIRFB_LOCAL_VAR_VT_SRCCODEIDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_LOCAL_VAR_VT_SRCCODEIDENTIFIER)) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4541-4591. GlobalValue read accessors and Verify.
class PackageFormat_GlobalValue <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetSrcCodeIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_SRCCODEIDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetRawMangledName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_RAWMANGLEDNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetPackageName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_PACKAGENAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetDeclaredParent(): UInt32 {
        return GetField(CHIRFB_GLOBAL_VALUE_VT_DECLAREDPARENT, 0u32)
    }

    func GetFeatures(): Option<Vector<Offset<FlatBufferString>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_FEATURES)) { Some(Vector<Offset<FlatBufferString>>(data, pointerPos)) } else { None }
    }

    func GetAnnoInfo(): Option<PackageFormat_AnnoInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VALUE_VT_ANNOINFO)) { Some(PackageFormat_AnnoInfo(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GLOBAL_VALUE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_SRCCODEIDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_GLOBAL_VALUE_VT_SRCCODEIDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_RAWMANGLEDNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_GLOBAL_VALUE_VT_RAWMANGLEDNAME)) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_PACKAGENAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_GLOBAL_VALUE_VT_PACKAGENAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_GLOBAL_VALUE_VT_DECLAREDPARENT, 4) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_FEATURES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_GLOBAL_VALUE_VT_FEATURES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(CHIRFB_GLOBAL_VALUE_VT_FEATURES)) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VALUE_VT_ANNOINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GLOBAL_VALUE_VT_ANNOINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_AnnoInfo(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4673-4692. GlobalVar read accessors and Verify.
class PackageFormat_GlobalVar <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_GlobalValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GLOBAL_VAR_VT_BASE)) { Some(PackageFormat_GlobalValue(data, pointerPos)) } else { None }
    }

    func GetInitializer(): UInt32 {
        return GetField(CHIRFB_GLOBAL_VAR_VT_INITIALIZER, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GLOBAL_VAR_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GLOBAL_VAR_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_GlobalValue(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_GLOBAL_VAR_VT_INITIALIZER, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4725-4750. FuncSigInfo read accessors and Verify.
class PackageFormat_FuncSigInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetFuncName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNC_SIG_INFO_VT_FUNCNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetFuncType(): UInt32 {
        return GetField(CHIRFB_FUNC_SIG_INFO_VT_FUNCTYPE, 0u32)
    }

    func GetGenericTypeParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNC_SIG_INFO_VT_GENERICTYPEPARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FUNC_SIG_INFO_VT_FUNCNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_FUNC_SIG_INFO_VT_FUNCNAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNC_SIG_INFO_VT_FUNCTYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_FUNC_SIG_INFO_VT_GENERICTYPEPARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FUNC_SIG_INFO_VT_GENERICTYPEPARAMS), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:4802-4890. Function read accessors and Verify.
class PackageFormat_Function <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_GlobalValue> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNCTION_VT_BASE)) { Some(PackageFormat_GlobalValue(data, pointerPos)) } else { None }
    }

    func GetGenericDecl(): UInt32 {
        return GetField(CHIRFB_FUNCTION_VT_GENERICDECL, 0u32)
    }

    func GetFuncKind(): UInt8 {
        return GetField(CHIRFB_FUNCTION_VT_FUNCKIND, 0u8)
    }

    func GetIsFastNative(): Bool {
        return GetField(CHIRFB_FUNCTION_VT_ISFASTNATIVE, false)
    }

    func GetIsCFFIWrapper(): Bool {
        return GetField(CHIRFB_FUNCTION_VT_ISCFFIWRAPPER, false)
    }

    func GetOriginalLambdaInfo(): Option<PackageFormat_FuncSigInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNCTION_VT_ORIGINALLAMBDAINFO)) { Some(PackageFormat_FuncSigInfo(data, pointerPos)) } else { None }
    }

    func GetGenericTypeParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNCTION_VT_GENERICTYPEPARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetParamDftValHostFunc(): UInt32 {
        return GetField(CHIRFB_FUNCTION_VT_PARAMDFTVALHOSTFUNC, 0u32)
    }

    func GetBody(): UInt32 {
        return GetField(CHIRFB_FUNCTION_VT_BODY, 0u32)
    }

    func GetParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNCTION_VT_PARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetRetVal(): UInt32 {
        return GetField(CHIRFB_FUNCTION_VT_RETVAL, 0u32)
    }

    func GetPropLoc(): Option<PackageFormat_DebugLocation> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNCTION_VT_PROPLOC)) { Some(PackageFormat_DebugLocation(data, pointerPos)) } else { None }
    }

    func GetLocalId(): UInt64 {
        return GetField(CHIRFB_FUNCTION_VT_LOCALID, 0u64)
    }

    func GetBlockId(): UInt64 {
        return GetField(CHIRFB_FUNCTION_VT_BLOCKID, 0u64)
    }

    func GetBlockGroupId(): UInt64 {
        return GetField(CHIRFB_FUNCTION_VT_BLOCKGROUPID, 0u64)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FUNCTION_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FUNCTION_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_GlobalValue(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNCTION_VT_GENERICDECL, 4) &&
            VerifyField<UInt8>(verifier, CHIRFB_FUNCTION_VT_FUNCKIND, 1) &&
            VerifyField<Bool>(verifier, CHIRFB_FUNCTION_VT_ISFASTNATIVE, 1) &&
            VerifyField<Bool>(verifier, CHIRFB_FUNCTION_VT_ISCFFIWRAPPER, 1) &&
            VerifyOffset(verifier, CHIRFB_FUNCTION_VT_ORIGINALLAMBDAINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FUNCTION_VT_ORIGINALLAMBDAINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncSigInfo(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_FUNCTION_VT_GENERICTYPEPARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FUNCTION_VT_GENERICTYPEPARAMS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNCTION_VT_PARAMDFTVALHOSTFUNC, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNCTION_VT_BODY, 4) &&
            VerifyOffset(verifier, CHIRFB_FUNCTION_VT_PARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_FUNCTION_VT_PARAMS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_FUNCTION_VT_RETVAL, 4) &&
            VerifyOffset(verifier, CHIRFB_FUNCTION_VT_PROPLOC) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FUNCTION_VT_PROPLOC), {tablePos: Int64, active: VerifierTemplate => PackageFormat_DebugLocation(data, tablePos).Verify(active)}) &&
            VerifyField<UInt64>(verifier, CHIRFB_FUNCTION_VT_LOCALID, 8) &&
            VerifyField<UInt64>(verifier, CHIRFB_FUNCTION_VT_BLOCKID, 8) &&
            VerifyField<UInt64>(verifier, CHIRFB_FUNCTION_VT_BLOCKGROUPID, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5026-5068. Block read accessors and Verify.
class PackageFormat_Block <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetParentGroup(): UInt32 {
        return GetField(CHIRFB_BLOCK_VT_PARENTGROUP, 0u32)
    }

    func GetExprs(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_VT_EXPRS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetPredecessors(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_VT_PREDECESSORS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetIsLandingPadBlock(): Bool {
        return GetField(CHIRFB_BLOCK_VT_ISLANDINGPADBLOCK, false)
    }

    func GetExceptionCatchList(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_VT_EXCEPTIONCATCHLIST)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BLOCK_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_BLOCK_VT_PARENTGROUP, 4) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_VT_EXPRS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BLOCK_VT_EXPRS), 4) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_VT_PREDECESSORS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BLOCK_VT_PREDECESSORS), 4) &&
            VerifyField<Bool>(verifier, CHIRFB_BLOCK_VT_ISLANDINGPADBLOCK, 1) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_VT_EXCEPTIONCATCHLIST) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BLOCK_VT_EXCEPTIONCATCHLIST), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5142-5177. BlockGroup read accessors and Verify.
class PackageFormat_BlockGroup <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Value> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_GROUP_VT_BASE)) { Some(PackageFormat_Value(data, pointerPos)) } else { None }
    }

    func GetEntryBlock(): UInt32 {
        return GetField(CHIRFB_BLOCK_GROUP_VT_ENTRYBLOCK, 0u32)
    }

    func GetBlocks(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BLOCK_GROUP_VT_BLOCKS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetOwnedFunc(): UInt32 {
        return GetField(CHIRFB_BLOCK_GROUP_VT_OWNEDFUNC, 0u32)
    }

    func GetOwnedExpression(): UInt32 {
        return GetField(CHIRFB_BLOCK_GROUP_VT_OWNEDEXPRESSION, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_GROUP_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BLOCK_GROUP_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Value(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_BLOCK_GROUP_VT_ENTRYBLOCK, 4) &&
            VerifyOffset(verifier, CHIRFB_BLOCK_GROUP_VT_BLOCKS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BLOCK_GROUP_VT_BLOCKS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_BLOCK_GROUP_VT_OWNEDFUNC, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_BLOCK_GROUP_VT_OWNEDEXPRESSION, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h union verifier switch for ValueElem.
func VerifyValueElem(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, kind: UInt8): Bool {
    return match (kind) {
        case 0u8 => true
        case 1u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_BoolLiteral(data, tablePos).Verify(active)})
        case 2u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_RuneLiteral(data, tablePos).Verify(active)})
        case 3u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_StringLiteral(data, tablePos).Verify(active)})
        case 4u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_IntLiteral(data, tablePos).Verify(active)})
        case 5u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_FloatLiteral(data, tablePos).Verify(active)})
        case 6u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_UnitLiteral(data, tablePos).Verify(active)})
        case 7u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_NullLiteral(data, tablePos).Verify(active)})
        case 8u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Parameter(data, tablePos).Verify(active)})
        case 9u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_LocalVar(data, tablePos).Verify(active)})
        case 10u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GlobalVar(data, tablePos).Verify(active)})
        case 11u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Function(data, tablePos).Verify(active)})
        case 12u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Block(data, tablePos).Verify(active)})
        case 13u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_BlockGroup(data, tablePos).Verify(active)})
        case _ => true
    }
}

func VerifyValueElemVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
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
        if (!VerifyValueElem(data, verifier, Some((valueVector.Get(index) as Int64).getOrThrow()), typeVector.Get(index, 0u8))) {
            return false
        }
        index++
    }
    return true
}
