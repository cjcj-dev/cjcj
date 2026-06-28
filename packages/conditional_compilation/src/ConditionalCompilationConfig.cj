package cangjie_compiler::conditional_compilation

import cangjie_compiler::basic.CANGJIE_VERSION
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.SplitLines
import cangjie_compiler::basic.SplitString
import cangjie_compiler::option.BackendType
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::option.TripleInfo
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.NFC as UtilsNFC
import std.collection.*

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
            let filePath = FileUtil.JoinPath(path, cfgFileName)
            if (!FileUtil.FileExist(filePath)) {
                reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_warning_no_such_file, args: [filePath])
                continue
            }
            let _ = SetupLSPConditionalCompilationCfgFromFile(filePath, passedCondition, reporter)
            return
        }

        let defaultCfgFilePath = if (options.packagePaths.isEmpty()) {
            cfgFileName
        } else {
            FileUtil.JoinPath(options.packagePaths[0], cfgFileName)
        }
        if (FileUtil.FileExist(defaultCfgFilePath)) {
            let _ = SetupLSPConditionalCompilationCfgFromFile(defaultCfgFilePath, passedCondition, reporter)
        }
    }
}

private func IsLSPCfgFileBuiltinCondition(key: String): Bool {
    return key == "os" || key == "backend" || key == "arch" || key == "debug" ||
        key == "cjc_version" || key == "test"
}

private func IsLSPEscaped(input: String, index: Int64): Bool {
    var count: Int64 = 0
    var idx = index
    while (idx >= 0 && input[idx] == b'\\') {
        count++
        idx--
    }
    return count % 2 == 1
}

private func FindLSPTomlComment(line: String): Int64 {
    var insideString = false
    var idx: Int64 = 0
    while (idx < line.size) {
        if (!insideString && line[idx] == b'#') {
            return idx
        }
        if (line[idx] == b'"' && (idx == 0 || !IsLSPEscaped(line, idx - 1))) {
            insideString = !insideString
        }
        idx++
    }
    return -1
}

private func SeeingLSPTomlComment(line: String): Bool {
    if (line.isEmpty() || !line.contains("#")) {
        return false
    }
    var idx: Int64 = 0
    while (idx < line.size) {
        if (line[idx] == b' ' || line[idx] == b'\t') {
            idx++
            continue
        }
        return line[idx] == b'#'
    }
    return true
}

private func ParseAndCheckLSPConditionVar(
    key: String,
    map: HashMap<String, String>,
    reporter: ConditionalDiagnosticReporter
): Option<String> {
    if (!FileUtil.IsIdentifier(key)) {
        reporter.DiagnoseDefault(BasicDiagKindRefactor.dirver_cfg_invaild_identifier)
        return None
    }
    var normalizedKey = key
    if (normalizedKey.size > 2 && normalizedKey[0] == b'`' && normalizedKey[normalizedKey.size - 1] == b'`') {
        normalizedKey = normalizedKey[1..normalizedKey.size - 1]
    }
    normalizedKey = UtilsNFC(normalizedKey)
    if (IsLSPCfgFileBuiltinCondition(normalizedKey)) {
        reporter.DiagnoseDefault(BasicDiagKindRefactor.dirver_cfg_same_with_builtin)
        return None
    }
    if (map.contains(normalizedKey)) {
        reporter.DiagnoseDefault(BasicDiagKindRefactor.dirver_cfg_key_repeat)
        return None
    }
    return normalizedKey
}

private func ParseLSPConditionKeyValueLine(
    line: String,
    map: HashMap<String, String>,
    reporter: ConditionalDiagnosticReporter
): Bool {
    let commentPos = FindLSPTomlComment(line)
    let processedLine = if (commentPos >= 0) { line[0..commentPos] } else { line }
    let kv = SplitString(processedLine, "=")
    if (kv.size != 2) {
        reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_toml_content_err)
        return false
    }
    let key = kv[0].trimAscii()
    let quotedValue = kv[1].trimAscii()
    if (key.isEmpty() || quotedValue.size <= 2 || quotedValue[0] != b'"' ||
        quotedValue[quotedValue.size - 1] != b'"') {
        reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_toml_content_err)
        return false
    }
    if (let Some(normalizedKey) <- ParseAndCheckLSPConditionVar(key, map, reporter)) {
        let unquotedValue = quotedValue[1..quotedValue.size - 1].replace("\\\"", "\"")
        map.add(normalizedKey, unquotedValue)
        return true
    }
    return false
}

private func SetupLSPConditionalCompilationCfgFromFile(
    filePath: String,
    map: HashMap<String, String>,
    reporter: ConditionalDiagnosticReporter
): Bool {
    let failReason = Box<String>("")
    if (let Some(content) <- FileUtil.ReadFileContent(filePath, failReason)) {
        for (line in SplitLines(content)) {
            if (line.isEmpty() || SeeingLSPTomlComment(line)) {
                continue
            }
            if (!ParseLSPConditionKeyValueLine(line, map, reporter)) {
                return false
            }
        }
        return true
    }
    reporter.DiagnoseDefault(BasicDiagKindRefactor.driver_cfg_file_read_failed, args: [filePath, failReason.value])
    return false
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
