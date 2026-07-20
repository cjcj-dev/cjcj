package cjcj::chir

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// PackageFormat_generated.h:2746-2765. Type read accessors and Verify.
class PackageFormat_Type <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetKind(): UInt8 {
        return GetField<UInt8>(CHIRFB_TYPE_VT_KIND, 0u8)
    }

    func GetArgTys(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_TYPE_VT_ARGTYS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, CHIRFB_TYPE_VT_KIND, 1) &&
            VerifyOffset(verifier, CHIRFB_TYPE_VT_ARGTYS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_TYPE_VT_ARGTYS), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:2809-2828. RawArrayType read accessors and Verify.
class PackageFormat_RawArrayType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Type> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_RAW_ARRAY_TYPE_VT_BASE)) { Some(PackageFormat_Type(data, pointerPos)) } else { None }
    }

    func GetDims(): UInt32 {
        return GetField<UInt32>(CHIRFB_RAW_ARRAY_TYPE_VT_DIMS, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_RAW_ARRAY_TYPE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_RAW_ARRAY_TYPE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_RAW_ARRAY_TYPE_VT_DIMS, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:2861-2880. VArrayType read accessors and Verify.
class PackageFormat_VArrayType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Type> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_V_ARRAY_TYPE_VT_BASE)) { Some(PackageFormat_Type(data, pointerPos)) } else { None }
    }

    func GetSize(): Int64 {
        return GetField<Int64>(CHIRFB_V_ARRAY_TYPE_VT_SIZE, 0)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_V_ARRAY_TYPE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_V_ARRAY_TYPE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)}) &&
            VerifyField<Int64>(verifier, CHIRFB_V_ARRAY_TYPE_VT_SIZE, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:2913-2937. FuncType read accessors and Verify.
class PackageFormat_FuncType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Type> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_FUNC_TYPE_VT_BASE)) { Some(PackageFormat_Type(data, pointerPos)) } else { None }
    }

    func GetIsCFuncType(): Bool {
        return GetField<Bool>(CHIRFB_FUNC_TYPE_VT_ISCFUNCTYPE, false)
    }

    func GetHasVarArg(): Bool {
        return GetField<Bool>(CHIRFB_FUNC_TYPE_VT_HASVARARG, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_FUNC_TYPE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_FUNC_TYPE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_FUNC_TYPE_VT_ISCFUNCTYPE, 1) &&
            VerifyField<Bool>(verifier, CHIRFB_FUNC_TYPE_VT_HASVARARG, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:2975-2994. CustomType read accessors and Verify.
class PackageFormat_CustomType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Type> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_VT_BASE)) { Some(PackageFormat_Type(data, pointerPos)) } else { None }
    }

    func GetCustomTypeDef(): UInt32 {
        return GetField<UInt32>(CHIRFB_CUSTOM_TYPE_VT_CUSTOMTYPEDEF, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_CUSTOM_TYPE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_CUSTOM_TYPE_VT_CUSTOMTYPEDEF, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3027-3059. GenericType read accessors and Verify.
class PackageFormat_GenericType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Type> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GENERIC_TYPE_VT_BASE)) { Some(PackageFormat_Type(data, pointerPos)) } else { None }
    }

    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GENERIC_TYPE_VT_IDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetSrcCodeIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GENERIC_TYPE_VT_SRCCODEIDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetUpperBounds(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_GENERIC_TYPE_VT_UPPERBOUNDS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_GENERIC_TYPE_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_GENERIC_TYPE_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_GENERIC_TYPE_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_GENERIC_TYPE_VT_IDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_GENERIC_TYPE_VT_SRCCODEIDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_GENERIC_TYPE_VT_SRCCODEIDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_GENERIC_TYPE_VT_UPPERBOUNDS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_GENERIC_TYPE_VT_UPPERBOUNDS), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3119-3137. Pos read accessors and Verify.
class PackageFormat_Pos <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetLine(): UInt32 {
        return GetField<UInt32>(CHIRFB_POS_VT_LINE, 0u32)
    }

    func GetColumn(): UInt32 {
        return GetField<UInt32>(CHIRFB_POS_VT_COLUMN, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, CHIRFB_POS_VT_LINE, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_POS_VT_COLUMN, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3170-3207. DebugLocation read accessors and Verify.
class PackageFormat_DebugLocation <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetFilePath(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_LOCATION_VT_FILEPATH)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetFileId(): UInt32 {
        return GetField<UInt32>(CHIRFB_DEBUG_LOCATION_VT_FILEID, 0u32)
    }

    func GetBeginPos(): Option<PackageFormat_Pos> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_LOCATION_VT_BEGINPOS)) { Some(PackageFormat_Pos(data, pointerPos)) } else { None }
    }

    func GetEndPos(): Option<PackageFormat_Pos> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_LOCATION_VT_ENDPOS)) { Some(PackageFormat_Pos(data, pointerPos)) } else { None }
    }

    func GetScope(): Option<Vector<Int32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_DEBUG_LOCATION_VT_SCOPE)) { Some(Vector<Int32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_LOCATION_VT_FILEPATH) &&
            verifier.VerifyString(GetPointer(CHIRFB_DEBUG_LOCATION_VT_FILEPATH)) &&
            VerifyField<UInt32>(verifier, CHIRFB_DEBUG_LOCATION_VT_FILEID, 4) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_LOCATION_VT_BEGINPOS) &&
            verifier.VerifyTable(GetPointer(CHIRFB_DEBUG_LOCATION_VT_BEGINPOS), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Pos(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_LOCATION_VT_ENDPOS) &&
            verifier.VerifyTable(GetPointer(CHIRFB_DEBUG_LOCATION_VT_ENDPOS), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Pos(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_DEBUG_LOCATION_VT_SCOPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_DEBUG_LOCATION_VT_SCOPE), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3273-3286. LinkTypeInfo read accessors and Verify.
class PackageFormat_LinkTypeInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetLinkage(): Int16 {
        return GetField<Int16>(CHIRFB_LINK_TYPE_INFO_VT_LINKAGE, 0)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int16>(verifier, CHIRFB_LINK_TYPE_INFO_VT_LINKAGE, 2) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3314-3327. SkipCheck read accessors and Verify.
class PackageFormat_SkipCheck <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetSkipKind(): UInt8 {
        return GetField<UInt8>(CHIRFB_SKIP_CHECK_VT_SKIPKIND, 0u8)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, CHIRFB_SKIP_CHECK_VT_SKIPKIND, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3355-3368. NeedCheckArrayBound read accessors and Verify.
class PackageFormat_NeedCheckArrayBound <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetNeed(): Bool {
        return GetField<Bool>(CHIRFB_NEED_CHECK_ARRAY_BOUND_VT_NEED, true)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_NEED_CHECK_ARRAY_BOUND_VT_NEED, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3396-3409. NeedCheckCast read accessors and Verify.
class PackageFormat_NeedCheckCast <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetNeed(): Bool {
        return GetField<Bool>(CHIRFB_NEED_CHECK_CAST_VT_NEED, true)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_NEED_CHECK_CAST_VT_NEED, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3437-3450. NeverOverflowInfo read accessors and Verify.
class PackageFormat_NeverOverflowInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetNeverOverflow(): Bool {
        return GetField<Bool>(CHIRFB_NEVER_OVERFLOW_INFO_VT_NEVEROVERFLOW, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_NEVER_OVERFLOW_INFO_VT_NEVEROVERFLOW, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3478-3491. GeneratedFromForIn read accessors and Verify.
class PackageFormat_GeneratedFromForIn <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetValue(): Bool {
        return GetField<Bool>(CHIRFB_GENERATED_FROM_FOR_IN_VT_VALUE, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_GENERATED_FROM_FOR_IN_VT_VALUE, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3519-3532. IsAutoEnvClass read accessors and Verify.
class PackageFormat_IsAutoEnvClass <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetValue(): Bool {
        return GetField<Bool>(CHIRFB_IS_AUTO_ENV_CLASS_VT_VALUE, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_IS_AUTO_ENV_CLASS_VT_VALUE, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3560-3573. IsCapturedClassInCC read accessors and Verify.
class PackageFormat_IsCapturedClassInCC <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetValue(): Bool {
        return GetField<Bool>(CHIRFB_IS_CAPTURED_CLASS_IN_CC_VT_VALUE, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, CHIRFB_IS_CAPTURED_CLASS_IN_CC_VT_VALUE, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3601-3614. EnumCaseIndex read accessors and Verify.
class PackageFormat_EnumCaseIndex <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetIndex(): Int64 {
        return GetField<Int64>(CHIRFB_ENUM_CASE_INDEX_VT_INDEX, -1)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int64>(verifier, CHIRFB_ENUM_CASE_INDEX_VT_INDEX, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3642-3655. VirMethodOffset read accessors and Verify.
class PackageFormat_VirMethodOffset <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetOffset(): Int64 {
        return GetField<Int64>(CHIRFB_VIR_METHOD_OFFSET_VT_OFFSET, -1)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int64>(verifier, CHIRFB_VIR_METHOD_OFFSET_VT_OFFSET, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3683-3696. WrappedRawMethod read accessors and Verify.
class PackageFormat_WrappedRawMethod <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetRawMethod(): UInt32 {
        return GetField<UInt32>(CHIRFB_WRAPPED_RAW_METHOD_VT_RAWMETHOD, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, CHIRFB_WRAPPED_RAW_METHOD_VT_RAWMETHOD, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3724-3737. OverrideSrcFuncType read accessors and Verify.
class PackageFormat_OverrideSrcFuncType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetType(): UInt32 {
        return GetField<UInt32>(CHIRFB_OVERRIDE_SRC_FUNC_TYPE_VT_TYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, CHIRFB_OVERRIDE_SRC_FUNC_TYPE_VT_TYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:3765-3797. Base read accessors and Verify.
class PackageFormat_Base <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetAnnos_type(): Option<Vector<UInt8>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BASE_VT_ANNOS_TYPE)) { Some(Vector<UInt8>(data, pointerPos)) } else { None }
    }

    func GetAnnos(): Option<Vector<Offset<Any>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BASE_VT_ANNOS)) { Some(Vector<Offset<Any>>(data, pointerPos)) } else { None }
    }

    func GetLoc(): Option<PackageFormat_DebugLocation> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_BASE_VT_LOC)) { Some(PackageFormat_DebugLocation(data, pointerPos)) } else { None }
    }

    func GetAttributes(): UInt64 {
        return GetField<UInt64>(CHIRFB_BASE_VT_ATTRIBUTES, 0u64)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_BASE_VT_ANNOS_TYPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BASE_VT_ANNOS_TYPE), 1) &&
            VerifyOffset(verifier, CHIRFB_BASE_VT_ANNOS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_BASE_VT_ANNOS), 4) &&
            VerifyAnnotationVector(data, verifier, GetPointer(CHIRFB_BASE_VT_ANNOS), GetPointer(CHIRFB_BASE_VT_ANNOS_TYPE)) &&
            VerifyOffset(verifier, CHIRFB_BASE_VT_LOC) &&
            verifier.VerifyTable(GetPointer(CHIRFB_BASE_VT_LOC), {tablePos: Int64, active: VerifierTemplate => PackageFormat_DebugLocation(data, tablePos).Verify(active)}) &&
            VerifyField<UInt64>(verifier, CHIRFB_BASE_VT_ATTRIBUTES, 8) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5242-5269. CustomAnnoInstance read accessors and Verify.
class PackageFormat_CustomAnnoInstance <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetAnnoClassName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ANNOCLASSNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetArgValues(): Option<Vector<Offset<FlatBufferString>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ARGVALUES)) { Some(Vector<Offset<FlatBufferString>>(data, pointerPos)) } else { None }
    }

    func GetLoc(): Option<PackageFormat_DebugLocation> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_LOC)) { Some(PackageFormat_DebugLocation(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ANNOCLASSNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ANNOCLASSNAME)) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ARGVALUES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ARGVALUES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_ARGVALUES)) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_ANNO_INSTANCE_VT_LOC) &&
            verifier.VerifyTable(GetPointer(CHIRFB_CUSTOM_ANNO_INSTANCE_VT_LOC), {tablePos: Int64, active: VerifierTemplate => PackageFormat_DebugLocation(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5321-5342. AnnoInfo read accessors and Verify.
class PackageFormat_AnnoInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetMangledName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ANNO_INFO_VT_MANGLEDNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetAnnoInstances(): Option<Vector<Offset<PackageFormat_CustomAnnoInstance>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ANNO_INFO_VT_ANNOINSTANCES)) { Some(Vector<Offset<PackageFormat_CustomAnnoInstance>>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_ANNO_INFO_VT_MANGLEDNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_ANNO_INFO_VT_MANGLEDNAME)) &&
            VerifyOffset(verifier, CHIRFB_ANNO_INFO_VT_ANNOINSTANCES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_ANNO_INFO_VT_ANNOINSTANCES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(CHIRFB_ANNO_INFO_VT_ANNOINSTANCES), {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomAnnoInstance(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5387-5439. MemberVarInfo read accessors and Verify.
class PackageFormat_MemberVarInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_NAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetRawMangledName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_RAWMANGLEDNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetType(): UInt32 {
        return GetField<UInt32>(CHIRFB_MEMBER_VAR_INFO_VT_TYPE, 0u32)
    }

    func GetAttributes(): UInt64 {
        return GetField<UInt64>(CHIRFB_MEMBER_VAR_INFO_VT_ATTRIBUTES, 0u64)
    }

    func GetLoc(): Option<PackageFormat_DebugLocation> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_LOC)) { Some(PackageFormat_DebugLocation(data, pointerPos)) } else { None }
    }

    func GetAnnoInfo(): Option<PackageFormat_AnnoInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_ANNOINFO)) { Some(PackageFormat_AnnoInfo(data, pointerPos)) } else { None }
    }

    func GetInitializerFunc(): UInt32 {
        return GetField<UInt32>(CHIRFB_MEMBER_VAR_INFO_VT_INITIALIZERFUNC, 0u32)
    }

    func GetOuterDef(): UInt32 {
        return GetField<UInt32>(CHIRFB_MEMBER_VAR_INFO_VT_OUTERDEF, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_MEMBER_VAR_INFO_VT_NAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_NAME)) &&
            VerifyOffset(verifier, CHIRFB_MEMBER_VAR_INFO_VT_RAWMANGLEDNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_RAWMANGLEDNAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_MEMBER_VAR_INFO_VT_TYPE, 4) &&
            VerifyField<UInt64>(verifier, CHIRFB_MEMBER_VAR_INFO_VT_ATTRIBUTES, 8) &&
            VerifyOffset(verifier, CHIRFB_MEMBER_VAR_INFO_VT_LOC) &&
            verifier.VerifyTable(GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_LOC), {tablePos: Int64, active: VerifierTemplate => PackageFormat_DebugLocation(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_MEMBER_VAR_INFO_VT_ANNOINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_MEMBER_VAR_INFO_VT_ANNOINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_AnnoInfo(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_MEMBER_VAR_INFO_VT_INITIALIZERFUNC, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_MEMBER_VAR_INFO_VT_OUTERDEF, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5526-5576. VirtualMethodInfo read accessors and Verify.
class PackageFormat_VirtualMethodInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetFuncName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_VIRTUAL_METHOD_INFO_VT_FUNCNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetSigType(): UInt32 {
        return GetField<UInt32>(CHIRFB_VIRTUAL_METHOD_INFO_VT_SIGTYPE, 0u32)
    }

    func GetMethodGenericTypeParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_VIRTUAL_METHOD_INFO_VT_METHODGENERICTYPEPARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetInstance(): UInt32 {
        return GetField<UInt32>(CHIRFB_VIRTUAL_METHOD_INFO_VT_INSTANCE, 0u32)
    }

    func GetAttributes(): UInt64 {
        return GetField<UInt64>(CHIRFB_VIRTUAL_METHOD_INFO_VT_ATTRIBUTES, 0u64)
    }

    func GetOriginalType(): UInt32 {
        return GetField<UInt32>(CHIRFB_VIRTUAL_METHOD_INFO_VT_ORIGINALTYPE, 0u32)
    }

    func GetParentType(): UInt32 {
        return GetField<UInt32>(CHIRFB_VIRTUAL_METHOD_INFO_VT_PARENTTYPE, 0u32)
    }

    func GetReturnType(): UInt32 {
        return GetField<UInt32>(CHIRFB_VIRTUAL_METHOD_INFO_VT_RETURNTYPE, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_FUNCNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_VIRTUAL_METHOD_INFO_VT_FUNCNAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_SIGTYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_METHODGENERICTYPEPARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_VIRTUAL_METHOD_INFO_VT_METHODGENERICTYPEPARAMS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_INSTANCE, 4) &&
            VerifyField<UInt64>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_ATTRIBUTES, 8) &&
            VerifyField<UInt32>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_ORIGINALTYPE, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_PARENTTYPE, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_VIRTUAL_METHOD_INFO_VT_RETURNTYPE, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5663-5683. VTableInType read accessors and Verify.
class PackageFormat_VTableInType <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetSrcParentType(): UInt32 {
        return GetField<UInt32>(CHIRFB_V_TABLE_IN_TYPE_VT_SRCPARENTTYPE, 0u32)
    }

    func GetVirtualMethods(): Option<Vector<Offset<PackageFormat_VirtualMethodInfo>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_V_TABLE_IN_TYPE_VT_VIRTUALMETHODS)) { Some(Vector<Offset<PackageFormat_VirtualMethodInfo>>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, CHIRFB_V_TABLE_IN_TYPE_VT_SRCPARENTTYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_V_TABLE_IN_TYPE_VT_VIRTUALMETHODS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_V_TABLE_IN_TYPE_VT_VIRTUALMETHODS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(CHIRFB_V_TABLE_IN_TYPE_VT_VIRTUALMETHODS), {tablePos: Int64, active: VerifierTemplate => PackageFormat_VirtualMethodInfo(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5727-5822. CustomTypeDef read accessors and Verify.
class PackageFormat_CustomTypeDef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_Base> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_BASE)) { Some(PackageFormat_Base(data, pointerPos)) } else { None }
    }

    func GetKind(): UInt8 {
        return GetField<UInt8>(CHIRFB_CUSTOM_TYPE_DEF_VT_KIND, 0u8)
    }

    func GetCustomTypeDefID(): UInt32 {
        return GetField<UInt32>(CHIRFB_CUSTOM_TYPE_DEF_VT_CUSTOMTYPEDEFID, 0u32)
    }

    func GetSrcCodeIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_SRCCODEIDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_IDENTIFIER)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetPackageName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_PACKAGENAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetType(): UInt32 {
        return GetField<UInt32>(CHIRFB_CUSTOM_TYPE_DEF_VT_TYPE, 0u32)
    }

    func GetGenericDecl(): UInt32 {
        return GetField<UInt32>(CHIRFB_CUSTOM_TYPE_DEF_VT_GENERICDECL, 0u32)
    }

    func GetMethods(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_METHODS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetImplementedInterfaces(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_IMPLEMENTEDINTERFACES)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetInstanceMemberVars(): Option<Vector<Offset<PackageFormat_MemberVarInfo>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEMEMBERVARS)) { Some(Vector<Offset<PackageFormat_MemberVarInfo>>(data, pointerPos)) } else { None }
    }

    func GetStaticMemberVars(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_STATICMEMBERVARS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetAnnoInfo(): Option<PackageFormat_AnnoInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_ANNOINFO)) { Some(PackageFormat_AnnoInfo(data, pointerPos)) } else { None }
    }

    func GetVtable(): Option<Vector<Offset<PackageFormat_VTableInType>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_VTABLE)) { Some(Vector<Offset<PackageFormat_VTableInType>>(data, pointerPos)) } else { None }
    }

    func GetInstanceVarInitFunc(): UInt32 {
        return GetField<UInt32>(CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEVARINITFUNC, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_Base(data, tablePos).Verify(active)}) &&
            VerifyField<UInt8>(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_KIND, 1) &&
            VerifyField<UInt32>(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_CUSTOMTYPEDEFID, 4) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_SRCCODEIDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_SRCCODEIDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_IDENTIFIER)) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_PACKAGENAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_PACKAGENAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_TYPE, 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_GENERICDECL, 4) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_METHODS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_METHODS), 4) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_IMPLEMENTEDINTERFACES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_IMPLEMENTEDINTERFACES), 4) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEMEMBERVARS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEMEMBERVARS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEMEMBERVARS), {tablePos: Int64, active: VerifierTemplate => PackageFormat_MemberVarInfo(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_STATICMEMBERVARS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_STATICMEMBERVARS), 4) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_ANNOINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_ANNOINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_AnnoInfo(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_VTABLE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_VTABLE), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(CHIRFB_CUSTOM_TYPE_DEF_VT_VTABLE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_VTableInType(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_CUSTOM_TYPE_DEF_VT_INSTANCEVARINITFUNC, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:5964-5995. EnumCtorInfo read accessors and Verify.
class PackageFormat_EnumCtorInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetSrcCodeName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_SRCCODENAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetMangledName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_MANGLEDNAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetFuncType(): UInt32 {
        return GetField<UInt32>(CHIRFB_ENUM_CTOR_INFO_VT_FUNCTYPE, 0u32)
    }

    func GetAnnoInfo(): Option<PackageFormat_AnnoInfo> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_ANNOINFO)) { Some(PackageFormat_AnnoInfo(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_ENUM_CTOR_INFO_VT_SRCCODENAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_SRCCODENAME)) &&
            VerifyOffset(verifier, CHIRFB_ENUM_CTOR_INFO_VT_MANGLEDNAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_MANGLEDNAME)) &&
            VerifyField<UInt32>(verifier, CHIRFB_ENUM_CTOR_INFO_VT_FUNCTYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_ENUM_CTOR_INFO_VT_ANNOINFO) &&
            verifier.VerifyTable(GetPointer(CHIRFB_ENUM_CTOR_INFO_VT_ANNOINFO), {tablePos: Int64, active: VerifierTemplate => PackageFormat_AnnoInfo(data, tablePos).Verify(active)}) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6054-6080. EnumDef read accessors and Verify.
class PackageFormat_EnumDef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_CustomTypeDef> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ENUM_DEF_VT_BASE)) { Some(PackageFormat_CustomTypeDef(data, pointerPos)) } else { None }
    }

    func GetCtors(): Option<Vector<Offset<PackageFormat_EnumCtorInfo>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_ENUM_DEF_VT_CTORS)) { Some(Vector<Offset<PackageFormat_EnumCtorInfo>>(data, pointerPos)) } else { None }
    }

    func GetNonExhaustive(): Bool {
        return GetField<Bool>(CHIRFB_ENUM_DEF_VT_NONEXHAUSTIVE, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_ENUM_DEF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_ENUM_DEF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomTypeDef(data, tablePos).Verify(active)}) &&
            VerifyOffset(verifier, CHIRFB_ENUM_DEF_VT_CTORS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_ENUM_DEF_VT_CTORS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(CHIRFB_ENUM_DEF_VT_CTORS), {tablePos: Int64, active: VerifierTemplate => PackageFormat_EnumCtorInfo(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_ENUM_DEF_VT_NONEXHAUSTIVE, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6131-6150. StructDef read accessors and Verify.
class PackageFormat_StructDef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_CustomTypeDef> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_STRUCT_DEF_VT_BASE)) { Some(PackageFormat_CustomTypeDef(data, pointerPos)) } else { None }
    }

    func GetIsCStruct(): Bool {
        return GetField<Bool>(CHIRFB_STRUCT_DEF_VT_ISCSTRUCT, false)
    }

    func GetAlignment(): Int64 {
        return GetField<Int64>(CHIRFB_STRUCT_DEF_VT_ALIGNMENT, 0)
    }

    func GetIsPacked(): Bool {
        return GetField<Bool>(CHIRFB_STRUCT_DEF_VT_ISPACKED, false)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_STRUCT_DEF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_STRUCT_DEF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomTypeDef(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_STRUCT_DEF_VT_ISCSTRUCT, 1) &&
            VerifyField<Int64>(verifier, CHIRFB_STRUCT_DEF_VT_ALIGNMENT, 8) &&
            VerifyField<Bool>(verifier, CHIRFB_STRUCT_DEF_VT_ISPACKED, 1) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6183-6208. ExtendDef read accessors and Verify.
class PackageFormat_ExtendDef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_CustomTypeDef> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_EXTEND_DEF_VT_BASE)) { Some(PackageFormat_CustomTypeDef(data, pointerPos)) } else { None }
    }

    func GetExtendedType(): UInt32 {
        return GetField<UInt32>(CHIRFB_EXTEND_DEF_VT_EXTENDEDTYPE, 0u32)
    }

    func GetGenericParams(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_EXTEND_DEF_VT_GENERICPARAMS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_EXTEND_DEF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_EXTEND_DEF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomTypeDef(data, tablePos).Verify(active)}) &&
            VerifyField<UInt32>(verifier, CHIRFB_EXTEND_DEF_VT_EXTENDEDTYPE, 4) &&
            VerifyOffset(verifier, CHIRFB_EXTEND_DEF_VT_GENERICPARAMS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_EXTEND_DEF_VT_GENERICPARAMS), 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h:6259-6294. ClassDef read accessors and Verify.
class PackageFormat_ClassDef <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetBase(): Option<PackageFormat_CustomTypeDef> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CLASS_DEF_VT_BASE)) { Some(PackageFormat_CustomTypeDef(data, pointerPos)) } else { None }
    }

    func GetIsClass(): Bool {
        return GetField<Bool>(CHIRFB_CLASS_DEF_VT_ISCLASS, false)
    }

    func GetIsAnnotation(): Bool {
        return GetField<Bool>(CHIRFB_CLASS_DEF_VT_ISANNOTATION, false)
    }

    func GetAnnotationTargets(): Option<Vector<UInt32>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CLASS_DEF_VT_ANNOTATIONTARGETS)) { Some(Vector<UInt32>(data, pointerPos)) } else { None }
    }

    func GetSuperClass(): UInt32 {
        return GetField<UInt32>(CHIRFB_CLASS_DEF_VT_SUPERCLASS, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_CLASS_DEF_VT_BASE) &&
            verifier.VerifyTable(GetPointer(CHIRFB_CLASS_DEF_VT_BASE), {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomTypeDef(data, tablePos).Verify(active)}) &&
            VerifyField<Bool>(verifier, CHIRFB_CLASS_DEF_VT_ISCLASS, 1) &&
            VerifyField<Bool>(verifier, CHIRFB_CLASS_DEF_VT_ISANNOTATION, 1) &&
            VerifyOffset(verifier, CHIRFB_CLASS_DEF_VT_ANNOTATIONTARGETS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CLASS_DEF_VT_ANNOTATIONTARGETS), 4) &&
            VerifyField<UInt32>(verifier, CHIRFB_CLASS_DEF_VT_SUPERCLASS, 4) &&
            verifier.EndTable()
    }
}

// PackageFormat_generated.h union verifier switch for Annotation.
func VerifyAnnotation(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, kind: UInt8): Bool {
    return match (kind) {
        case 0u8 => true
        case 1u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_NeedCheckArrayBound(data, tablePos).Verify(active)})
        case 2u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_NeedCheckCast(data, tablePos).Verify(active)})
        case 3u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_DebugLocation(data, tablePos).Verify(active)})
        case 4u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GeneratedFromForIn(data, tablePos).Verify(active)})
        case 5u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_IsAutoEnvClass(data, tablePos).Verify(active)})
        case 6u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_IsCapturedClassInCC(data, tablePos).Verify(active)})
        case 7u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_LinkTypeInfo(data, tablePos).Verify(active)})
        case 8u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_SkipCheck(data, tablePos).Verify(active)})
        case 9u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_NeverOverflowInfo(data, tablePos).Verify(active)})
        case 10u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_EnumCaseIndex(data, tablePos).Verify(active)})
        case 11u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_VirMethodOffset(data, tablePos).Verify(active)})
        case 12u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_WrappedRawMethod(data, tablePos).Verify(active)})
        case 13u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_OverrideSrcFuncType(data, tablePos).Verify(active)})
        case _ => true
    }
}

func VerifyAnnotationVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
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
        if (!VerifyAnnotation(data, verifier, Some((valueVector.Get(index) as Int64).getOrThrow()), (typeVector.Get(index) as UInt8).getOrThrow())) {
            return false
        }
        index++
    }
    return true
}

// PackageFormat_generated.h union verifier switch for TypeElem.
func VerifyTypeElem(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, kind: UInt8): Bool {
    return match (kind) {
        case 0u8 => true
        case 1u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_Type(data, tablePos).Verify(active)})
        case 2u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_RawArrayType(data, tablePos).Verify(active)})
        case 3u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_VArrayType(data, tablePos).Verify(active)})
        case 4u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_FuncType(data, tablePos).Verify(active)})
        case 5u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_CustomType(data, tablePos).Verify(active)})
        case 6u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_GenericType(data, tablePos).Verify(active)})
        case _ => true
    }
}

func VerifyTypeElemVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
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
        if (!VerifyTypeElem(data, verifier, Some((valueVector.Get(index) as Int64).getOrThrow()), (typeVector.Get(index) as UInt8).getOrThrow())) {
            return false
        }
        index++
    }
    return true
}

// PackageFormat_generated.h union verifier switch for CustomTypeDefElem.
func VerifyCustomTypeDefElem(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, kind: UInt8): Bool {
    return match (kind) {
        case 0u8 => true
        case 1u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_EnumDef(data, tablePos).Verify(active)})
        case 2u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_StructDef(data, tablePos).Verify(active)})
        case 3u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_ClassDef(data, tablePos).Verify(active)})
        case 4u8 => verifier.VerifyTable(obj, {tablePos: Int64, active: VerifierTemplate => PackageFormat_ExtendDef(data, tablePos).Verify(active)})
        case _ => true
    }
}

func VerifyCustomTypeDefElemVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
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
        if (!VerifyCustomTypeDefElem(data, verifier, Some((valueVector.Get(index) as Int64).getOrThrow()), (typeVector.Get(index) as UInt8).getOrThrow())) {
            return false
        }
        index++
    }
    return true
}
