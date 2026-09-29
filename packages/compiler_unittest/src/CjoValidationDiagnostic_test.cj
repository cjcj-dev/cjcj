package cjcj::compiler_unittest

import std.collection.*
import std.env.getVariable
import cjcj::utils.{FileUtil, GenerateRandomHexString}
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
    different: Bool, packageName!: String = "diagnostic.package", cjoPath!: String = "diagnostic.cjo",
    expectedName!: String = "diagnostic.package"): Unit {
    let expected = if (different) {
        "validation of ast file '${expectedName}' failed: it was compiled with cjc '${producer}', " +
            "but the current compiler is cjc '${CANGJIE_VERSION}'."
    } else {
        "validation of ast file '${expectedName}' failed, please confirm it was created by compiler " +
            "whose version is '${CANGJIE_VERSION}'."
    }
    let diag = HeaderDiagnostics()
    let header = ASTLoader(data, packageName, diag)
    header.SetCjoPath(cjoPath)
    @Expect(header.LoadPackageDepInfo(), "")
    let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.MODULE)
    @Assert(diagnostics.size, 1)
    println("HEADER_TARGET producer=${producer} different=${different}")
    @Expect(diagnostics[0].errorMessage, expected)

    let pkg = RequireFirstPackage(result)
    let frontendDiag = DiagnosticEngine()
    let loader = CjoSignatureMaterializer(packageName, pkg, HashMap<UInt32, File>(),
        HashMap<UInt64, File>(), ArrayList<Package>(), HashMap<String, PackageDecl>(),
        HashMap<String, HashMap<String, Decl>>(), frontendDiag,
        result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), data: Some(data))
    loader.SetCjoPath(cjoPath)
    @Expect(loader.LoadPackageDepInfo(), "")
    @Expect(frontendDiag.GetErrorCount(), 1u64)
    // The frontend exposes the production diagnostic output, not its backing
    // engine. The integration runner asserts the emitted message in this block.
    println("FRONTEND_TARGET_BEGIN")
    frontendDiag.EmitCategoryDiagnostics(DiagCategory.MODULE)
    println("FRONTEND_TARGET_END")
    println("FRONTEND_EXPECTED=${expected}")
}

// Exercise the importer entry that previously diagnosed before reaching the
// loader, using a real on-disk compiler export and the production search path.
private func CheckImportedValidation(result: TestCompileResult, data: Array<UInt8>, producer: String,
    valid: Bool): Unit {
    let directory = FileUtil.JoinPath(getVariable("CJO_DIAGNOSTIC_TEST_TMP") ?? ".",
        "cjo-" + GenerateRandomHexString())
    @Assert(FileUtil.CreateDirs(directory + "/"))
    @Assert(FileUtil.WriteBufferToASTFile(directory + "/diagnosticfixture.cjo", data))
    let diag = DiagnosticEngine()
    let manager = ImportManager(diag,
        result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), result.instance.invocation.globalOptions)
    manager.GetSearchPath().add(directory)
    let loaded = manager.AnalyzeDepStdPkgsOfBC("diagnosticfixture")
    println("IMPORT_TARGET loaded=${loaded} expected=${valid}")
    @Expect(loaded, valid)
    if (valid) {
        @Expect(diag.GetErrorCount(), 0u64)
    } else {
        println("FRONTEND_TARGET_BEGIN")
        diag.EmitCategoryDiagnostics(DiagCategory.MODULE)
        println("FRONTEND_TARGET_END")
        println("FRONTEND_EXPECTED=validation of ast file 'diagnosticfixture' failed: it was compiled with cjc '" +
            producer + "', but the current compiler is cjc '" + CANGJIE_VERSION + "'.")
    }
}

@Test
public class CjoValidationDiagnosticTest {
    @TestCase
    public func DifferentProducerVersion(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        let (data, producer) = InvalidValidationData(result, true)
        CheckValidationDiagnostic(result, data, producer, true)
        CheckImportedValidation(result, data, producer, false)
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
    @TestCase
    public func EmptyPackageNameUsesPath(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        CheckValidationDiagnostic(result, Array<UInt8>(4, repeat: 0u8), "", false,
            packageName: "", expectedName: "diagnostic.cjo")
    }

    @TestCase
    public func EmptyPackageNameAndPathUsesUnknown(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        CheckValidationDiagnostic(result, Array<UInt8>(4, repeat: 0u8), "", false,
            packageName: "", cjoPath: "", expectedName: "unknown package")
    }

    @TestCase
    public func ValidDependencyHeader(): Unit {
        let result = CompileSource("package diagnosticfixture\npublic func value(): Int64 { 0 }")
        @Assert(result.ok)
        let data = result.instance.ExportAST(false, RequireFirstPackage(result))
        CheckImportedValidation(result, data, CANGJIE_VERSION, true)
    }

}
