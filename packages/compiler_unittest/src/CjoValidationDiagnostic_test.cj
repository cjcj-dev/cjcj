package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::basic.{CANGJIE_VERSION, DiagCategory}
import cjcj::basic.DiagnosticEngine as HeaderDiagnostics
import cjcj::frontend.*
import cjcj::modules.{ASTLoader, GetPackage}

// PackageTest.cpp@ed8c7bc5:1445-1556. Export real compiler data, retain the
// version field, and invalidate the length of a different serialized string.
private func InvalidValidationData(result: TestCompileResult, different: Bool): (Array<UInt8>, String) {
    let data = result.instance.ExportAST(false, RequireFirstPackage(result))
    let table = GetPackage(data)
    let version = table.GetPointer(4u16).getOrThrow()
    if (different) {
        data[version + 4] = if (data[version + 4] == 57u8) { 56u8 } else { 57u8 }
    }
    let producer = table.GetVersion().getOrThrow().str()
    let name = table.GetPointer(8u16).getOrThrow()
    for (i in 0..4) { data[name + i] = 255u8 }
    return (data, producer)
}

private func CheckValidationDiagnostic(result: TestCompileResult, data: Array<UInt8>, producer: String,
    different: Bool): Unit {
    let expected = if (different) {
        "validation of ast file 'diagnostic.package' failed: it was compiled with cjc '${producer}', " +
            "but the current compiler is cjc '${CANGJIE_VERSION}'."
    } else {
        "validation of ast file 'diagnostic.package' failed, please confirm it was created by compiler " +
            "whose version is '${CANGJIE_VERSION}'."
    }
    let diag = HeaderDiagnostics()
    let header = ASTLoader(data, "diagnostic.package", diag)
    header.SetCjoPath("diagnostic.cjo")
    @Expect(header.LoadPackageDepInfo(), "")
    let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.MODULE)
    @Assert(diagnostics.size, 1)
    println("HEADER_TARGET producer=${producer} different=${different}")
    @Expect(diagnostics[0].errorMessage, expected)

    let pkg = RequireFirstPackage(result)
    let frontendDiag = DiagnosticEngine()
    let loader = CjoSignatureMaterializer("diagnostic.package", pkg, HashMap<UInt32, File>(),
        HashMap<UInt64, File>(), ArrayList<Package>(), HashMap<String, PackageDecl>(),
        HashMap<String, HashMap<String, Decl>>(), frontendDiag,
        result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), data: Some(data))
    loader.SetCjoPath("diagnostic.cjo")
    @Expect(loader.LoadPackageDepInfo(), "")
    @Expect(frontendDiag.GetErrorCount(), 1u64)
    // The frontend exposes the production diagnostic output, not its backing
    // engine. The integration runner asserts the emitted message in this block.
    println("FRONTEND_TARGET_BEGIN")
    frontendDiag.EmitCategoryDiagnostics(DiagCategory.MODULE)
    println("FRONTEND_TARGET_END")
    println("FRONTEND_EXPECTED=${expected}")
}

@Test
public class CjoValidationDiagnosticTest {
    @TestCase
    public func DifferentProducerVersion(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        let (data, producer) = InvalidValidationData(result, true)
        CheckValidationDiagnostic(result, data, producer, true)
    }

    @TestCase
    public func SameProducerVersion(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        let (data, producer) = InvalidValidationData(result, false)
        @Expect(producer, CANGJIE_VERSION)
        CheckValidationDiagnostic(result, data, producer, false)
    }

    @TestCase
    public func UnavailableProducerVersion(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        CheckValidationDiagnostic(result, Array<UInt8>(4, repeat: 0u8), "", false)
    }
}
