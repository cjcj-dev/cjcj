package cjcj::frontend

import cjcj::modules.MacroHost
import cjcj::modules.MacroHostImportManager
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.SourceManager
import cjcj::option.GlobalOptions as OptionGlobalOptions

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

    public func GetRuntimeLibPath(): String {
        return ci.invocation.GetRuntimeLibPath()
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
