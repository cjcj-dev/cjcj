package cangjie_compiler::driver

@When[os == "Windows"]
import cangjie_compiler::utils.GetApplicationPath
@When[!debug && os != "Windows"]
import cangjie_compiler::utils.{CreateAltSignalStack, RegisterCrashSignalHandler}
@When[!debug && os == "Windows"]
import cangjie_compiler::utils.{RegisterCrashExceptionHandler, RegisterCrashSignalHandler}
import cangjie_compiler::macro_pkg.RuntimeInit
import cangjie_compiler::utils.{InternalError, NullPointerException, RegisterCrtlCSignalHandler, TriggerPointSetter}

@When[!debug && os != "Windows"]
private func RegisterSignalHandler(): Unit {
    CreateAltSignalStack()
    RegisterCrashSignalHandler()
}

@When[!debug && os == "Windows"]
private func RegisterSignalHandler(): Unit {
    RegisterCrashExceptionHandler()
    RegisterCrashSignalHandler()
}

public func RunDriverMain(args: Array<String>): Int64 {
    try {
        @When[!debug]
        let _ = RegisterSignalHandler()
        RegisterCrtlCSignalHandler()
        let environmentVars = StringifyEnvironment()
        if (args.isEmpty()) {
            return 1
        }
        @When[os == "Windows"]
        let maybeExePath = GetApplicationPath()
        @When[os != "Windows"]
        let maybeExePath = GetApplicationPath(args[0], environmentVars)
        if (let None <- maybeExePath) {
            return 1
        }
        let executablePath = maybeExePath.getOrThrow()
        let executableName = FileUtil.GetFileName(args[0])
        if (executableName == "cjc-frontend" || executableName == "cjc-frontend.exe") {
            let exitCode = ExecuteFrontendShim(args, executablePath)
            RuntimeInit.GetInstance().CloseRuntime()
            TempFileManager.Instance().DeleteTempFiles()
            return exitCode
        }
        let driver = Driver(args, executableName: executablePath)
        driver.EnvironmentSetup(environmentVars)
        if (!driver.ParseArgs()) {
            eprintln("Invalid options. Try: 'cjc --help' for more information.")
            return 1
        }
        let result = driver.ExecuteCompilation()
        TempFileManager.Instance().DeleteTempFiles()
        if (!result) {
            RuntimeInit.GetInstance().CloseRuntime()
            return 1
        }
        RuntimeInit.GetInstance().CloseRuntime()
    } catch (nullPointerException: NullPointerException) {
        try (iceSetter = TriggerPointSetter(nullPointerException.GetTriggerPoint())) {
            InternalError("null pointer")
        }
    }
    return 0
}
