package cjcj::chir

import cjcj::flatbuffers.{FlatBufferString, Offset, Table, Vector, VerifierTemplate}

// PackageFormat_generated.h:7931-8023. CHIRPackage read accessors and Verify.
class PackageFormat_CHIRPackage <: Table {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func GetName(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_NAME)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetPath(): Option<FlatBufferString> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_PATH)) { Some(FlatBufferString(data, pointerPos)) } else { None }
    }

    func GetPkgAccessLevel(): UInt8 {
        return GetField<UInt8>(CHIRFB_CHIR_PACKAGE_VT_PKGACCESSLEVEL, 0u8)
    }

    func GetTypes_type(): Option<Vector<UInt8>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES_TYPE)) { Some(Vector<UInt8>(data, pointerPos)) } else { None }
    }

    func GetTypes(): Option<Vector<Offset<Any>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES)) { Some(Vector<Offset<Any>>(data, pointerPos)) } else { None }
    }

    func GetValues_type(): Option<Vector<UInt8>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES_TYPE)) { Some(Vector<UInt8>(data, pointerPos)) } else { None }
    }

    func GetValues(): Option<Vector<Offset<Any>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES)) { Some(Vector<Offset<Any>>(data, pointerPos)) } else { None }
    }

    func GetExprs_type(): Option<Vector<UInt8>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS_TYPE)) { Some(Vector<UInt8>(data, pointerPos)) } else { None }
    }

    func GetExprs(): Option<Vector<Offset<Any>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS)) { Some(Vector<Offset<Any>>(data, pointerPos)) } else { None }
    }

    func GetDefs_type(): Option<Vector<UInt8>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS_TYPE)) { Some(Vector<UInt8>(data, pointerPos)) } else { None }
    }

    func GetDefs(): Option<Vector<Offset<Any>>> {
        return if (let Some(pointerPos) <- GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS)) { Some(Vector<Offset<Any>>(data, pointerPos)) } else { None }
    }

    func GetPackageInitFunc(): UInt32 {
        return GetField<UInt32>(CHIRFB_CHIR_PACKAGE_VT_PACKAGEINITFUNC, 0u32)
    }

    func GetPhase(): UInt8 {
        return GetField<UInt8>(CHIRFB_CHIR_PACKAGE_VT_PHASE, 0u8)
    }

    func GetPackageLiteralInitFunc(): UInt32 {
        return GetField<UInt32>(CHIRFB_CHIR_PACKAGE_VT_PACKAGELITERALINITFUNC, 0u32)
    }

    func Verify(verifier: VerifierTemplate): Bool {
        return VerifyTableStart(verifier) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_NAME) &&
            verifier.VerifyString(GetPointer(CHIRFB_CHIR_PACKAGE_VT_NAME)) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_PATH) &&
            verifier.VerifyString(GetPointer(CHIRFB_CHIR_PACKAGE_VT_PATH)) &&
            VerifyField<UInt8>(verifier, CHIRFB_CHIR_PACKAGE_VT_PKGACCESSLEVEL, 1) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_TYPES_TYPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES_TYPE), 1) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_TYPES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES), 4) &&
            VerifyTypeElemVector(data, verifier, GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES), GetPointer(CHIRFB_CHIR_PACKAGE_VT_TYPES_TYPE)) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_VALUES_TYPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES_TYPE), 1) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_VALUES) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES), 4) &&
            VerifyValueElemVector(data, verifier, GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES), GetPointer(CHIRFB_CHIR_PACKAGE_VT_VALUES_TYPE)) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_EXPRS_TYPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS_TYPE), 1) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_EXPRS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS), 4) &&
            VerifyExpressionElemVector(data, verifier, GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS), GetPointer(CHIRFB_CHIR_PACKAGE_VT_EXPRS_TYPE)) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_DEFS_TYPE) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS_TYPE), 1) &&
            VerifyOffset(verifier, CHIRFB_CHIR_PACKAGE_VT_DEFS) &&
            verifier.VerifyVector(GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS), 4) &&
            VerifyCustomTypeDefElemVector(data, verifier, GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS), GetPointer(CHIRFB_CHIR_PACKAGE_VT_DEFS_TYPE)) &&
            VerifyField<UInt32>(verifier, CHIRFB_CHIR_PACKAGE_VT_PACKAGEINITFUNC, 4) &&
            VerifyField<UInt8>(verifier, CHIRFB_CHIR_PACKAGE_VT_PHASE, 1) &&
            VerifyField<UInt32>(verifier, CHIRFB_CHIR_PACKAGE_VT_PACKAGELITERALINITFUNC, 4) &&
            verifier.EndTable()
    }
}
