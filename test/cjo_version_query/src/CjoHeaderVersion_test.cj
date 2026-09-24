package cjcj::cjo_version_query

import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::flatbuffers.ReadScalar
import cjcj::modules.ASTLoader
import cjcj::basic.DiagnosticEngine
import cjcj::utils.FileUtil

// PackageTest.cpp@12883f2b CjoVersionQueryOnLoader / CjoVersionCheckOnLoad.
// ASTLoader is the product library linked by cjc --test, not a copied checker.
private func VersionOffset(data: Array<UInt8>): Int64 {
    let root = Int64(ReadScalar(data, 0, 0u32))
    let vtable = root - Int64(ReadScalar(data, root, 0i32))
    return root + Int64(ReadScalar(data, vtable + 6, 0u16))
}

private func LoadFixture(): Array<UInt8> {
    let path = getVariable("CJO_FIXTURE").getOrThrow()
    let (ok, data, reason) = FileUtil.ReadBinaryFileToBuffer(path)
    if (!ok) {
        throw IllegalStateException("fixture read failed: ${reason}")
    }
    return data
}

@Test
public class CjoHeaderVersionTest {
    @TestCase
    public func HeaderQueryAndGate(): Unit {
        let data = LoadFixture()
        let offset = VersionOffset(data)
        for (minor in [0u8, 1u8, 2u8]) {
            let copy = data.clone()
            copy[offset + 1] = minor
            copy[offset + 2] = 255u8
            let diag = DiagnosticEngine()
            let loader = ASTLoader(copy, "vercheck", diag)
            loader.SetCjoPath("vercheck.cjo")
            @Expect(loader.HasCjoVersion(), false)
            let depInfo = loader.LoadPackageDepInfo()
            let refuse = minor == 2u8
            @Expect(depInfo.isEmpty(), refuse)
            @Expect(diag.GetErrorCount(), if (refuse) { 1u64 } else { 0u64 })
            if (!refuse) {
                @Expect(depInfo.contains("vercheck"), true)
                @Expect(loader.HasCjoVersion(), true)
                @Expect(loader.GetCjoVersion().major, 0u8)
                @Expect(loader.GetCjoVersion().minor, minor)
                @Expect(loader.GetCjoVersion().patch, 255u8)
                @Expect(loader.IsCjoVersionAtLeast(0u8, 0u8), true)
                @Expect(loader.IsCjoVersionAtMost(0u8, 1u8), true)
                @Expect(loader.IsCjoVersionExactly(0u8, minor), true)
                @Expect(loader.IsCjoVersionAtLeast(0u8, 1u8), minor == 1u8)
                @Expect(loader.IsCjoVersionAtMost(0u8, 0u8), minor == 0u8)
                @Expect(loader.IsCjoVersionAtLeast(1u8, 0u8), false)
                @Expect(loader.IsCjoVersionAtMost(1u8, 0u8), false)
                @Expect(loader.IsCjoVersionExactly(1u8, minor), false)
            }
            println("CjoHeaderQuery observed minor=${minor} refuse=${refuse} errors=${diag.GetErrorCount()} empty=${depInfo.isEmpty()}")
        }
        let missing = data.clone()
        let root = Int64(ReadScalar(missing, 0, 0u32))
        let vtable = root - Int64(ReadScalar(missing, root, 0i32))
        missing[vtable + 6] = 0u8
        missing[vtable + 7] = 0u8
        let diag = DiagnosticEngine()
        let loader = ASTLoader(missing, "vercheck", diag)
        loader.SetCjoPath("vercheck.cjo")
        let depInfo = loader.LoadPackageDepInfo()
        @Expect(depInfo.isEmpty(), true)
        @Expect(diag.GetErrorCount(), 1u64)
        @Expect(loader.HasCjoVersion(), false)
        @Expect(loader.GetCjoVersion().major, 0u8)
        @Expect(loader.GetCjoVersion().minor, 0u8)
        @Expect(loader.IsCjoVersionAtLeast(0u8, 0u8), false)
        @Expect(loader.IsCjoVersionExactly(0u8, 0u8), false)
        println("CjoHeaderQuery observed missing errors=${diag.GetErrorCount()} empty=${depInfo.isEmpty()}")
    }
}
