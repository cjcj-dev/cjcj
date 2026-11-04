package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::flatbuffers.ReadScalar
import cjcj::frontend.*
import cjcj::modules.ASTLoader as HeaderLoader
import cjcj::modules.{CJO_MAJOR_VERSION, CJO_MINOR_VERSION}
import cjcj::basic.{DiagCategory, DiagKindRefactorName}
import cjcj::basic.DiagnosticEngine as HeaderDiagnostics

private func VersionLoader(result: TestCompileResult, data: Array<UInt8>): CjoSignatureMaterializer {
    let pkg = RequireFirstPackage(result)
    return CjoSignatureMaterializer(pkg.fullPackageName, pkg, HashMap<UInt32, File>(),
        HashMap<UInt64, File>(), ArrayList<Package>(), HashMap<String, PackageDecl>(),
        HashMap<String, HashMap<String, Decl>>(), result.diag,
        result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), data: Some(data))
}

// PackageTest.cpp@12883f2b MutableCjoVersionBytes and CjoVersionQueryOnLoader.
private func VersionOffset(data: Array<UInt8>): Int64 {
    let root = Int64(ReadScalar(data, 0, 0u32))
    let vtable = root - Int64(ReadScalar(data, root, 0i32))
    return root + Int64(ReadScalar(data, vtable + 6, 0u16))
}

@Test
public class CjoVersionTest {
    @TestCase
    public func CjoVersionQueryOnLoader(): Unit {
        let result = CompileSource("package versionquery\npublic func answer(): Int64 { 42 }")
        @Assert(result.ok)
        let data = result.instance.ExportAST(false, RequireFirstPackage(result))
        @Assert(!data.isEmpty())
        let offset = VersionOffset(data)
        @Expect(data[offset], 2u8)
        @Expect(data[offset + 1], 0u8)
        @Expect(data[offset + 2], 0u8)
        for (minor in [0u8, 1u8]) {
            let copy = data.clone()
            copy[offset + 1] = minor
            copy[offset + 2] = 255u8
            let loader = VersionLoader(result, copy)
            // No header yet: absence is different from the valid version 0.0.0.
            @Expect(loader.HasCjoVersion(), false)
            @Expect(loader.GetCjoVersion().major, 0u8)
            @Expect(loader.GetCjoVersion().minor, 0u8)
            @Expect(loader.GetCjoVersion().patch, 0u8)
            @Expect(loader.IsCjoVersionAtLeast(CJO_MAJOR_VERSION, 0u8), false)
            @Expect(loader.IsCjoVersionAtMost(CJO_MAJOR_VERSION, 1u8), false)
            @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, 0u8), false)
            loader.SetCjoPath("versionquery.cjo")
            let errorsBefore = result.diag.GetErrorCount()
            let depInfo = loader.LoadPackageDepInfo()
            let tooNew = minor > CJO_MINOR_VERSION
            @Expect(depInfo.isEmpty(), tooNew)
            @Expect(result.diag.GetErrorCount(), errorsBefore + (if (tooNew) { 1u64 } else { 0u64 }))
            @Expect(loader.HasCjoVersion(), true)
            @Expect(loader.GetCjoVersion().major, CJO_MAJOR_VERSION)
            @Expect(loader.GetCjoVersion().minor, minor)
            @Expect(loader.GetCjoVersion().patch, 255u8)
            @Expect(loader.IsCjoVersionAtLeast(CJO_MAJOR_VERSION, 0u8), true)
            @Expect(loader.IsCjoVersionAtMost(CJO_MAJOR_VERSION, 1u8), true)
            @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, minor), true)
            @Expect(loader.IsCjoVersionAtLeast(CJO_MAJOR_VERSION, 1u8), minor == 1u8)
            @Expect(loader.IsCjoVersionAtMost(CJO_MAJOR_VERSION, 0u8), minor == 0u8)
            @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, 1u8), minor == 1u8)
            @Expect(loader.IsCjoVersionAtLeast(1u8, 0u8), false)
            @Expect(loader.IsCjoVersionAtMost(1u8, 0u8), false)
            @Expect(loader.IsCjoVersionExactly(1u8, minor), false)
            println("CjoVersionQueryOnLoader observed minor=${minor} patch=255")
        }
    }

    @TestCase
    public func MissingVersionQueryOnLoader(): Unit {
        let result = CompileSource("package versionmissing\npublic func answer(): Int64 { 42 }")
        @Assert(result.ok)
        let data = result.instance.ExportAST(false, RequireFirstPackage(result))
        let root = Int64(ReadScalar(data, 0, 0u32))
        let vtable = root - Int64(ReadScalar(data, root, 0i32))
        data[vtable + 6] = 0u8
        data[vtable + 7] = 0u8
        let loader = VersionLoader(result, data)
        @Expect(loader.LoadPackageDepInfo(), "")
        @Expect(result.diag.GetErrorCount(), 1u64)
        @Expect(loader.HasCjoVersion(), false)
        @Expect(loader.GetCjoVersion().major, 0u8)
        @Expect(loader.GetCjoVersion().minor, 0u8)
        @Expect(loader.GetCjoVersion().patch, 0u8)
        @Expect(loader.IsCjoVersionAtLeast(CJO_MAJOR_VERSION, 0u8), false)
        @Expect(loader.IsCjoVersionAtMost(CJO_MAJOR_VERSION, 1u8), false)
        @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, 0u8), false)
        println("MissingVersionQueryOnLoader observed missing version")
    }
    @TestCase
    public func HeaderVersionQueryAndGate(): Unit {
        let result = CompileSource("package headerquery\npublic func answer(): Int64 { 42 }")
        @Assert(result.ok)
        let data = result.instance.ExportAST(false, RequireFirstPackage(result))
        let offset = VersionOffset(data)
        for (minor in [0u8, 1u8, 2u8]) {
            let copy = data.clone()
            copy[offset + 1] = minor
            let diag = HeaderDiagnostics()
            let loader = HeaderLoader(copy, "headerquery", diag)
            loader.SetCjoPath("headerquery.cjo")
            @Expect(loader.HasCjoVersion(), false)
            @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, 0u8), false)
            let depInfo = loader.LoadPackageDepInfo()
            @Expect(depInfo.isEmpty(), minor > CJO_MINOR_VERSION)
            @Expect(diag.GetErrorCount(), if (minor > CJO_MINOR_VERSION) { 1u64 } else { 0u64 })
            @Expect(loader.HasCjoVersion(), true)
            @Expect(loader.GetCjoVersion().minor, minor)
            @Expect(loader.IsCjoVersionAtLeast(CJO_MAJOR_VERSION, minor), true)
            @Expect(loader.IsCjoVersionAtMost(CJO_MAJOR_VERSION, minor), true)
            @Expect(loader.IsCjoVersionExactly(CJO_MAJOR_VERSION, minor), true)
            @Expect(loader.IsCjoVersionAtMost(1u8, minor), false)
            println("HeaderVersionQueryAndGate observed minor=${minor}")
        }
    }

    @TestCase
    public func oldConstructorABIRejectedByBothLoaders(): Unit {
        let result = CompileSource("package oldctorabi\npublic class A { public init() {} }")
        @Assert(result.ok)
        let data = result.instance.ExportAST(false, RequireFirstPackage(result))
        let offset = VersionOffset(data)
        @Assert(data[offset] == 2u8)
        let controlDiag = HeaderDiagnostics()
        let control = HeaderLoader(data, "oldctorabi", controlDiag)
        control.SetCjoPath("oldctorabi.cjo")
        let _ = control.LoadPackageDepInfo()
        @Expect(controlDiag.GetErrorCount(), 0u64)
        let old = data.clone()
        old[offset] = 0u8
        let oldDiag = HeaderDiagnostics()
        let oldHeader = HeaderLoader(old, "oldctorabi", oldDiag)
        oldHeader.SetCjoPath("oldctorabi.cjo")
        @Expect(oldHeader.LoadPackageDepInfo().isEmpty(), true)
        @Expect(oldDiag.GetErrorCount(), 1u64)
        let errorsBefore = result.diag.GetErrorCount()
        let oldSignature = VersionLoader(result, old)
        oldSignature.SetCjoPath("oldctorabi.cjo")
        @Expect(oldSignature.LoadPackageDepInfo(), "")
        @Expect(result.diag.GetErrorCount(), errorsBefore + 1u64)
    }

    @TestCase
    public func receiverABIBoundaryRejectsOldAndFutureVersions(): Unit {
        let result = CompileSource("package receiverabiversion\npublic func answer(): Int64 { 42 }")
        @Assert(result.ok)
        let pkg = RequireFirstPackage(result)
        let data = result.instance.ExportAST(false, pkg)
        let offset = VersionOffset(data)
        @Assert(data[offset], 2u8)
        @Assert(data[offset + 1], 0u8)
        @Assert(data[offset + 2], 0u8)
        let control = VersionLoader(result, data)
        @Expect(control.LoadPackageDependencies(data), true)
        @Expect(result.diag.GetErrorCount(), 0u64)
        // These are gate unit fixtures, not genuine old-ABI producer artifacts.
        // The real 1.1.0/1.1.1 <-> 2.0.0 matrix belongs to paired production.
        for ((major, minor, patch) in [(1u8, 1u8, 0u8), (1u8, 1u8, 1u8),
            (3u8, 0u8, 0u8), (2u8, 1u8, 0u8)]) {
            let old = data.clone()
            old[offset] = major
            old[offset + 1] = minor
            old[offset + 2] = patch
            let headerDiag = HeaderDiagnostics()
            let header = HeaderLoader(old, "receiverabiversion", headerDiag)
            header.SetCjoPath("receiverabiversion.cjo")
            @Expect(header.LoadPackageDepInfo(), "")
            let diagnostics = headerDiag.GetCategoryDiagnostic(DiagCategory.MODULE)
            @Assert(diagnostics.size, 1)
            @Expect(DiagKindRefactorName(diagnostics[0].rKind), "module_version_not_identical")
            for (entry in ["dep-info", "dependencies", "common-part", "cached-type"]) {
                let storage = result.instance.importManager.getOrThrow().GetDiagnosticEngine()
                storage.Reset()
                let loader = VersionLoader(result, old)
                loader.SetCjoPath("receiverabiversion.cjo")
                if (entry == "dep-info") {
                    @Expect(loader.LoadPackageDepInfo(), "")
                } else if (entry == "dependencies") {
                    @Expect(loader.LoadPackageDependencies(old), false)
                } else if (entry == "common-part") {
                    @Expect(loader.PreloadCommonPartOfPackage(pkg, result.instance.invocation.globalOptions), false)
                } else {
                    // A cache mismatch is a silent miss. This assertion alone
                    // does not claim the public pipeline rebuilt from source.
                    @Expect(loader.LoadCachedTypeForPackage(pkg, HashMap<String, Decl>()).isEmpty())
                }
                let frontendDiagnostics = storage.GetCategoryDiagnostic(DiagCategory.MODULE)
                if (entry == "cached-type") {
                    @Expect(result.diag.GetErrorCount(), 0u64)
                    @Expect(frontendDiagnostics.isEmpty())
                } else {
                    @Expect(result.diag.GetErrorCount(), 1u64)
                    @Assert(frontendDiagnostics.size, 1)
                    @Expect(DiagKindRefactorName(frontendDiagnostics[0].rKind), "module_version_not_identical")
                }
                println("RECEIVER_ABI_GATE ${major}.${minor}.${patch} entry=${entry}")
            }
        }
    }

}
