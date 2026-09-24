package cjcj::cjo_frontend_query

import std.collection.*
import std.env.getVariable
import cjcj::ast.{Decl, File, Package, PackageDecl}
import cjcj::flatbuffers.ReadScalar
import cjcj::frontend.{CjoSignatureMaterializer, DiagnosticEngine, TypeManager}
import cjcj::utils.FileUtil

var failures: Int64 = 0

func Mark(ok: Bool): String {
    if (!ok) {
        failures = failures + 1
        return "FAIL"
    }
    return "PASS"
}

func CheckBool(name: String, observed: Bool, expected: Bool): Unit {
    let obs = if (observed) { "true" } else { "false" }
    let exp = if (expected) { "true" } else { "false" }
    println("QUERY_ASSERT ${name} expected=${exp} observed=${obs} ${Mark(observed == expected)}")
}

func CheckU8(name: String, observed: UInt8, expected: UInt8): Unit {
    println("QUERY_ASSERT ${name} expected=${expected} observed=${observed} ${Mark(observed == expected)}")
}

func CheckU64(name: String, observed: UInt64, expected: UInt64): Unit {
    println("QUERY_ASSERT ${name} expected=${expected} observed=${observed} ${Mark(observed == expected)}")
}

func VersionOffset(data: Array<UInt8>): Int64 {
    let root = Int64(ReadScalar(data, 0, 0u32))
    let vtable = root - Int64(ReadScalar(data, root, 0i32))
    return root + Int64(ReadScalar(data, vtable + 6, 0u16))
}

func MakeLoader(data: Array<UInt8>, diag: DiagnosticEngine): CjoSignatureMaterializer {
    let pkg = Package("vercheck")
    return CjoSignatureMaterializer("vercheck", pkg, HashMap<UInt32, File>(), HashMap<UInt64, File>(),
        ArrayList<Package>(), HashMap<String, PackageDecl>(), HashMap<String, HashMap<String, Decl>>(), diag,
        TypeManager().AsFaithfulSemaTypeManager(), importSrcCode: false, data: Some(data))
}

func CheckUnread(loader: CjoSignatureMaterializer, tag: String): Unit {
    println("QUERY_TARGET ${tag}.unread executed=1")
    CheckBool("${tag}.unread.HasCjoVersion", loader.HasCjoVersion(), false)
    CheckU8("${tag}.unread.major", loader.GetCjoVersion().major, 0u8)
    CheckU8("${tag}.unread.minor", loader.GetCjoVersion().minor, 0u8)
    CheckU8("${tag}.unread.patch", loader.GetCjoVersion().patch, 0u8)
    CheckBool("${tag}.unread.AtLeast00", loader.IsCjoVersionAtLeast(0u8, 0u8), false)
    CheckBool("${tag}.unread.AtMost01", loader.IsCjoVersionAtMost(0u8, 1u8), false)
    CheckBool("${tag}.unread.Exactly00", loader.IsCjoVersionExactly(0u8, 0u8), false)
}

func CheckLoadedQuery(loader: CjoSignatureMaterializer, tag: String, major: UInt8, minor: UInt8, patch: UInt8): Unit {
    let trip = loader.GetCjoVersion()
    println("QUERY_TARGET ${tag}.GetCjoVersion executed=1 major=${trip.major} minor=${trip.minor} patch=${trip.patch}")
    CheckBool("${tag}.HasCjoVersion", loader.HasCjoVersion(), true)
    CheckU8("${tag}.major", trip.major, major)
    CheckU8("${tag}.minor", trip.minor, minor)
    CheckU8("${tag}.patch", trip.patch, patch)
    CheckBool("${tag}.AtLeast00", loader.IsCjoVersionAtLeast(0u8, 0u8), major == 0u8)
    CheckBool("${tag}.AtMost01", loader.IsCjoVersionAtMost(0u8, 1u8), major == 0u8 && minor <= 1u8)
    CheckBool("${tag}.Exactly0minor", loader.IsCjoVersionExactly(0u8, minor), major == 0u8)
    CheckBool("${tag}.AtLeast01", loader.IsCjoVersionAtLeast(0u8, 1u8), major == 0u8 && minor >= 1u8)
    CheckBool("${tag}.AtMost00", loader.IsCjoVersionAtMost(0u8, 0u8), major == 0u8 && minor == 0u8)
    CheckBool("${tag}.AtLeast10", loader.IsCjoVersionAtLeast(1u8, 0u8), major == 1u8)
    CheckBool("${tag}.AtMost10", loader.IsCjoVersionAtMost(1u8, 0u8), major == 1u8 && minor == 0u8)
    CheckBool("${tag}.Exactly1minor", loader.IsCjoVersionExactly(1u8, minor), major == 1u8)
    CheckBool("${tag}.ExactlyMajorMinor", loader.IsCjoVersionExactly(major, minor), true)
}

func CheckGate(tag: String, depInfo: String, errors: UInt64, refuse: Bool): Unit {
    println("GATE_ASSERT ${tag} empty=${depInfo.isEmpty()} errors=${errors} refuse=${refuse}")
    CheckBool("${tag}.depEmpty", depInfo.isEmpty(), refuse)
    CheckU64("${tag}.errors", errors, if (refuse) { 1u64 } else { 0u64 })
    if (!refuse) {
        CheckBool("${tag}.depHasName", depInfo.contains("vercheck"), true)
    }
}

func RunCase(data: Array<UInt8>, offset: Int64, tag: String, major: UInt8, minor: UInt8, patch: UInt8,
    refuse: Bool): Unit {
    let copy = data.clone()
    copy[offset] = major
    copy[offset + 1] = minor
    copy[offset + 2] = patch
    let diag = DiagnosticEngine()
    let loader = MakeLoader(copy, diag)
    loader.SetCjoPath("vercheck.cjo")
    CheckUnread(loader, tag)
    let depInfo = loader.LoadPackageDepInfo()
    CheckGate(tag, depInfo, diag.GetErrorCount(), refuse)
    CheckLoadedQuery(loader, tag, major, minor, patch)
}

main(): Int64 {
    let path = getVariable("CJO_FIXTURE").getOrThrow()
    let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(path)
    if (!ok) {
        println("INFRA fixture read failed: ${reason}")
        return 2
    }
    let offset = VersionOffset(data)
    if (offset <= 0) {
        println("INFRA version offset missing")
        return 2
    }

    let unreadCopy = data.clone()
    let unreadDiag = DiagnosticEngine()
    let unread = MakeLoader(unreadCopy, unreadDiag)
    unread.SetCjoPath("vercheck.cjo")
    CheckUnread(unread, "header")

    RunCase(data, offset, "older", 0u8, 0u8, 255u8, false)
    RunCase(data, offset, "current", 0u8, 1u8, 255u8, false)
    RunCase(data, offset, "patch", 0u8, 1u8, 7u8, false)
    RunCase(data, offset, "newer", 0u8, 2u8, 0u8, true)
    RunCase(data, offset, "major", 1u8, 1u8, 0u8, true)

    let missing = data.clone()
    let root = Int64(ReadScalar(missing, 0, 0u32))
    let vtable = root - Int64(ReadScalar(missing, root, 0i32))
    missing[vtable + 6] = 0u8
    missing[vtable + 7] = 0u8
    let missingDiag = DiagnosticEngine()
    let missingLoader = MakeLoader(missing, missingDiag)
    missingLoader.SetCjoPath("vercheck.cjo")
    let missingDep = missingLoader.LoadPackageDepInfo()
    CheckGate("missing", missingDep, missingDiag.GetErrorCount(), true)
    println("QUERY_TARGET missing.GetCjoVersion executed=1")
    CheckBool("missing.HasCjoVersion", missingLoader.HasCjoVersion(), false)
    CheckU8("missing.major", missingLoader.GetCjoVersion().major, 0u8)
    CheckU8("missing.minor", missingLoader.GetCjoVersion().minor, 0u8)
    CheckU8("missing.patch", missingLoader.GetCjoVersion().patch, 0u8)
    CheckBool("missing.AtLeast00", missingLoader.IsCjoVersionAtLeast(0u8, 0u8), false)
    CheckBool("missing.Exactly00", missingLoader.IsCjoVersionExactly(0u8, 0u8), false)

    println("QUERY_SUMMARY failures=${failures}")
    if (failures != 0) {
        return 1
    }
    return 0
}
