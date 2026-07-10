package cjcj::conditional_compilation

import cjcj::ast.File
import cjcj::ast.Package
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions

public class ConditionalCompilation {
    private let impl: ConditionalCompilationImpl

    public init() {
        impl = ConditionalCompilationImpl(ConditionalCompilationConfig())
    }

    public init(config: ConditionalCompilationConfig) {
        impl = ConditionalCompilationImpl(config)
    }

    public init(options: GlobalOptions) {
        impl = ConditionalCompilationImpl(ConditionalCompilationConfig(options))
    }

    public init(options: GlobalOptions, diag: BasicDiagnosticEngine) {
        impl = ConditionalCompilationImpl(ConditionalCompilationConfig(options, diag))
    }

    /// Entrance of the conditional-compilation stage.
    public func HandleConditionalCompilation(root: Package): Unit {
        impl.HandleConditionalCompilation(root)
    }

    /// File entrance used by the package pass and by macro expansion.
    public func HandleFileConditionalCompilation(file: File): Unit {
        impl.HandleFileConditionalCompilation(file)
    }
}
