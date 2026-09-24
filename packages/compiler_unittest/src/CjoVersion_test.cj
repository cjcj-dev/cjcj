package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::flatbuffers.ReadScalar
import cjcj::frontend.*
import cjcj::modules.ASTLoader as HeaderLoader
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
        @Expect(data[offset], 0u8)
        @Expect(data[offset + 1], 1u8)
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
            @Expect(loader.IsCjoVersionAtLeast(0u8, 0u8), false)
            @Expect(loader.IsCjoVersionAtMost(0u8, 1u8), false)
            @Expect(loader.IsCjoVersionExactly(0u8, 0u8), false)
            loader.SetCjoPath("versionquery.cjo")
            let _ = loader.LoadPackageDepInfo()
            @Expect(result.diag.GetErrorCount(), 0u64)
            @Expect(loader.HasCjoVersion(), true)
            @Expect(loader.GetCjoVersion().major, 0u8)
            @Expect(loader.GetCjoVersion().minor, minor)
            @Expect(loader.GetCjoVersion().patch, 255u8)
            @Expect(loader.IsCjoVersionAtLeast(0u8, 0u8), true)
            @Expect(loader.IsCjoVersionAtMost(0u8, 1u8), true)
            @Expect(loader.IsCjoVersionExactly(0u8, minor), true)
            @Expect(loader.IsCjoVersionAtLeast(0u8, 1u8), minor == 1u8)
            @Expect(loader.IsCjoVersionAtMost(0u8, 0u8), minor == 0u8)
            @Expect(loader.IsCjoVersionExactly(0u8, 1u8), minor == 1u8)
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
        @Expect(loader.IsCjoVersionAtLeast(0u8, 0u8), false)
        @Expect(loader.IsCjoVersionAtMost(0u8, 1u8), false)
        @Expect(loader.IsCjoVersionExactly(0u8, 0u8), false)
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
            @Expect(loader.IsCjoVersionExactly(0u8, 0u8), false)
            let depInfo = loader.LoadPackageDepInfo()
            @Expect(depInfo.isEmpty(), minor == 2u8)
            @Expect(diag.GetErrorCount(), if (minor == 2u8) { 1u64 } else { 0u64 })
            @Expect(loader.HasCjoVersion(), true)
            @Expect(loader.GetCjoVersion().minor, minor)
            @Expect(loader.IsCjoVersionAtLeast(0u8, minor), true)
            @Expect(loader.IsCjoVersionAtMost(0u8, minor), true)
            @Expect(loader.IsCjoVersionExactly(0u8, minor), true)
            @Expect(loader.IsCjoVersionAtMost(1u8, minor), false)
            println("HeaderVersionQueryAndGate observed minor=${minor}")
        }
    }

}
