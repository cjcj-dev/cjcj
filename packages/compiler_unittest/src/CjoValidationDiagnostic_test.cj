package cjcj::compiler_unittest

import std.collection.*
import std.env.getVariable
import cjcj::utils.{FileUtil, GenerateRandomHexString}
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::basic.{CANGJIE_VERSION, DiagCategory, DiagKindRefactorName}
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
    @Expect(DiagKindRefactorName(diagnostics[0].rKind),
        if (different) { "module_loaded_ast_failed_with_version" } else { "module_loaded_ast_failed" })

    let pkg = RequireFirstPackage(result)
    for (entry in ["dep-info", "dependencies", "common-part", "cached-type"]) {
        let frontendDiag = result.diag
        let frontendStorage = result.instance.importManager.getOrThrow().GetDiagnosticEngine()
        frontendStorage.Reset()
        let loader = CjoSignatureMaterializer(packageName, pkg, HashMap<UInt32, File>(),
            HashMap<UInt64, File>(), ArrayList<Package>(), HashMap<String, PackageDecl>(),
            HashMap<String, HashMap<String, Decl>>(), frontendDiag,
            result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), data: Some(data))
        loader.SetCjoPath(cjoPath)
        if (entry == "dep-info") {
            @Expect(loader.LoadPackageDepInfo(), "")
        } else if (entry == "dependencies") {
            @Expect(loader.LoadPackageDependencies(data), false)
        } else if (entry == "common-part") {
            @Expect(loader.PreloadCommonPartOfPackage(pkg, result.instance.invocation.globalOptions), false)
        } else {
            @Expect(loader.LoadCachedTypeForPackage(pkg, HashMap<String, Decl>()).isEmpty())
        }
        @Expect(frontendDiag.GetErrorCount(), 1u64)
        let expectedMessage = if (entry == "cached-type") {
            expected.replace("validation of ast file", "validation of cached type file")
        } else { expected }
        let frontendDiagnostics = frontendStorage.GetCategoryDiagnostic(DiagCategory.MODULE)
        @Assert(frontendDiagnostics.size, 1)
        println("FRONTEND_TARGET_BEGIN entry=${entry}")
        @Expect(frontendDiagnostics[0].errorMessage, expectedMessage)
        @Expect(DiagKindRefactorName(frontendDiagnostics[0].rKind),
            if (different) { "module_loaded_ast_failed_with_version" } else { "module_loaded_ast_failed" })
        frontendDiag.EmitCategoryDiagnostics(DiagCategory.MODULE)
        println("FRONTEND_TARGET_END")
        println("FRONTEND_EXPECTED=${expectedMessage}")

    }

}

// Exercise the importer entry that previously diagnosed before reaching the
// loader, using a real on-disk compiler export and the production search path.
private func CheckImportedValidation(result: TestCompileResult, data: Array<UInt8>, producer: String,
    valid: Bool): Unit {
    let directory = FileUtil.JoinPath(getVariable("CJO_DIAGNOSTIC_TEST_TMP") ?? ".",
        "cjo-" + GenerateRandomHexString())
    @Assert(FileUtil.CreateDirs(directory + "/"), 0)
    @Assert(FileUtil.WriteBufferToASTFile(directory + "/diagnosticfixture.cjo", data))
    let diag = DiagnosticEngine()
    // CompilerInstance.cpp:80 / CompilerInstance.cj:277 initialize the live engine
    // with a SourceManager before a successful package header materializes files.
    diag.SetSourceManager(result.diag.GetSourceManager())
    let manager = ImportManager(diag,
        result.instance.typeManager.getOrThrow().AsFaithfulSemaTypeManager(), result.instance.invocation.globalOptions)
    manager.GetSearchPath().add(directory)
    let loaded = manager.AnalyzeDepStdPkgsOfBC("diagnosticfixture")
    println("IMPORT_TARGET loaded=${loaded} expected=${valid}")
    @Expect(loaded, valid)
    if (valid) {
        @Expect(diag.GetErrorCount(), 0u64)
        if (let Some(loadedPackage) <- manager.GetPackage("diagnosticfixture")) {
            for (name in loadedPackage.GetAllDependentStdPkgs()) {
                println("VALID_STANDARD_DEPENDENCY=${name}")
            }
        }
    } else {
        let expected = "validation of ast file 'diagnosticfixture' failed: it was compiled with cjc '" +
            producer + "', but the current compiler is cjc '" + CANGJIE_VERSION + "'."
        let diagnostics = manager.GetDiagnosticEngine().GetCategoryDiagnostic(DiagCategory.MODULE)
        @Assert(diagnostics.size, 1)
        println("FRONTEND_TARGET_BEGIN")
        @Expect(diagnostics[0].errorMessage, expected)
        @Expect(DiagKindRefactorName(diagnostics[0].rKind), "module_loaded_ast_failed_with_version")
        diag.EmitCategoryDiagnostics(DiagCategory.MODULE)
        println("FRONTEND_TARGET_END")
        println("FRONTEND_EXPECTED=${expected}")
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
