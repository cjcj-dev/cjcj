package cangjie_compiler::driver

import std.collection.*
import cangjie_compiler::basic.{DEFAULT_POSITION, DiagnosticEngine, DiagKindRefactor, PrintVersion}
import cangjie_compiler::option.{CreateOptionTable, Group}
import cangjie_compiler::utils.{ProfileRecorder, ProfileRecorderType}

public class Driver {
    public let args: Array<String>
    public let driverOptions: DriverOptions = DriverOptions()
    public let executableName: String
    public var cangjieHome: String

    public init(args: Array<String>, executableName!: String = "cjc") {
        this.args = args
        this.executableName = executableName
        driverOptions.executablePath = executableName
        let exeDir = FileUtil.GetDirPath(FileUtil.GetAbsPath(executableName) ?? executableName)
        cangjieHome = FileUtil.GetDirPath(exeDir)
    }

    public func ParseArgs(): Bool {
        if (!driverOptions.ParseFromArgs(args)) {
            return false
        }
        if (!driverOptions.cangjieHome.isEmpty()) {
            cangjieHome = driverOptions.cangjieHome
        } else {
            driverOptions.cangjieHome = cangjieHome
        }
        driverOptions.SetCompilationCachedPath()
        return ExtractBCPackageNames()
    }

    public func ExtractBCPackageNames(): Bool {
        let diag = DiagnosticEngine()
        for (bcPath in driverOptions.bcInputFiles) {
            let (ok, packageName, error, message) = ExtractBitcodePackageNameFromLLVM(bcPath)
            if (!ok) {
                if (error == DiagKindRefactor.bc_file_open_failed) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.bc_file_open_failed,
                        DEFAULT_POSITION,
                        arguments: [bcPath, message]
                    ).Emit()
                } else if (error == DiagKindRefactor.bc_parse_failed) {
                    diag.DiagnoseRefactor(DiagKindRefactor.bc_parse_failed, DEFAULT_POSITION, arguments: [bcPath]).Emit()
                } else {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.bc_invalid_package_name,
                        DEFAULT_POSITION,
                        arguments: [bcPath]
                    ).Emit()
                }
                return false
            }
            driverOptions.bcPackageNames.add(packageName)
        }
        return true
    }

    public func EnvironmentSetup(environmentVars: HashMap<String, String>): Unit {
        driverOptions.ReadPathsFromEnvironmentVars(environmentVars)
        driverOptions.cangjieHome = if (driverOptions.environment.cangjieHome.hasValue) {
            driverOptions.environment.cangjieHome.value
        } else {
            cangjieHome
        }
    }

    public func ExecuteCompilation(): Bool {
        if (driverOptions.showUsage) {
            PrintUsage(driverOptions)
            if (driverOptions.HasInputs()) {
                eprintln("warning: cjc doesn't do compilation job in show usage mode.")
            }
            return true
        }
        if (driverOptions.enableVerbose || driverOptions.printVersionOnly) {
            PrintVersion()
        }
        if (driverOptions.printVersionOnly) {
            if (driverOptions.HasInputs()) {
                eprintln("warning: cjc doesn't do compilation job in version check mode.")
            }
            return true
        }
        if (driverOptions.enableTimer) {
            ProfileRecorder.Enable(true, `type`: ProfileRecorderType.TIMER)
        }
        if (driverOptions.enableMemoryCollect) {
            ProfileRecorder.Enable(true, `type`: ProfileRecorderType.MEMORY)
        }
        if (!TempFileManager.Instance().Init(driverOptions, false)) {
            return false
        }
        if (!ExecuteFrontendPhase(this)) {
            return false
        }
        if (driverOptions.frontendOnlyAction) {
            return true
        }
        if (driverOptions.frontendOutputFiles.isEmpty() && driverOptions.inputObjs.isEmpty()) {
            return true
        }
        if (driverOptions.IsEmitCHIREnable()) {
            return true
        }
        return InvokeCompileToolchain()
    }

    public func InvokeCompileToolchain(): Bool {
        let job = Job()
        if (!job.Assemble(driverOptions, this)) {
            return false
        }
        return job.Execute()
    }
}

public func PrintUsage(driverOptions: DriverOptions): Unit {
    let groups = [Group.GLOBAL, Group.DRIVER]
    CreateOptionTable().Usage(
        driverOptions.GetOptionsBackend(),
        groups,
        showExperimental: driverOptions.experimentalMode
    )
}
