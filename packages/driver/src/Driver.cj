package cangjie_compiler::driver

import std.collection.*
import cangjie_compiler::basic.PrintVersion
import cangjie_compiler::option.{CreateOptionTable, Group}

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
        for (bcPath in driverOptions.bcInputFiles) {
            let result = ExtractBitcodePackageNameFromLLVM(bcPath)
            if (!result.ok) {
                ReportBitcodePackageNameError(bcPath, result.error)
                return false
            }
            driverOptions.bcPackageNames.add(result.packageName)
        }
        return true
    }

    public func EnvironmentSetup(environmentVars: HashMap<String, String>): Unit {
        driverOptions.ReadPathsFromEnvironmentVars(environmentVars)
        if (driverOptions.environment.cangjieHome.hasValue) {
            cangjieHome = driverOptions.environment.cangjieHome.value
        }
        driverOptions.cangjieHome = cangjieHome
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
        if (!TempFileManager.Instance().Init(driverOptions, false)) {
            return false
        }
        if (!driverOptions.srcFiles.isEmpty() || driverOptions.compilePackage || driverOptions.scanDepPkg) {
            if (!ExecuteFrontendPhase(this)) {
                return false
            }
        }
        if (driverOptions.frontendOnlyAction) {
            return true
        }
        if (driverOptions.frontendOutputFiles.isEmpty() && driverOptions.inputObjs.isEmpty() &&
            driverOptions.bcInputFiles.isEmpty()) {
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

private func ReportBitcodePackageNameError(bcPath: String, error: BitcodePackageNameError): Unit {
    if (error == BitcodePackageNameError.OPEN_FAILED) {
        eprintln("error: failed to open bitcode file '${bcPath}'")
    } else if (error == BitcodePackageNameError.PARSE_FAILED) {
        eprintln("error: failed to parse bitcode file '${bcPath}'")
    } else {
        eprintln("error: invalid bitcode package name in '${bcPath}'")
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
