package cangjie_compiler::driver

import std.collection.*

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
            let fileName = FileUtil.GetFileNameWithoutExtension(bcPath)
            if (fileName.isEmpty()) {
                eprintln("error: invalid bitcode input '${bcPath}'")
                return false
            }
            // TODO(selfhost:Driver): Bind LLVM bitcode reader through C FFI and extract Module::sourceFileName,
            // matching Driver::ExtractBCPackageNames instead of using the filename fallback.
            driverOptions.bcPackageNames.add(fileName)
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
            // TODO(selfhost:Driver): Invoke the self-hosted FrontendTool package once Driver can depend on it
            // without changing package metadata in this module-only port step.
            eprintln("error: frontend execution from Driver is not wired in this package build yet.")
            return false
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

public func PrintVersion(): Unit {
    println("Cangjie Compiler self-host Driver")
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
