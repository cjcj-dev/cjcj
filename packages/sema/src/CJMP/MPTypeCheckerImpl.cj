package cangjie_compiler::sema.CJMP

import cangjie_compiler::sema.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

public class MPTypeCheckerImpl {
    public var typeManager: TypeManager
    public var diag: BasicDiagnosticEngine
    public var compileCommon: Bool = false
    public var compilePlatform: Bool = false
    public var severalParents: Bool = false

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
        this.diag = BasicDiagnosticEngine()
    }

    public init(typeManager: TypeManager, diag: BasicDiagnosticEngine) {
        this.typeManager = typeManager
        this.diag = diag
    }
}
