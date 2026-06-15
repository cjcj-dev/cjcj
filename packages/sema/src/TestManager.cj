package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::modules.ImportManager
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.MockMode

public enum MockKind {
    | PLAIN_MOCK
    | SPY
    | NOT_MOCK
}

public class MockContext { public init() {} }
public class MockManager { public init() {} }
public class MockSupportManager { public init() {} }
public class MockUtils { public init() {} }

public class TestManager {
    private var importManager: ImportManager
    private var typeManager: TypeManager
    private var diag: BasicDiagnosticEngine
    private var testEnabled: Bool = false
    private var mockMode: MockMode = MockMode.DEFAULT
    private var exportForTest: Bool = false

    public init(importManager: ImportManager, typeManager: TypeManager, diag: BasicDiagnosticEngine,
        compilationOptions: OptionGlobalOptions) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        testEnabled = compilationOptions.enableCompileTest
        mockMode = compilationOptions.mock
        exportForTest = compilationOptions.exportForTest
    }

    public func PreparePackageForTestIfNeeded(pkg: Package): Unit {
        if (!testEnabled && !exportForTest) {
            return
        }
        markGeneratedTestDecls(pkg)
    }

    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        if (!testEnabled && !exportForTest) {
            return
        }
        for (pkg in pkgs) {
            markGeneratedTestDecls(pkg)
        }
    }

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return decl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT) || decl.TestAttr(Attribute.PUBLIC)
    }

    public static func IsDeclGeneratedForTest(decl: Decl): Bool {
        return decl.TestAttr(Attribute.COMPILER_ADD) && decl.identifier.Val().contains("Mock")
    }

    public static func IsMockAccessor(decl: Decl): Bool {
        return decl.identifier.Val().contains("$mock") || decl.identifier.Val().contains("mockAccessor")
    }

    public func PrepareToMock(pkg: Package): Unit {
        let _ = pkg
        // TODO(selfhost:Sema): port mock support dependency synthesis and accessor generation.
    }

    public func HandleCreateMock(pkg: Package): Unit {
        let _ = pkg
        // TODO(selfhost:Sema): port createMock call validation and class generation.
    }

    private func markGeneratedTestDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                markGeneratedTestDecl(decl)
            }
        }
    }

    private func markGeneratedTestDecl(decl: Decl): Unit {
        if (IsDeclGeneratedForTest(decl)) {
            decl.toBeCompiled = true
        }
        for (member in decl.GetMemberDecls()) {
            markGeneratedTestDecl(member)
        }
    }
}
