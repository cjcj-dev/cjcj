package cjcj::sema.CJMP

import cjcj::sema.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.OutputMode

public class MPTypeCheckerImpl {
    public var typeManager: TypeManager
    public var diag: BasicDiagnosticEngine
    public var compileCommon: Bool = false
    public var compilePlatform: Bool = false
    public var severalParents: Bool = false

    // C++ src/Sema/CJMP/CheckCJMP.cpp:37-43.
    public init(ci: CompilerInstance) {
        this.typeManager = ci.typeManager
        this.diag = ci.diag.getOrThrow()
        this.compileCommon = ci.globalOptions.outputMode == OutputMode.CHIR
        this.compilePlatform = !ci.globalOptions.commonPartCjos.isEmpty()
        this.severalParents = ci.globalOptions.commonPartCjos.size > 1
    }

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
        this.diag = BasicDiagnosticEngine()
    }

    public init(typeManager: TypeManager, diag: BasicDiagnosticEngine) {
        this.typeManager = typeManager
        this.diag = diag
    }
}
