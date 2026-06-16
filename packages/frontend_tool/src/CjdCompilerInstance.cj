package cangjie_compiler::frontend_tool

import cangjie_compiler::frontend.*

public class CjdCompilerInstance <: DefaultCompilerInstance {
    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        super(invocation, diag)
        core.buildTrie = false
    }

    public override func PerformDesugarAfterSema(): Bool {
        return true
    }

    public override func PerformGenericInstantiation(): Bool {
        return true
    }

    public override func PerformOverflowStrategy(): Bool {
        return true
    }

    public override func PerformCHIRCompilation(): Bool {
        return true
    }

    public override func PerformCodeGen(): Bool {
        return true
    }

    public override func PerformResultsSaving(): Bool {
        return true
    }
}
