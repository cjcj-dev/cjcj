package cangjie_compiler::driver

import std.collection.*
import cangjie_compiler::basic.PrintVersion

public class Driver {
    public let args: Array<String>
    public let driverOptions: DriverOptions = DriverOptions()
    public let executableName: String
    public let cangjieHome: String

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
        driverOptions.cangjieHome = driverOptions.environment.cangjieHome ?? cangjieHome
    }

    public func ExecuteCompilation(): Bool {
        if (driverOptions.showUsage) {
            PrintUsage()
            if (!driverOptions.srcFiles.isEmpty()) {
                eprintln("warning: cjc doesn't do compilation job in show usage mode.")
            }
            return true
        }
        if (driverOptions.enableVerbose || driverOptions.printVersionOnly) {
            PrintVersion()
        }
        if (driverOptions.printVersionOnly) {
            if (!driverOptions.srcFiles.isEmpty()) {
                eprintln("warning: cjc doesn't do compilation job in version check mode.")
            }
            return true
        }
        if (!TempFileManager.Instance().Init(driverOptions, false)) {
            return false
        }
        if (!driverOptions.srcFiles.isEmpty()) {
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

public func PrintUsage(): Unit {
    println("Usage: cjc [options] <inputs>")
    println("  -h, --help              Display available options")
    println("  -v, --version           Display version information")
    println("  -V, --verbose           Print tool invocations")
    println("  -o, --output <path>     Write output to <path>")
    println("  --target <triple>       Select target triple")
    println("  --output-type <kind>    exe, staticlib, or dylib")
}
