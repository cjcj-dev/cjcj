package cangjie_compiler::frontend_tool

import cangjie_compiler::frontend.*
import cangjie_compiler::option.OutputMode
import cangjie_compiler::utils.ProfileRecorder

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
        if (invocation.globalOptions.outputMode != OutputMode.CHIR) {
            return true
        }
        let recorder = ProfileRecorder("Main Stage", "Save results")
        var ret = true
        for (pkg in core.GetSourcePackages()) {
            ret = SaveCjo(pkg) && ret
        }
        recorder.close()
        return ret
    }
}
