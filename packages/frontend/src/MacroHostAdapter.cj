package cangjie_compiler::frontend

import cangjie_compiler::modules.MacroHost
import cangjie_compiler::modules.MacroHostImportManager
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.SourceManager
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions

// Live-backed MacroHost injected into macro_pkg.MacroExpansion so macro expansion operates on the
// real CompilerInstance state (mirrors C++ MacroExpansion holding CompilerInstance*). The frontend
// wraps basic.DiagnosticEngine and subclasses option.GlobalOptions, so bridge back to the base
// types the macro package (and the MacroHost interface) are written against.
class MacroHostAdapter <: MacroHost {
    private let ci: CompilerInstance

    init(ci: CompilerInstance) {
        this.ci = ci
    }

    public func GetDiag(): BasicDiagnosticEngine {
        return ci.diag.AsBasicDiagnosticEngine()
    }

    public func GetGlobalOptions(): OptionGlobalOptions {
        return ci.invocation.globalOptions
    }

    public prop importManager: MacroHostImportManager {
        get() {
            return ci.importManager
        }
    }

    public func GetSourceManager(): SourceManager {
        return ci.diag.GetSourceManager()
    }
}
