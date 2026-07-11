package cjcj::modules

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// FlatBuffers read/verify bindings for the 58 tables of ModuleFormat.fbs.
// Each class mirrors the accessors and Verify() body of the matching struct in
// ModuleFormat_generated.h. Struct fields use the readers in
// ModuleFormatStructs.cj (size/align cited per struct: Position 20/4,
// DeclHash 40/8). Vectors of offsets (tables/strings) surface as
// Vector<Offset<Any>>; vectors of scalars as Vector<scalar>.

// ModuleFormat_generated.h:1983-2056 (FullId).
class PackageFormat_FullId <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetPkgId(): Int32 { return GetField<Int32>(MF_FULL_ID_VT_PKGID, 0) }
    func GetDecl(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_FULL_ID_VT_DECL)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetIndex(): UInt32 { return GetField<UInt32>(MF_FULL_ID_VT_INDEX, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int32>(verifier, MF_FULL_ID_VT_PKGID, 4) &&
            VerifyOffset(verifier, MF_FULL_ID_VT_DECL) &&
            verifier.VerifyString(GetPointer(MF_FULL_ID_VT_DECL)) &&
            VerifyField<UInt32>(verifier, MF_FULL_ID_VT_INDEX, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2058-2092 (Constraint).
class PackageFormat_Constraint <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_CONSTRAINT_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_CONSTRAINT_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetType(): UInt32 { return GetField<UInt32>(MF_CONSTRAINT_VT_TYPE, 0u32) }
    func GetUppers(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_CONSTRAINT_VT_UPPERS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetIsImplicitlyIntroduced(): Bool { return GetField<Bool>(MF_CONSTRAINT_VT_ISIMPLICITLYINTRODUCED, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyStructField(verifier, MF_CONSTRAINT_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_CONSTRAINT_VT_END, 20, 4) &&
            VerifyField<UInt32>(verifier, MF_CONSTRAINT_VT_TYPE, 4) &&
            VerifyOffset(verifier, MF_CONSTRAINT_VT_UPPERS) &&
            verifier.VerifyVector(GetPointer(MF_CONSTRAINT_VT_UPPERS), 4) &&
            VerifyField<Bool>(verifier, MF_CONSTRAINT_VT_ISIMPLICITLYINTRODUCED, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2157-2178 (Generic).
class PackageFormat_Generic <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetTypeParameters(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_GENERIC_VT_TYPEPARAMETERS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetConstraints(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_GENERIC_VT_CONSTRAINTS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_GENERIC_VT_TYPEPARAMETERS) &&
            verifier.VerifyVector(GetPointer(MF_GENERIC_VT_TYPEPARAMETERS), 4) &&
            VerifyOffset(verifier, MF_GENERIC_VT_CONSTRAINTS) &&
            verifier.VerifyVector(GetPointer(MF_GENERIC_VT_CONSTRAINTS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_GENERIC_VT_CONSTRAINTS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Constraint(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2223-2244 (FuncParamList).
class PackageFormat_FuncParamList <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetParams(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_FUNC_PARAM_LIST_VT_PARAMS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetDesugars(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_FUNC_PARAM_LIST_VT_DESUGARS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FUNC_PARAM_LIST_VT_PARAMS) &&
            verifier.VerifyVector(GetPointer(MF_FUNC_PARAM_LIST_VT_PARAMS), 4) &&
            VerifyOffset(verifier, MF_FUNC_PARAM_LIST_VT_DESUGARS) &&
            verifier.VerifyVector(GetPointer(MF_FUNC_PARAM_LIST_VT_DESUGARS), 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2288-2320 (FuncBody).
class PackageFormat_FuncBody <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetParamLists(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_FUNC_BODY_VT_PARAMLISTS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetRetType(): UInt32 { return GetField<UInt32>(MF_FUNC_BODY_VT_RETTYPE, 0u32) }
    func GetBody(): UInt32 { return GetField<UInt32>(MF_FUNC_BODY_VT_BODY, 0u32) }
    func GetAlways(): Bool { return GetField<Bool>(MF_FUNC_BODY_VT_ALWAYS, false) }
    func GetCaptureKind(): UInt8 { return GetField<UInt8>(MF_FUNC_BODY_VT_CAPTUREKIND, 0u8) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FUNC_BODY_VT_PARAMLISTS) &&
            verifier.VerifyVector(GetPointer(MF_FUNC_BODY_VT_PARAMLISTS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_FUNC_BODY_VT_PARAMLISTS),
                {p: Int64, v: VerifierTemplate => PackageFormat_FuncParamList(data, p).Verify(v)}) &&
            VerifyField<UInt32>(verifier, MF_FUNC_BODY_VT_RETTYPE, 4) &&
            VerifyField<UInt32>(verifier, MF_FUNC_BODY_VT_BODY, 4) &&
            VerifyField<Bool>(verifier, MF_FUNC_BODY_VT_ALWAYS, 1) &&
            VerifyField<UInt8>(verifier, MF_FUNC_BODY_VT_CAPTUREKIND, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2388-2409 (ArrayValue). val is [ConstValue].
class PackageFormat_ArrayValue <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetValType(): Option<Vector<UInt8>> {
        return if (let Some(p) <- GetPointer(MF_ARRAY_VALUE_VT_VAL_TYPE)) { Some(Vector<UInt8>(data, p)) } else { None }
    }
    func GetVal(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_ARRAY_VALUE_VT_VAL)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_ARRAY_VALUE_VT_VAL_TYPE) &&
            verifier.VerifyVector(GetPointer(MF_ARRAY_VALUE_VT_VAL_TYPE), 1) &&
            VerifyOffset(verifier, MF_ARRAY_VALUE_VT_VAL) &&
            verifier.VerifyVector(GetPointer(MF_ARRAY_VALUE_VT_VAL), 4) &&
            VerifyConstValueVector(data, verifier, GetPointer(MF_ARRAY_VALUE_VT_VAL), GetPointer(MF_ARRAY_VALUE_VT_VAL_TYPE)) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2454-2524 (MemberValue). value is ConstValue union.
class PackageFormat_MemberValue <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetField_(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_MEMBER_VALUE_VT_FIELD)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetType(): UInt32 { return GetField<UInt32>(MF_MEMBER_VALUE_VT_TYPE, 0u32) }
    func GetValueType(): UInt8 { return GetField<UInt8>(MF_MEMBER_VALUE_VT_VALUE_TYPE, 0u8) }
    func GetValue(): Option<Int64> { return GetPointer(MF_MEMBER_VALUE_VT_VALUE) }

    func GetValueAsInt8Value(): Option<PackageFormat_Int8Value> {
        return if (GetValueType() == MF_CONST_VALUE_INT8_VALUE) { WrapInt8Value(data, GetValue()) } else { None }
    }
    func GetValueAsUInt8Value(): Option<PackageFormat_UInt8Value> {
        return if (GetValueType() == MF_CONST_VALUE_UINT8_VALUE) { WrapUInt8Value(data, GetValue()) } else { None }
    }
    func GetValueAsInt16Value(): Option<PackageFormat_Int16Value> {
        return if (GetValueType() == MF_CONST_VALUE_INT16_VALUE) { WrapInt16Value(data, GetValue()) } else { None }
    }
    func GetValueAsUInt16Value(): Option<PackageFormat_UInt16Value> {
        return if (GetValueType() == MF_CONST_VALUE_UINT16_VALUE) { WrapUInt16Value(data, GetValue()) } else { None }
    }
    func GetValueAsInt32Value(): Option<PackageFormat_Int32Value> {
        return if (GetValueType() == MF_CONST_VALUE_INT32_VALUE) { WrapInt32Value(data, GetValue()) } else { None }
    }
    func GetValueAsUInt32Value(): Option<PackageFormat_UInt32Value> {
        return if (GetValueType() == MF_CONST_VALUE_UINT32_VALUE) { WrapUInt32Value(data, GetValue()) } else { None }
    }
    func GetValueAsInt64Value(): Option<PackageFormat_Int64Value> {
        return if (GetValueType() == MF_CONST_VALUE_INT64_VALUE) { WrapInt64Value(data, GetValue()) } else { None }
    }
    func GetValueAsUInt64Value(): Option<PackageFormat_UInt64Value> {
        return if (GetValueType() == MF_CONST_VALUE_UINT64_VALUE) { WrapUInt64Value(data, GetValue()) } else { None }
    }
    func GetValueAsFloat32Value(): Option<PackageFormat_Float32Value> {
        return if (GetValueType() == MF_CONST_VALUE_FLOAT32_VALUE) { WrapFloat32Value(data, GetValue()) } else { None }
    }
    func GetValueAsFloat64Value(): Option<PackageFormat_Float64Value> {
        return if (GetValueType() == MF_CONST_VALUE_FLOAT64_VALUE) { WrapFloat64Value(data, GetValue()) } else { None }
    }
    func GetValueAsArrayValue(): Option<PackageFormat_ArrayValue> {
        return if (GetValueType() == MF_CONST_VALUE_ARRAY_VALUE) { WrapArrayValue(data, GetValue()) } else { None }
    }
    func GetValueAsStringValue(): Option<FlatBufferString> {
        return if (GetValueType() == MF_CONST_VALUE_STRING_VALUE) { WrapFbString(data, GetValue()) } else { None }
    }
    func GetValueAsCompositeValue(): Option<PackageFormat_CompositeValueIndex> {
        return if (GetValueType() == MF_CONST_VALUE_COMPOSITE_VALUE) { WrapCompositeValueIndex(data, GetValue()) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_MEMBER_VALUE_VT_FIELD) &&
            verifier.VerifyString(GetPointer(MF_MEMBER_VALUE_VT_FIELD)) &&
            VerifyField<UInt32>(verifier, MF_MEMBER_VALUE_VT_TYPE, 4) &&
            VerifyField<UInt8>(verifier, MF_MEMBER_VALUE_VT_VALUE_TYPE, 1) &&
            VerifyOffset(verifier, MF_MEMBER_VALUE_VT_VALUE) &&
            VerifyConstValue(data, verifier, GetValue(), GetValueType()) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2634-2662 (CompositeValue).
class PackageFormat_CompositeValue <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetType(): UInt32 { return GetField<UInt32>(MF_COMPOSITE_VALUE_VT_TYPE, 0u32) }
    func GetFields(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_COMPOSITE_VALUE_VT_FIELDS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, MF_COMPOSITE_VALUE_VT_TYPE, 4) &&
            VerifyOffset(verifier, MF_COMPOSITE_VALUE_VT_FIELDS) &&
            verifier.VerifyVector(GetPointer(MF_COMPOSITE_VALUE_VT_FIELDS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_COMPOSITE_VALUE_VT_FIELDS),
                {p: Int64, v: VerifierTemplate => PackageFormat_MemberValue(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2698-2739 (AutoDiffInfo).
class PackageFormat_AutoDiffInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsDiff(): Bool { return GetField<Bool>(MF_AUTO_DIFF_INFO_VT_ISDIFF, false) }
    func GetIsAdj(): Bool { return GetField<Bool>(MF_AUTO_DIFF_INFO_VT_ISADJ, false) }
    func GetPrimal(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_AUTO_DIFF_INFO_VT_PRIMAL)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetExcepts(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_AUTO_DIFF_INFO_VT_EXCEPTS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetIncludes(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_AUTO_DIFF_INFO_VT_INCLUDES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetStage(): UInt64 { return GetField<UInt64>(MF_AUTO_DIFF_INFO_VT_STAGE, 0u64) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_AUTO_DIFF_INFO_VT_ISDIFF, 1) &&
            VerifyField<Bool>(verifier, MF_AUTO_DIFF_INFO_VT_ISADJ, 1) &&
            VerifyOffset(verifier, MF_AUTO_DIFF_INFO_VT_PRIMAL) &&
            verifier.VerifyString(GetPointer(MF_AUTO_DIFF_INFO_VT_PRIMAL)) &&
            VerifyOffset(verifier, MF_AUTO_DIFF_INFO_VT_EXCEPTS) &&
            verifier.VerifyVector(GetPointer(MF_AUTO_DIFF_INFO_VT_EXCEPTS), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_AUTO_DIFF_INFO_VT_EXCEPTS)) &&
            VerifyOffset(verifier, MF_AUTO_DIFF_INFO_VT_INCLUDES) &&
            verifier.VerifyVector(GetPointer(MF_AUTO_DIFF_INFO_VT_INCLUDES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_AUTO_DIFF_INFO_VT_INCLUDES)) &&
            VerifyField<UInt64>(verifier, MF_AUTO_DIFF_INFO_VT_STAGE, 8) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2815-2860 (ClassInfo).
class PackageFormat_ClassInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInheritedTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_CLASS_INFO_VT_INHERITEDTYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetBody(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_CLASS_INFO_VT_BODY)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetAdInfo(): Option<PackageFormat_AutoDiffInfo> {
        return if (let Some(p) <- GetPointer(MF_CLASS_INFO_VT_ADINFO)) { Some(PackageFormat_AutoDiffInfo(data, p)) } else { None }
    }
    func GetIsAnno(): Bool { return GetField<Bool>(MF_CLASS_INFO_VT_ISANNO, false) }
    func GetAnnoTargets(): UInt8 { return GetField<UInt8>(MF_CLASS_INFO_VT_ANNOTARGETS, 0u8) }
    func GetRuntimeVisible(): Bool { return GetField<Bool>(MF_CLASS_INFO_VT_RUNTIMEVISIBLE, false) }
    func GetAnnoTargets2(): UInt8 { return GetField<UInt8>(MF_CLASS_INFO_VT_ANNOTARGETS2, 0u8) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_CLASS_INFO_VT_INHERITEDTYPES) &&
            verifier.VerifyVector(GetPointer(MF_CLASS_INFO_VT_INHERITEDTYPES), 4) &&
            VerifyOffset(verifier, MF_CLASS_INFO_VT_BODY) &&
            verifier.VerifyVector(GetPointer(MF_CLASS_INFO_VT_BODY), 4) &&
            VerifyOffset(verifier, MF_CLASS_INFO_VT_ADINFO) &&
            verifier.VerifyTable(GetPointer(MF_CLASS_INFO_VT_ADINFO),
                {p: Int64, v: VerifierTemplate => PackageFormat_AutoDiffInfo(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_CLASS_INFO_VT_ISANNO, 1) &&
            VerifyField<UInt8>(verifier, MF_CLASS_INFO_VT_ANNOTARGETS, 1) &&
            VerifyField<Bool>(verifier, MF_CLASS_INFO_VT_RUNTIMEVISIBLE, 1) &&
            VerifyField<UInt8>(verifier, MF_CLASS_INFO_VT_ANNOTARGETS2, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:2941-2985 (InterfaceInfo).
class PackageFormat_InterfaceInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInheritedTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_INTERFACE_INFO_VT_INHERITEDTYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetBody(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_INTERFACE_INFO_VT_BODY)) { Some(Vector<UInt32>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_INTERFACE_INFO_VT_INHERITEDTYPES) &&
            verifier.VerifyVector(GetPointer(MF_INTERFACE_INFO_VT_INHERITEDTYPES), 4) &&
            VerifyOffset(verifier, MF_INTERFACE_INFO_VT_BODY) &&
            verifier.VerifyVector(GetPointer(MF_INTERFACE_INFO_VT_BODY), 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3006-3050 (StructInfo).
class PackageFormat_StructInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInheritedTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_STRUCT_INFO_VT_INHERITEDTYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetBody(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_STRUCT_INFO_VT_BODY)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetAdInfo(): Option<PackageFormat_AutoDiffInfo> {
        return if (let Some(p) <- GetPointer(MF_STRUCT_INFO_VT_ADINFO)) { Some(PackageFormat_AutoDiffInfo(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_STRUCT_INFO_VT_INHERITEDTYPES) &&
            verifier.VerifyVector(GetPointer(MF_STRUCT_INFO_VT_INHERITEDTYPES), 4) &&
            VerifyOffset(verifier, MF_STRUCT_INFO_VT_BODY) &&
            verifier.VerifyVector(GetPointer(MF_STRUCT_INFO_VT_BODY), 4) &&
            VerifyOffset(verifier, MF_STRUCT_INFO_VT_ADINFO) &&
            verifier.VerifyTable(GetPointer(MF_STRUCT_INFO_VT_ADINFO),
                {p: Int64, v: VerifierTemplate => PackageFormat_AutoDiffInfo(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3084-3128 (EnumInfo).
class PackageFormat_EnumInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInheritedTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_ENUM_INFO_VT_INHERITEDTYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetBody(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_ENUM_INFO_VT_BODY)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetAdInfo(): Option<PackageFormat_AutoDiffInfo> {
        return if (let Some(p) <- GetPointer(MF_ENUM_INFO_VT_ADINFO)) { Some(PackageFormat_AutoDiffInfo(data, p)) } else { None }
    }
    func GetHasArguments(): Bool { return GetField<Bool>(MF_ENUM_INFO_VT_HASARGUMENTS, false) }
    func GetNonExhaustive(): Bool { return GetField<Bool>(MF_ENUM_INFO_VT_NONEXHAUSTIVE, false) }
    func GetEllipsisPos(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_ENUM_INFO_VT_ELLIPSISPOS)) { Some(PackageFormat_Position(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_ENUM_INFO_VT_INHERITEDTYPES) &&
            verifier.VerifyVector(GetPointer(MF_ENUM_INFO_VT_INHERITEDTYPES), 4) &&
            VerifyOffset(verifier, MF_ENUM_INFO_VT_BODY) &&
            verifier.VerifyVector(GetPointer(MF_ENUM_INFO_VT_BODY), 4) &&
            VerifyOffset(verifier, MF_ENUM_INFO_VT_ADINFO) &&
            verifier.VerifyTable(GetPointer(MF_ENUM_INFO_VT_ADINFO),
                {p: Int64, v: VerifierTemplate => PackageFormat_AutoDiffInfo(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_ENUM_INFO_VT_HASARGUMENTS, 1) &&
            VerifyField<Bool>(verifier, MF_ENUM_INFO_VT_NONEXHAUSTIVE, 1) &&
            VerifyStructField(verifier, MF_ENUM_INFO_VT_ELLIPSISPOS, 20, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3198-3242 (ExtendInfo).
class PackageFormat_ExtendInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInheritedTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_EXTEND_INFO_VT_INHERITEDTYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetBody(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_EXTEND_INFO_VT_BODY)) { Some(Vector<UInt32>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_EXTEND_INFO_VT_INHERITEDTYPES) &&
            verifier.VerifyVector(GetPointer(MF_EXTEND_INFO_VT_INHERITEDTYPES), 4) &&
            VerifyOffset(verifier, MF_EXTEND_INFO_VT_BODY) &&
            verifier.VerifyVector(GetPointer(MF_EXTEND_INFO_VT_BODY), 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3263-3308 (VarInfo). value is ConstValue union.
class PackageFormat_VarInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsVar(): Bool { return GetField<Bool>(MF_VAR_INFO_VT_ISVAR, false) }
    func GetIsConst(): Bool { return GetField<Bool>(MF_VAR_INFO_VT_ISCONST, false) }
    func GetIsMemberParam(): Bool { return GetField<Bool>(MF_VAR_INFO_VT_ISMEMBERPARAM, false) }
    func GetInitializer(): UInt32 { return GetField<UInt32>(MF_VAR_INFO_VT_INITIALIZER, 0u32) }
    func GetValueType(): UInt8 { return GetField<UInt8>(MF_VAR_INFO_VT_VALUE_TYPE, 0u8) }
    func GetValue(): Option<Int64> { return GetPointer(MF_VAR_INFO_VT_VALUE) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_VAR_INFO_VT_ISVAR, 1) &&
            VerifyField<Bool>(verifier, MF_VAR_INFO_VT_ISCONST, 1) &&
            VerifyField<Bool>(verifier, MF_VAR_INFO_VT_ISMEMBERPARAM, 1) &&
            VerifyField<UInt32>(verifier, MF_VAR_INFO_VT_INITIALIZER, 4) &&
            VerifyField<UInt8>(verifier, MF_VAR_INFO_VT_VALUE_TYPE, 1) &&
            VerifyOffset(verifier, MF_VAR_INFO_VT_VALUE) &&
            VerifyConstValue(data, verifier, GetValue(), GetValueType()) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3447-3491 (VarWithPatternInfo).
class PackageFormat_VarWithPatternInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsVar(): Bool { return GetField<Bool>(MF_VAR_WITH_PATTERN_INFO_VT_ISVAR, false) }
    func GetIsConst(): Bool { return GetField<Bool>(MF_VAR_WITH_PATTERN_INFO_VT_ISCONST, false) }
    func GetIrrefutablePattern(): Option<PackageFormat_Pattern> {
        return if (let Some(p) <- GetPointer(MF_VAR_WITH_PATTERN_INFO_VT_IRREFUTABLEPATTERN)) { Some(PackageFormat_Pattern(data, p)) } else { None }
    }
    func GetInitializer(): UInt32 { return GetField<UInt32>(MF_VAR_WITH_PATTERN_INFO_VT_INITIALIZER, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_VAR_WITH_PATTERN_INFO_VT_ISVAR, 1) &&
            VerifyField<Bool>(verifier, MF_VAR_WITH_PATTERN_INFO_VT_ISCONST, 1) &&
            VerifyOffset(verifier, MF_VAR_WITH_PATTERN_INFO_VT_IRREFUTABLEPATTERN) &&
            verifier.VerifyTable(GetPointer(MF_VAR_WITH_PATTERN_INFO_VT_IRREFUTABLEPATTERN),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            VerifyField<UInt32>(verifier, MF_VAR_WITH_PATTERN_INFO_VT_INITIALIZER, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3519-3563 (FuncInfo).
class PackageFormat_FuncInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFuncBody(): Option<PackageFormat_FuncBody> {
        return if (let Some(p) <- GetPointer(MF_FUNC_INFO_VT_FUNCBODY)) { Some(PackageFormat_FuncBody(data, p)) } else { None }
    }
    func GetOverflowPolicy(): UInt8 { return GetField<UInt8>(MF_FUNC_INFO_VT_OVERFLOWPOLICY, 0u8) }
    func GetOp(): UInt8 { return GetField<UInt8>(MF_FUNC_INFO_VT_OP, MF_OPERATOR_KIND_NA) }
    func GetAdInfo(): Option<PackageFormat_AutoDiffInfo> {
        return if (let Some(p) <- GetPointer(MF_FUNC_INFO_VT_ADINFO)) { Some(PackageFormat_AutoDiffInfo(data, p)) } else { None }
    }
    func GetIsConst(): Bool { return GetField<Bool>(MF_FUNC_INFO_VT_ISCONST, false) }
    func GetIsInline(): Bool { return GetField<Bool>(MF_FUNC_INFO_VT_ISINLINE, false) }
    func GetIsFastNative(): Bool { return GetField<Bool>(MF_FUNC_INFO_VT_ISFASTNATIVE, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FUNC_INFO_VT_FUNCBODY) &&
            verifier.VerifyTable(GetPointer(MF_FUNC_INFO_VT_FUNCBODY),
                {p: Int64, v: VerifierTemplate => PackageFormat_FuncBody(data, p).Verify(v)}) &&
            VerifyField<UInt8>(verifier, MF_FUNC_INFO_VT_OVERFLOWPOLICY, 1) &&
            VerifyField<UInt8>(verifier, MF_FUNC_INFO_VT_OP, 1) &&
            VerifyOffset(verifier, MF_FUNC_INFO_VT_ADINFO) &&
            verifier.VerifyTable(GetPointer(MF_FUNC_INFO_VT_ADINFO),
                {p: Int64, v: VerifierTemplate => PackageFormat_AutoDiffInfo(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_FUNC_INFO_VT_ISCONST, 1) &&
            VerifyField<Bool>(verifier, MF_FUNC_INFO_VT_ISINLINE, 1) &&
            VerifyField<Bool>(verifier, MF_FUNC_INFO_VT_ISFASTNATIVE, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3622-3666 (ParamInfo).
class PackageFormat_ParamInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsNamedParam(): Bool { return GetField<Bool>(MF_PARAM_INFO_VT_ISNAMEDPARAM, false) }
    func GetIsMemberParam(): Bool { return GetField<Bool>(MF_PARAM_INFO_VT_ISMEMBERPARAM, false) }
    func GetDefaultVal(): UInt32 { return GetField<UInt32>(MF_PARAM_INFO_VT_DEFAULTVAL, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_PARAM_INFO_VT_ISNAMEDPARAM, 1) &&
            VerifyField<Bool>(verifier, MF_PARAM_INFO_VT_ISMEMBERPARAM, 1) &&
            VerifyField<UInt32>(verifier, MF_PARAM_INFO_VT_DEFAULTVAL, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3683-3727 (PropInfo).
class PackageFormat_PropInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsConst(): Bool { return GetField<Bool>(MF_PROP_INFO_VT_ISCONST, false) }
    func GetIsMutable(): Bool { return GetField<Bool>(MF_PROP_INFO_VT_ISMUTABLE, false) }
    func GetSetters(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_PROP_INFO_VT_SETTERS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetGetters(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_PROP_INFO_VT_GETTERS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_PROP_INFO_VT_ISCONST, 1) &&
            VerifyField<Bool>(verifier, MF_PROP_INFO_VT_ISMUTABLE, 1) &&
            VerifyOffset(verifier, MF_PROP_INFO_VT_SETTERS) &&
            verifier.VerifyVector(GetPointer(MF_PROP_INFO_VT_SETTERS), 4) &&
            VerifyOffset(verifier, MF_PROP_INFO_VT_GETTERS) &&
            verifier.VerifyVector(GetPointer(MF_PROP_INFO_VT_GETTERS), 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3772-3812 (BuiltInInfo).
class PackageFormat_BuiltInInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetBuiltInType(): UInt8 { return GetField<UInt8>(MF_BUILT_IN_INFO_VT_BUILTINTYPE, 0u8) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, MF_BUILT_IN_INFO_VT_BUILTINTYPE, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3813-3853 (AliasInfo).
class PackageFormat_AliasInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetAliasedTy(): UInt32 { return GetField<UInt32>(MF_ALIAS_INFO_VT_ALIASEDTY, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, MF_ALIAS_INFO_VT_ALIASEDTY, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:3854-4223 (Decl). info is DeclInfo union.
class PackageFormat_Decl <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetKind(): UInt16 { return GetField<UInt16>(MF_DECL_VT_KIND, MF_DECL_KIND_INVALID_DECL) }
    func GetIsTopLevel(): Bool { return GetField<Bool>(MF_DECL_VT_ISTOPLEVEL, false) }
    func GetFullPkgName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_FULLPKGNAME)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetGenericDecl(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_GENERICDECL)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }
    func GetGeneric(): Option<PackageFormat_Generic> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_GENERIC)) { Some(PackageFormat_Generic(data, p)) } else { None }
    }
    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_DECL_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_DECL_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_IDENTIFIER)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetIdentifierPos(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_DECL_VT_IDENTIFIERPOS)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetAttributes(): Option<Vector<UInt64>> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_ATTRIBUTES)) { Some(Vector<UInt64>(data, p)) } else { None }
    }
    func GetAnnotations(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_ANNOTATIONS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetType(): UInt32 { return GetField<UInt32>(MF_DECL_VT_TYPE, 0u32) }
    func GetMangledName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_MANGLEDNAME)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetExportId(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_EXPORTID)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetMangledBeforeSema(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_MANGLEDBEFORESEMA)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetHash(): Option<PackageFormat_DeclHash> {
        return if (let Some(p) <- GetStruct(MF_DECL_VT_HASH)) { Some(PackageFormat_DeclHash(data, p)) } else { None }
    }
    func GetInfoType(): UInt8 { return GetField<UInt8>(MF_DECL_VT_INFO_TYPE, 0u8) }
    func GetInfo(): Option<Int64> { return GetPointer(MF_DECL_VT_INFO) }
    func GetDependencies(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_DECL_VT_DEPENDENCIES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt16>(verifier, MF_DECL_VT_KIND, 2) &&
            VerifyField<Bool>(verifier, MF_DECL_VT_ISTOPLEVEL, 1) &&
            VerifyOffset(verifier, MF_DECL_VT_FULLPKGNAME) &&
            verifier.VerifyString(GetPointer(MF_DECL_VT_FULLPKGNAME)) &&
            VerifyOffset(verifier, MF_DECL_VT_GENERICDECL) &&
            verifier.VerifyTable(GetPointer(MF_DECL_VT_GENERICDECL),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_DECL_VT_GENERIC) &&
            verifier.VerifyTable(GetPointer(MF_DECL_VT_GENERIC),
                {p: Int64, v: VerifierTemplate => PackageFormat_Generic(data, p).Verify(v)}) &&
            VerifyStructField(verifier, MF_DECL_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_DECL_VT_END, 20, 4) &&
            VerifyOffset(verifier, MF_DECL_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(MF_DECL_VT_IDENTIFIER)) &&
            VerifyStructField(verifier, MF_DECL_VT_IDENTIFIERPOS, 20, 4) &&
            VerifyOffset(verifier, MF_DECL_VT_ATTRIBUTES) &&
            verifier.VerifyVector(GetPointer(MF_DECL_VT_ATTRIBUTES), 8) &&
            VerifyOffset(verifier, MF_DECL_VT_ANNOTATIONS) &&
            verifier.VerifyVector(GetPointer(MF_DECL_VT_ANNOTATIONS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_DECL_VT_ANNOTATIONS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Anno(data, p).Verify(v)}) &&
            VerifyField<UInt32>(verifier, MF_DECL_VT_TYPE, 4) &&
            VerifyOffset(verifier, MF_DECL_VT_MANGLEDNAME) &&
            verifier.VerifyString(GetPointer(MF_DECL_VT_MANGLEDNAME)) &&
            VerifyOffset(verifier, MF_DECL_VT_EXPORTID) &&
            verifier.VerifyString(GetPointer(MF_DECL_VT_EXPORTID)) &&
            VerifyOffset(verifier, MF_DECL_VT_MANGLEDBEFORESEMA) &&
            verifier.VerifyString(GetPointer(MF_DECL_VT_MANGLEDBEFORESEMA)) &&
            VerifyStructField(verifier, MF_DECL_VT_HASH, 40, 8) &&
            VerifyField<UInt8>(verifier, MF_DECL_VT_INFO_TYPE, 1) &&
            VerifyOffset(verifier, MF_DECL_VT_INFO) &&
            VerifyDeclInfo(data, verifier, GetInfo(), GetInfoType()) &&
            VerifyOffset(verifier, MF_DECL_VT_DEPENDENCIES) &&
            verifier.VerifyVector(GetPointer(MF_DECL_VT_DEPENDENCIES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_DECL_VT_DEPENDENCIES),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4225-4314 (Anno).
class PackageFormat_Anno <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetKind(): UInt16 { return GetField<UInt16>(MF_ANNO_VT_KIND, 0u16) }
    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_ANNO_VT_IDENTIFIER)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetArgs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_ANNO_VT_ARGS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetTarget(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_ANNO_VT_TARGET)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt16>(verifier, MF_ANNO_VT_KIND, 2) &&
            VerifyOffset(verifier, MF_ANNO_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(MF_ANNO_VT_IDENTIFIER)) &&
            VerifyOffset(verifier, MF_ANNO_VT_ARGS) &&
            verifier.VerifyVector(GetPointer(MF_ANNO_VT_ARGS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_ANNO_VT_ARGS),
                {p: Int64, v: VerifierTemplate => PackageFormat_AnnoArg(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_ANNO_VT_TARGET) &&
            verifier.VerifyTable(GetPointer(MF_ANNO_VT_TARGET),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4316-4376 (AnnoArg).
class PackageFormat_AnnoArg <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_ANNO_ARG_VT_NAME)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetExpr(): UInt32 { return GetField<UInt32>(MF_ANNO_ARG_VT_EXPR, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_ANNO_ARG_VT_NAME) &&
            verifier.VerifyString(GetPointer(MF_ANNO_ARG_VT_NAME)) &&
            VerifyField<UInt32>(verifier, MF_ANNO_ARG_VT_EXPR, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4379-4420 (CallInfo).
class PackageFormat_CallInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetHasSideEffect(): Bool { return GetField<Bool>(MF_CALL_INFO_VT_HASSIDEEFFECT, false) }
    func GetCallKind(): UInt8 { return GetField<UInt8>(MF_CALL_INFO_VT_CALLKIND, MF_CALL_KIND_NA) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_CALL_INFO_VT_HASSIDEEFFECT, 1) &&
            VerifyField<UInt8>(verifier, MF_CALL_INFO_VT_CALLKIND, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4430-4462 (UnaryInfo).
class PackageFormat_UnaryInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetOp(): UInt8 { return GetField<UInt8>(MF_UNARY_INFO_VT_OP, 0u8) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, MF_UNARY_INFO_VT_OP, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4471-4503 (BinaryInfo).
class PackageFormat_BinaryInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetOp(): UInt8 { return GetField<UInt8>(MF_BINARY_INFO_VT_OP, 0u8) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, MF_BINARY_INFO_VT_OP, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4512-4544 (IncOrDecInfo).
class PackageFormat_IncOrDecInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetOp(): UInt8 { return GetField<UInt8>(MF_INC_OR_DEC_INFO_VT_OP, 0u8) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, MF_INC_OR_DEC_INFO_VT_OP, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4553-4599 (LitConstInfo).
class PackageFormat_LitConstInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetStrValue(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_LIT_CONST_INFO_VT_STRVALUE)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetConstKind(): UInt8 { return GetField<UInt8>(MF_LIT_CONST_INFO_VT_CONSTKIND, 0u8) }
    func GetStrKind(): UInt8 { return GetField<UInt8>(MF_LIT_CONST_INFO_VT_STRKIND, 0u8) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_LIT_CONST_INFO_VT_STRVALUE) &&
            verifier.VerifyString(GetPointer(MF_LIT_CONST_INFO_VT_STRVALUE)) &&
            VerifyField<UInt8>(verifier, MF_LIT_CONST_INFO_VT_CONSTKIND, 1) &&
            VerifyField<UInt8>(verifier, MF_LIT_CONST_INFO_VT_STRKIND, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4628-4699 (ReferenceInfo).
class PackageFormat_ReferenceInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetReference(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_REFERENCE_INFO_VT_REFERENCE)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetTarget(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_REFERENCE_INFO_VT_TARGET)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }
    func GetInstTys(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_REFERENCE_INFO_VT_INSTTYS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetMatchedParentTy(): UInt32 { return GetField<UInt32>(MF_REFERENCE_INFO_VT_MATCHEDPARENTTY, 0u32) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_REFERENCE_INFO_VT_REFERENCE) &&
            verifier.VerifyString(GetPointer(MF_REFERENCE_INFO_VT_REFERENCE)) &&
            VerifyOffset(verifier, MF_REFERENCE_INFO_VT_TARGET) &&
            verifier.VerifyTable(GetPointer(MF_REFERENCE_INFO_VT_TARGET),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_REFERENCE_INFO_VT_INSTTYS) &&
            verifier.VerifyVector(GetPointer(MF_REFERENCE_INFO_VT_INSTTYS), 4) &&
            VerifyField<UInt32>(verifier, MF_REFERENCE_INFO_VT_MATCHEDPARENTTY, 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4718-4759 (LambdaInfo). funcBody is required.
class PackageFormat_LambdaInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFuncBody(): Option<PackageFormat_FuncBody> {
        return if (let Some(p) <- GetPointer(MF_LAMBDA_INFO_VT_FUNCBODY)) { Some(PackageFormat_FuncBody(data, p)) } else { None }
    }
    func GetSupportMock(): Bool { return GetField<Bool>(MF_LAMBDA_INFO_VT_SUPPORTMOCK, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffsetRequired(verifier, MF_LAMBDA_INFO_VT_FUNCBODY) &&
            verifier.VerifyTable(GetPointer(MF_LAMBDA_INFO_VT_FUNCBODY),
                {p: Int64, v: VerifierTemplate => PackageFormat_FuncBody(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_LAMBDA_INFO_VT_SUPPORTMOCK, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4771-4812 (AssignInfo).
class PackageFormat_AssignInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIsCompound(): Bool { return GetField<Bool>(MF_ASSIGN_INFO_VT_ISCOMPOUND, false) }
    func GetOp(): UInt8 { return GetField<UInt8>(MF_ASSIGN_INFO_VT_OP, 0u8) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_ASSIGN_INFO_VT_ISCOMPOUND, 1) &&
            VerifyField<UInt8>(verifier, MF_ASSIGN_INFO_VT_OP, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4822-4863 (ArrayInfo).
class PackageFormat_ArrayInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetInitFunc(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_ARRAY_INFO_VT_INITFUNC)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }
    func GetIsValueArray(): Bool { return GetField<Bool>(MF_ARRAY_INFO_VT_ISVALUEARRAY, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_ARRAY_INFO_VT_INITFUNC) &&
            verifier.VerifyTable(GetPointer(MF_ARRAY_INFO_VT_INITFUNC),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_ARRAY_INFO_VT_ISVALUEARRAY, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4874-4906 (JumpInfo).
class PackageFormat_JumpInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetIsBreak(): Bool { return GetField<Bool>(MF_JUMP_INFO_VT_ISBREAK, false) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_JUMP_INFO_VT_ISBREAK, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4915-4956 (FuncArgInfo).
class PackageFormat_FuncArgInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetWithInout(): Bool { return GetField<Bool>(MF_FUNC_ARG_INFO_VT_WITHINOUT, false) }
    func GetIsDefaultVal(): Bool { return GetField<Bool>(MF_FUNC_ARG_INFO_VT_ISDEFAULTVAL, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_FUNC_ARG_INFO_VT_WITHINOUT, 1) &&
            VerifyField<Bool>(verifier, MF_FUNC_ARG_INFO_VT_ISDEFAULTVAL, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:4966-4998 (SubscriptInfo).
class PackageFormat_SubscriptInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetIsTupleAccess(): Bool { return GetField<Bool>(MF_SUBSCRIPT_INFO_VT_ISTUPLEACCESS, false) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_SUBSCRIPT_INFO_VT_ISTUPLEACCESS, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5007-5039 (MatchInfo).
class PackageFormat_MatchInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetMatchMode(): Bool { return GetField<Bool>(MF_MATCH_INFO_VT_MATCHMODE, false) }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Bool>(verifier, MF_MATCH_INFO_VT_MATCHMODE, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5048-5089 (BlockInfo).
class PackageFormat_BlockInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }
    func GetIsExpr(): Option<Vector<Bool>> {
        return if (let Some(p) <- GetPointer(MF_BLOCK_INFO_VT_ISEXPR)) { Some(Vector<Bool>(data, p)) } else { None }
    }
    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_BLOCK_INFO_VT_ISEXPR) &&
            verifier.VerifyVector(GetPointer(MF_BLOCK_INFO_VT_ISEXPR), 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5099-5156 (TryInfo).
class PackageFormat_TryInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetResources(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_TRY_INFO_VT_RESOURCES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetPatterns(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_TRY_INFO_VT_PATTERNS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_TRY_INFO_VT_RESOURCES) &&
            verifier.VerifyVector(GetPointer(MF_TRY_INFO_VT_RESOURCES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_TRY_INFO_VT_RESOURCES),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_TRY_INFO_VT_PATTERNS) &&
            verifier.VerifyVector(GetPointer(MF_TRY_INFO_VT_PATTERNS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_TRY_INFO_VT_PATTERNS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5166-5208 (LetPatternDestructorInfo).
class PackageFormat_LetPatternDestructorInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetPatterns(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_LET_PATTERN_DESTRUCTOR_INFO_VT_PATTERNS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_LET_PATTERN_DESTRUCTOR_INFO_VT_PATTERNS) &&
            verifier.VerifyVector(GetPointer(MF_LET_PATTERN_DESTRUCTOR_INFO_VT_PATTERNS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_LET_PATTERN_DESTRUCTOR_INFO_VT_PATTERNS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5218-5259 (ForInInfo).
class PackageFormat_ForInInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetPattern(): Option<PackageFormat_Pattern> {
        return if (let Some(p) <- GetPointer(MF_FOR_IN_INFO_VT_PATTERN)) { Some(PackageFormat_Pattern(data, p)) } else { None }
    }
    func GetForInKind(): UInt8 { return GetField<UInt8>(MF_FOR_IN_INFO_VT_FORINKIND, MF_FOR_IN_KIND_NA) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FOR_IN_INFO_VT_PATTERN) &&
            verifier.VerifyTable(GetPointer(MF_FOR_IN_INFO_VT_PATTERN),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            VerifyField<UInt8>(verifier, MF_FOR_IN_INFO_VT_FORINKIND, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5270-5312 (MatchCaseInfo).
class PackageFormat_MatchCaseInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetPatterns(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_MATCH_CASE_INFO_VT_PATTERNS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_MATCH_CASE_INFO_VT_PATTERNS) &&
            verifier.VerifyVector(GetPointer(MF_MATCH_CASE_INFO_VT_PATTERNS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_MATCH_CASE_INFO_VT_PATTERNS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5322-5354 (SpawnInfo).
class PackageFormat_SpawnInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFuture(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_SPAWN_INFO_VT_FUTURE)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_SPAWN_INFO_VT_FUTURE) &&
            verifier.VerifyTable(GetPointer(MF_SPAWN_INFO_VT_FUTURE),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5364-5645 (Expr). info is ExprInfo union.
class PackageFormat_Expr <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetKind(): UInt16 { return GetField<UInt16>(MF_EXPR_VT_KIND, MF_EXPR_KIND_INVALID_EXPR) }
    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_EXPR_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_EXPR_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetMapExpr(): UInt32 { return GetField<UInt32>(MF_EXPR_VT_MAPEXPR, 0u32) }
    func GetOperands(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_EXPR_VT_OPERANDS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetType(): UInt32 { return GetField<UInt32>(MF_EXPR_VT_TYPE, 0u32) }
    func GetOverflowPolicy(): UInt8 { return GetField<UInt8>(MF_EXPR_VT_OVERFLOWPOLICY, 0u8) }
    func GetInfoType(): UInt8 { return GetField<UInt8>(MF_EXPR_VT_INFO_TYPE, 0u8) }
    func GetInfo(): Option<Int64> { return GetPointer(MF_EXPR_VT_INFO) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt16>(verifier, MF_EXPR_VT_KIND, 2) &&
            VerifyStructField(verifier, MF_EXPR_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_EXPR_VT_END, 20, 4) &&
            VerifyField<UInt32>(verifier, MF_EXPR_VT_MAPEXPR, 4) &&
            VerifyOffset(verifier, MF_EXPR_VT_OPERANDS) &&
            verifier.VerifyVector(GetPointer(MF_EXPR_VT_OPERANDS), 4) &&
            VerifyField<UInt32>(verifier, MF_EXPR_VT_TYPE, 4) &&
            VerifyField<UInt8>(verifier, MF_EXPR_VT_OVERFLOWPOLICY, 1) &&
            VerifyField<UInt8>(verifier, MF_EXPR_VT_INFO_TYPE, 1) &&
            VerifyOffset(verifier, MF_EXPR_VT_INFO) &&
            VerifyExprInfo(data, verifier, GetInfo(), GetInfoType()) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5646-5812 (Pattern). values is [ConstValue].
class PackageFormat_Pattern <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetKind(): Int8 { return GetField<Int8>(MF_PATTERN_VT_KIND, MF_PATTERN_KIND_INVALID_PATTERN) }
    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_PATTERN_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_PATTERN_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetPatterns(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PATTERN_VT_PATTERNS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetTypes(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_PATTERN_VT_TYPES)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetExprs(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_PATTERN_VT_EXPRS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetValuesType(): Option<Vector<UInt8>> {
        return if (let Some(p) <- GetPointer(MF_PATTERN_VT_VALUES_TYPE)) { Some(Vector<UInt8>(data, p)) } else { None }
    }
    func GetValues(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PATTERN_VT_VALUES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetMatchBeforeRuntime(): Bool { return GetField<Bool>(MF_PATTERN_VT_MATCHBEFORERUNTIME, false) }
    func GetNeedRuntimeTypeCheck(): Bool { return GetField<Bool>(MF_PATTERN_VT_NEEDRUNTIMETYPECHECK, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int8>(verifier, MF_PATTERN_VT_KIND, 1) &&
            VerifyStructField(verifier, MF_PATTERN_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_PATTERN_VT_END, 20, 4) &&
            VerifyOffset(verifier, MF_PATTERN_VT_PATTERNS) &&
            verifier.VerifyVector(GetPointer(MF_PATTERN_VT_PATTERNS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PATTERN_VT_PATTERNS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Pattern(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PATTERN_VT_TYPES) &&
            verifier.VerifyVector(GetPointer(MF_PATTERN_VT_TYPES), 4) &&
            VerifyOffset(verifier, MF_PATTERN_VT_EXPRS) &&
            verifier.VerifyVector(GetPointer(MF_PATTERN_VT_EXPRS), 4) &&
            VerifyOffset(verifier, MF_PATTERN_VT_VALUES_TYPE) &&
            verifier.VerifyVector(GetPointer(MF_PATTERN_VT_VALUES_TYPE), 1) &&
            VerifyOffset(verifier, MF_PATTERN_VT_VALUES) &&
            verifier.VerifyVector(GetPointer(MF_PATTERN_VT_VALUES), 4) &&
            VerifyConstValueVector(data, verifier, GetPointer(MF_PATTERN_VT_VALUES), GetPointer(MF_PATTERN_VT_VALUES_TYPE)) &&
            VerifyField<Bool>(verifier, MF_PATTERN_VT_MATCHBEFORERUNTIME, 1) &&
            VerifyField<Bool>(verifier, MF_PATTERN_VT_NEEDRUNTIMETYPECHECK, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5815-5856 (FuncTyInfo).
class PackageFormat_FuncTyInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetRetType(): UInt32 { return GetField<UInt32>(MF_FUNC_TY_INFO_VT_RETTYPE, 0u32) }
    func GetIsC(): Bool { return GetField<Bool>(MF_FUNC_TY_INFO_VT_ISC, false) }
    func GetHasVariableLenArg(): Bool { return GetField<Bool>(MF_FUNC_TY_INFO_VT_HASVARIABLELENARG, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, MF_FUNC_TY_INFO_VT_RETTYPE, 4) &&
            VerifyField<Bool>(verifier, MF_FUNC_TY_INFO_VT_ISC, 1) &&
            VerifyField<Bool>(verifier, MF_FUNC_TY_INFO_VT_HASVARIABLELENARG, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5876-5917 (CompositeTyInfo).
class PackageFormat_CompositeTyInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetDeclPtr(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_COMPOSITE_TY_INFO_VT_DECLPTR)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }
    func GetIsThisTy(): Bool { return GetField<Bool>(MF_COMPOSITE_TY_INFO_VT_ISTHISTY, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_COMPOSITE_TY_INFO_VT_DECLPTR) &&
            verifier.VerifyTable(GetPointer(MF_COMPOSITE_TY_INFO_VT_DECLPTR),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyField<Bool>(verifier, MF_COMPOSITE_TY_INFO_VT_ISTHISTY, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5928-5981 (GenericTyInfo).
class PackageFormat_GenericTyInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetDeclPtr(): Option<PackageFormat_FullId> {
        return if (let Some(p) <- GetPointer(MF_GENERIC_TY_INFO_VT_DECLPTR)) { Some(PackageFormat_FullId(data, p)) } else { None }
    }
    func GetUpperBounds(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_GENERIC_TY_INFO_VT_UPPERBOUNDS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_GENERIC_TY_INFO_VT_DECLPTR) &&
            verifier.VerifyTable(GetPointer(MF_GENERIC_TY_INFO_VT_DECLPTR),
                {p: Int64, v: VerifierTemplate => PackageFormat_FullId(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_GENERIC_TY_INFO_VT_UPPERBOUNDS) &&
            verifier.VerifyVector(GetPointer(MF_GENERIC_TY_INFO_VT_UPPERBOUNDS), 4) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:5992-6030 (ArrayTyInfo).
class PackageFormat_ArrayTyInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetDimsOrSize(): Int64 { return GetField<Int64>(MF_ARRAY_TY_INFO_VT_DIMSORSIZE, 0) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<Int64>(verifier, MF_ARRAY_TY_INFO_VT_DIMSORSIZE, 8) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6033-6147 (SemaTy). info is SemaTyInfo union.
class PackageFormat_SemaTy <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetKind(): UInt16 { return GetField<UInt16>(MF_SEMA_TY_VT_KIND, MF_TYPE_KIND_UNIT) }
    func GetTypeArgs(): Option<Vector<UInt32>> {
        return if (let Some(p) <- GetPointer(MF_SEMA_TY_VT_TYPEARGS)) { Some(Vector<UInt32>(data, p)) } else { None }
    }
    func GetInfoType(): UInt8 { return GetField<UInt8>(MF_SEMA_TY_VT_INFO_TYPE, 0u8) }
    func GetInfo(): Option<Int64> { return GetPointer(MF_SEMA_TY_VT_INFO) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt16>(verifier, MF_SEMA_TY_VT_KIND, 2) &&
            VerifyOffset(verifier, MF_SEMA_TY_VT_TYPEARGS) &&
            verifier.VerifyVector(GetPointer(MF_SEMA_TY_VT_TYPEARGS), 4) &&
            VerifyField<UInt8>(verifier, MF_SEMA_TY_VT_INFO_TYPE, 1) &&
            VerifyOffset(verifier, MF_SEMA_TY_VT_INFO) &&
            VerifySemaTyInfo(data, verifier, GetInfo(), GetInfoType()) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6150-6299 (ImportSpec).
class PackageFormat_ImportSpec <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_IMPORT_SPEC_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_IMPORT_SPEC_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetPrefixPaths(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_IMPORT_SPEC_VT_PREFIXPATHS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetIdentifier(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_IMPORT_SPEC_VT_IDENTIFIER)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetAsIdentifier(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_IMPORT_SPEC_VT_ASIDENTIFIER)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetReExport(): UInt8 { return GetField<UInt8>(MF_IMPORT_SPEC_VT_REEXPORT, MF_ACCESS_MODIFIER_PRIVATE) }
    func GetIsDecl(): Bool { return GetField<Bool>(MF_IMPORT_SPEC_VT_ISDECL, false) }
    func GetHasDoubleColon(): Bool { return GetField<Bool>(MF_IMPORT_SPEC_VT_HASDOUBLECOLON, false) }
    func GetWithImplicitExport(): Bool { return GetField<Bool>(MF_IMPORT_SPEC_VT_WITHIMPLICITEXPORT, true) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyStructField(verifier, MF_IMPORT_SPEC_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_IMPORT_SPEC_VT_END, 20, 4) &&
            VerifyOffset(verifier, MF_IMPORT_SPEC_VT_PREFIXPATHS) &&
            verifier.VerifyVector(GetPointer(MF_IMPORT_SPEC_VT_PREFIXPATHS), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_IMPORT_SPEC_VT_PREFIXPATHS)) &&
            VerifyOffset(verifier, MF_IMPORT_SPEC_VT_IDENTIFIER) &&
            verifier.VerifyString(GetPointer(MF_IMPORT_SPEC_VT_IDENTIFIER)) &&
            VerifyOffset(verifier, MF_IMPORT_SPEC_VT_ASIDENTIFIER) &&
            verifier.VerifyString(GetPointer(MF_IMPORT_SPEC_VT_ASIDENTIFIER)) &&
            VerifyField<UInt8>(verifier, MF_IMPORT_SPEC_VT_REEXPORT, 1) &&
            VerifyField<Bool>(verifier, MF_IMPORT_SPEC_VT_ISDECL, 1) &&
            VerifyField<Bool>(verifier, MF_IMPORT_SPEC_VT_HASDOUBLECOLON, 1) &&
            VerifyField<Bool>(verifier, MF_IMPORT_SPEC_VT_WITHIMPLICITEXPORT, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6302-6344 (Imports).
class PackageFormat_Imports <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetImportSpecs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_IMPORTS_VT_IMPORTSPECS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_IMPORTS_VT_IMPORTSPECS) &&
            verifier.VerifyVector(GetPointer(MF_IMPORTS_VT_IMPORTSPECS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_IMPORTS_VT_IMPORTSPECS),
                {p: Int64, v: VerifierTemplate => PackageFormat_ImportSpec(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6354-6396 (FeatureId).
class PackageFormat_FeatureId <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetIdentifiers(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_FEATURE_ID_VT_IDENTIFIERS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FEATURE_ID_VT_IDENTIFIERS) &&
            verifier.VerifyVector(GetPointer(MF_FEATURE_ID_VT_IDENTIFIERS), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_FEATURE_ID_VT_IDENTIFIERS)) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6406-6448 (FeaturesSet).
class PackageFormat_FeaturesSet <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFeatures(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_FEATURES_SET_VT_FEATURES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FEATURES_SET_VT_FEATURES) &&
            verifier.VerifyVector(GetPointer(MF_FEATURES_SET_VT_FEATURES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_FEATURES_SET_VT_FEATURES),
                {p: Int64, v: VerifierTemplate => PackageFormat_FeatureId(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6458-6497 (FeaturesDirective).
class PackageFormat_FeaturesDirective <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFeaturesSet(): Option<PackageFormat_FeaturesSet> {
        return if (let Some(p) <- GetPointer(MF_FEATURES_DIRECTIVE_VT_FEATURESSET)) { Some(PackageFormat_FeaturesSet(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_FEATURES_DIRECTIVE_VT_FEATURESSET) &&
            verifier.VerifyTable(GetPointer(MF_FEATURES_DIRECTIVE_VT_FEATURESSET),
                {p: Int64, v: VerifierTemplate => PackageFormat_FeaturesSet(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6500-6569 (FileInfo).
class PackageFormat_FileInfo <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetFileID(): UInt32 { return GetField<UInt32>(MF_FILE_INFO_VT_FILEID, 0u32) }
    func GetBegin(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_FILE_INFO_VT_BEGIN)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetEnd(): Option<PackageFormat_Position> {
        return if (let Some(p) <- GetStruct(MF_FILE_INFO_VT_END)) { Some(PackageFormat_Position(data, p)) } else { None }
    }
    func GetFeature(): Option<PackageFormat_FeaturesDirective> {
        return if (let Some(p) <- GetPointer(MF_FILE_INFO_VT_FEATURE)) { Some(PackageFormat_FeaturesDirective(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt32>(verifier, MF_FILE_INFO_VT_FILEID, 4) &&
            VerifyStructField(verifier, MF_FILE_INFO_VT_BEGIN, 20, 4) &&
            VerifyStructField(verifier, MF_FILE_INFO_VT_END, 20, 4) &&
            VerifyOffset(verifier, MF_FILE_INFO_VT_FEATURE) &&
            verifier.VerifyTable(GetPointer(MF_FILE_INFO_VT_FEATURE),
                {p: Int64, v: VerifierTemplate => PackageFormat_FeaturesDirective(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6572-6613 (CompilationOptions).
class PackageFormat_CompilationOptions <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetOptimizationLevel(): UInt8 { return GetField<UInt8>(MF_COMPILATION_OPTIONS_VT_OPTIMIZATION_LEVEL, 0u8) }
    func GetDebug(): Bool { return GetField<Bool>(MF_COMPILATION_OPTIONS_VT_DEBUG, false) }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyField<UInt8>(verifier, MF_COMPILATION_OPTIONS_VT_OPTIMIZATION_LEVEL, 1) &&
            VerifyField<Bool>(verifier, MF_COMPILATION_OPTIONS_VT_DEBUG, 1) &&
            verifier.EndTable()
    }
}

// ModuleFormat_generated.h:6623-6698 (Package, root table).
class PackageFormat_Package <: Table {
    init(data: Array<UInt8>, pos: Int64) { super(data, pos) }

    func GetVersion(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_VERSION)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetCjoVersion(): Option<PackageFormat_CjoVersion> {
        return if (let Some(p) <- GetStruct(MF_PACKAGE_VT_CJOVERSION)) { Some(PackageFormat_CjoVersion(data, p)) } else { None }
    }
    func GetFullPkgName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_FULLPKGNAME)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetPkgDepInfo(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_PKGDEPINFO)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetImports(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_IMPORTS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllFiles(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLFILES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllFileImports(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLFILEIMPORTS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllTypes(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLTYPES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllDecls(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLDECLS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllExprs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLEXPRS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllValues(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLVALUES)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetKind(): UInt8 { return GetField<UInt8>(MF_PACKAGE_VT_KIND, MF_PACKAGE_KIND_NORMAL) }
    func GetAccess(): UInt8 { return GetField<UInt8>(MF_PACKAGE_VT_ACCESS, MF_ACCESS_LEVEL_PUBLIC) }
    func GetModuleName(): Option<FlatBufferString> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_MODULENAME)) { Some(FlatBufferString(data, p)) } else { None }
    }
    func GetAllFileInfo(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLFILEINFO)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetAllDependentStdPkgs(): Option<Vector<Offset<Any>>> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_ALLDEPENDENTSTDPKGS)) { Some(Vector<Offset<Any>>(data, p)) } else { None }
    }
    func GetOptions(): Option<PackageFormat_CompilationOptions> {
        return if (let Some(p) <- GetPointer(MF_PACKAGE_VT_OPTIONS)) { Some(PackageFormat_CompilationOptions(data, p)) } else { None }
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_VERSION) &&
            verifier.VerifyString(GetPointer(MF_PACKAGE_VT_VERSION)) &&
            VerifyStructField(verifier, MF_PACKAGE_VT_CJOVERSION, 3, 1) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_FULLPKGNAME) &&
            verifier.VerifyString(GetPointer(MF_PACKAGE_VT_FULLPKGNAME)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_PKGDEPINFO) &&
            verifier.VerifyString(GetPointer(MF_PACKAGE_VT_PKGDEPINFO)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_IMPORTS) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_IMPORTS), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_PACKAGE_VT_IMPORTS)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLFILES) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLFILES), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_PACKAGE_VT_ALLFILES)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLFILEIMPORTS) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLFILEIMPORTS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLFILEIMPORTS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Imports(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLTYPES) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLTYPES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLTYPES),
                {p: Int64, v: VerifierTemplate => PackageFormat_SemaTy(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLDECLS) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLDECLS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLDECLS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Decl(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLEXPRS) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLEXPRS), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLEXPRS),
                {p: Int64, v: VerifierTemplate => PackageFormat_Expr(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLVALUES) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLVALUES), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLVALUES),
                {p: Int64, v: VerifierTemplate => PackageFormat_CompositeValue(data, p).Verify(v)}) &&
            VerifyField<UInt8>(verifier, MF_PACKAGE_VT_KIND, 1) &&
            VerifyField<UInt8>(verifier, MF_PACKAGE_VT_ACCESS, 1) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_MODULENAME) &&
            verifier.VerifyString(GetPointer(MF_PACKAGE_VT_MODULENAME)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLFILEINFO) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLFILEINFO), 4) &&
            verifier.VerifyVectorOfTables(GetPointer(MF_PACKAGE_VT_ALLFILEINFO),
                {p: Int64, v: VerifierTemplate => PackageFormat_FileInfo(data, p).Verify(v)}) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_ALLDEPENDENTSTDPKGS) &&
            verifier.VerifyVector(GetPointer(MF_PACKAGE_VT_ALLDEPENDENTSTDPKGS), 4) &&
            verifier.VerifyVectorOfStrings(GetPointer(MF_PACKAGE_VT_ALLDEPENDENTSTDPKGS)) &&
            VerifyOffset(verifier, MF_PACKAGE_VT_OPTIONS) &&
            verifier.VerifyTable(GetPointer(MF_PACKAGE_VT_OPTIONS),
                {p: Int64, v: VerifierTemplate => PackageFormat_CompilationOptions(data, p).Verify(v)}) &&
            verifier.EndTable()
    }
}

// Verifies the buffer root. ModuleFormat_generated.h:6722-6730 (VerifyPackageBuffer).
// data is the same byte array the verifier wraps; C++ recovers it from the
// Verifier internally, Cangjie passes it alongside.
func VerifyPackageBuffer(data: Array<UInt8>, verifier: VerifierTemplate): Bool {
    return verifier.VerifyBuffer({p: Int64, v: VerifierTemplate => PackageFormat_Package(data, p).Verify(v)})
}

// Struct/string wrappers used by union value_as_ accessors. Each resolves the
// union offset (already followed by GetPointer) into the member reader.
func WrapInt8Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Int8Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Int8Value(data, p)) } else { None }
}
func WrapUInt8Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_UInt8Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_UInt8Value(data, p)) } else { None }
}
func WrapInt16Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Int16Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Int16Value(data, p)) } else { None }
}
func WrapUInt16Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_UInt16Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_UInt16Value(data, p)) } else { None }
}
func WrapInt32Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Int32Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Int32Value(data, p)) } else { None }
}
func WrapUInt32Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_UInt32Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_UInt32Value(data, p)) } else { None }
}
func WrapInt64Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Int64Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Int64Value(data, p)) } else { None }
}
func WrapUInt64Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_UInt64Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_UInt64Value(data, p)) } else { None }
}
func WrapFloat32Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Float32Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Float32Value(data, p)) } else { None }
}
func WrapFloat64Value(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_Float64Value> {
    return if (let Some(p) <- obj) { Some(PackageFormat_Float64Value(data, p)) } else { None }
}
func WrapArrayValue(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_ArrayValue> {
    return if (let Some(p) <- obj) { Some(PackageFormat_ArrayValue(data, p)) } else { None }
}
func WrapCompositeValueIndex(data: Array<UInt8>, obj: Option<Int64>): Option<PackageFormat_CompositeValueIndex> {
    return if (let Some(p) <- obj) { Some(PackageFormat_CompositeValueIndex(data, p)) } else { None }
}
func WrapFbString(data: Array<UInt8>, obj: Option<Int64>): Option<FlatBufferString> {
    return if (let Some(p) <- obj) { Some(FlatBufferString(data, p)) } else { None }
}

// ModuleFormat_generated.h:6900-6948 (VerifyConstValue). Struct members verify
// as inline structs at the resolved offset; ArrayValue as a table; StringValue
// as a string; CompositeValue as an inline CompositeValueIndex struct.
func VerifyConstValue(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, ty: UInt8): Bool {
    // An if-chain, not `match`, because a `case CONST =>` arm binds the scrutinee
    // to CONST rather than comparing against the named constant.
    if (ty == MF_CONST_VALUE_INT8_VALUE) { return VerifyUnionStruct(verifier, obj, 1, 1) }
    if (ty == MF_CONST_VALUE_UINT8_VALUE) { return VerifyUnionStruct(verifier, obj, 1, 1) }
    if (ty == MF_CONST_VALUE_INT16_VALUE) { return VerifyUnionStruct(verifier, obj, 2, 2) }
    if (ty == MF_CONST_VALUE_UINT16_VALUE) { return VerifyUnionStruct(verifier, obj, 2, 2) }
    if (ty == MF_CONST_VALUE_INT32_VALUE) { return VerifyUnionStruct(verifier, obj, 4, 4) }
    if (ty == MF_CONST_VALUE_UINT32_VALUE) { return VerifyUnionStruct(verifier, obj, 4, 4) }
    if (ty == MF_CONST_VALUE_INT64_VALUE) { return VerifyUnionStruct(verifier, obj, 8, 8) }
    if (ty == MF_CONST_VALUE_UINT64_VALUE) { return VerifyUnionStruct(verifier, obj, 8, 8) }
    if (ty == MF_CONST_VALUE_FLOAT32_VALUE) { return VerifyUnionStruct(verifier, obj, 4, 4) }
    if (ty == MF_CONST_VALUE_FLOAT64_VALUE) { return VerifyUnionStruct(verifier, obj, 8, 8) }
    if (ty == MF_CONST_VALUE_ARRAY_VALUE) {
        return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ArrayValue(data, p).Verify(v)})
    }
    if (ty == MF_CONST_VALUE_STRING_VALUE) { return verifier.VerifyString(obj) }
    if (ty == MF_CONST_VALUE_COMPOSITE_VALUE) { return VerifyUnionStruct(verifier, obj, 4, 4) }
    return true
}

// ModuleFormat_generated.h:6950-6960 (VerifyConstValueVector).
func VerifyConstValueVector(data: Array<UInt8>, verifier: VerifierTemplate, values: Option<Int64>, types: Option<Int64>): Bool {
    match ((values, types)) {
        case (None, None) => return true
        case (Some(valuesPos), Some(typesPos)) =>
            let valueVec = Vector<Offset<Any>>(data, valuesPos)
            let typeVec = Vector<UInt8>(data, typesPos)
            if (valueVec.size() != typeVec.size()) {
                return false
            }
            var i = 0u32
            while (i < valueVec.size()) {
                let elemPos = (valueVec.Get(i) as Int64).getOrThrow()
                let elemType = (typeVec.Get(i) as UInt8).getOrThrow()
                if (!VerifyConstValue(data, verifier, Some(elemPos), elemType)) {
                    return false
                }
                i++
            }
            return true
        case _ => return false
    }
}

// ModuleFormat_generated.h:6962-7017 (VerifyDeclInfo).
func VerifyDeclInfo(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, ty: UInt8): Bool {
    if (ty == MF_DECL_INFO_CLASS_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ClassInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_INTERFACE_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_InterfaceInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_STRUCT_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_StructInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_ENUM_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_EnumInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_EXTEND_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ExtendInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_PROP_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_PropInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_VAR_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_VarInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_VAR_WITH_PATTERN_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_VarWithPatternInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_PARAM_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ParamInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_FUNC_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_FuncInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_BUILT_IN_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_BuiltInInfo(data, p).Verify(v)}) }
    if (ty == MF_DECL_INFO_ALIAS_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_AliasInfo(data, p).Verify(v)}) }
    return true
}

// ModuleFormat_generated.h:7031-7114 (VerifyExprInfo).
func VerifyExprInfo(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, ty: UInt8): Bool {
    if (ty == MF_EXPR_INFO_CALL_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_CallInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_UNARY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_UnaryInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_BINARY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_BinaryInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_INC_OR_DEC_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_IncOrDecInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_LIT_CONST_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_LitConstInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_REFERENCE_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ReferenceInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_LAMBDA_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_LambdaInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_ASSIGN_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_AssignInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_ARRAY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ArrayInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_JUMP_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_JumpInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_FUNC_ARG_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_FuncArgInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_SUBSCRIPT_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_SubscriptInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_MATCH_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_MatchInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_BLOCK_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_BlockInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_TRY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_TryInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_LET_PATTERN_DESTRUCTOR_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_LetPatternDestructorInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_FOR_IN_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ForInInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_MATCH_CASE_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_MatchCaseInfo(data, p).Verify(v)}) }
    if (ty == MF_EXPR_INFO_SPAWN_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_SpawnInfo(data, p).Verify(v)}) }
    return true
}

// ModuleFormat_generated.h:7128-7151 (VerifySemaTyInfo).
func VerifySemaTyInfo(data: Array<UInt8>, verifier: VerifierTemplate, obj: Option<Int64>, ty: UInt8): Bool {
    if (ty == MF_SEMA_TY_INFO_FUNC_TY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_FuncTyInfo(data, p).Verify(v)}) }
    if (ty == MF_SEMA_TY_INFO_COMPOSITE_TY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_CompositeTyInfo(data, p).Verify(v)}) }
    if (ty == MF_SEMA_TY_INFO_GENERIC_TY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_GenericTyInfo(data, p).Verify(v)}) }
    if (ty == MF_SEMA_TY_INFO_ARRAY_TY_INFO) { return verifier.VerifyTable(obj, {p: Int64, v: VerifierTemplate => PackageFormat_ArrayTyInfo(data, p).Verify(v)}) }
    return true
}

// A struct union member is stored by offset; verify the inline struct at the
// resolved position. Mirrors verifier.VerifyField<Struct>(obj, 0, align) with an
// explicit struct size. ModuleFormat_generated.h:6906-6944.
func VerifyUnionStruct(verifier: VerifierTemplate, obj: Option<Int64>, structSize: Int64, align: Int64): Bool {
    return if (let Some(p) <- obj) { verifier.VerifyFieldStruct(p, 0u16, structSize, align) } else { true }
}
