package cangjie_compiler::conditional_compilation

import cangjie_compiler::basic.CANGJIE_VERSION
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::option.BackendType
import cangjie_compiler::option.FileExist
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::option.JoinPath
import cangjie_compiler::option.SetupConditionalCompilationCfgFromFile
import cangjie_compiler::option.TripleInfo
import cangjie_compiler::option.Vendor
import std.collection.*

public interface ConditionalCompilationCompilerInstance {
    func GetGlobalOptions(): GlobalOptions
    func GetDiagnosticEngine(): BasicDiagnosticEngine
}

public class ConditionalCompilationConfig {
    public var backendType: BackendType = BackendType.CJNATIVE
    public var target: TripleInfo = TripleInfo()
    public var cjcVersion: String = CANGJIE_VERSION
    public var debug: Bool = false
    public var test: Bool = false
    public let passedCondition: HashMap<String, String> = HashMap<String, String>()
    public var diag: Option<BasicDiagnosticEngine> = None

    public init() {}

    public init(options: GlobalOptions) {
        LoadFromOptions(options)
    }

    public init(instance: ConditionalCompilationCompilerInstance) {
        diag = instance.GetDiagnosticEngine()
        LoadFromOptions(instance.GetGlobalOptions())
    }

    public init(options: GlobalOptions, diag: BasicDiagnosticEngine) {
        this.diag = diag
        LoadFromOptions(options)
    }

    public func LoadFromOptions(options: GlobalOptions): Unit {
        backendType = options.backend
        target = CopyTripleInfo(options.target)
        debug = options.enableCompileDebug
        test = options.enableCompileTest
        passedCondition.clear()
        for ((key, value) in options.passedWhenKeyValue) {
            passedCondition.add(key, value)
        }
        LoadLSPConfigIfNeeded(options)
    }

    private func LoadLSPConfigIfNeeded(options: GlobalOptions): Unit {
        if (!options.enableMacroInLSP) {
            return
        }
        let reporter = ConditionalDiagnosticReporter(diag)
        if (!passedCondition.isEmpty()) {
            for ((key, _) in passedCondition) {
                if (IsTargetCondition(key)) {
                    reporter.DiagnoseDefault(BasicDiagKindRefactor.dirver_cfg_same_with_builtin)
                }
            }
            if (!options.passedWhenCfgPaths.isEmpty()) {
                reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_path_ignored)
            }
            return
        }

        let cfgFileName = "cfg.toml"
        for (path in options.passedWhenCfgPaths) {
            let filePath = JoinPath(path, cfgFileName)
            if (!FileExist(filePath)) {
                reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_warning_no_such_file, args: [filePath])
                continue
            }
            if (!SetupConditionalCompilationCfgFromFile(filePath, passedCondition)) {
                reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_toml_content_err, args: [filePath])
            }
            return
        }

        let defaultCfgFilePath = if (options.packagePaths.isEmpty()) {
            cfgFileName
        } else {
            JoinPath(options.packagePaths[0], cfgFileName)
        }
        if (FileExist(defaultCfgFilePath)) {
            if (!SetupConditionalCompilationCfgFromFile(defaultCfgFilePath, passedCondition)) {
                reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_toml_content_err, args: [defaultCfgFilePath])
            }
        }
    }
}

public func CopyTripleInfo(src: TripleInfo): TripleInfo {
    let out = TripleInfo()
    out.arch = src.arch
    out.vendor = src.vendor
    out.os = src.os
    out.env = src.env
    out.apiLevel = src.apiLevel
    return out
}

public func DefaultTargetTriple(): TripleInfo {
    let out = TripleInfo()
    out.vendor = Vendor.UNKNOWN
    return out
}
