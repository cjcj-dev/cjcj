package cjcj::driver

@When[!debug && os != "Windows"]
import cjcj::utils.{CreateAltSignalStack, RegisterCrashSignalHandler}
@When[!debug && os == "Windows"]
import cjcj::option.RegisterCrashExceptionHandler
@When[!debug && os == "Windows"]
import cjcj::utils.RegisterCrashSignalHandler
import cjcj::macro_pkg.RuntimeInit
import cjcj::frontend.{DiagnosticEngine, SourceManager}
import cjcj::utils.{InternalError, NullPointerException, TriggerPointSetter}
import cjcj::option.RegisterCrtlCSignalHandler

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
        let sourceManager = SourceManager()
        // C++: src/main.cpp:62-64, main-scope SourceManager and DiagnosticEngine lifetime.
        let diag = DiagnosticEngine()
        var failed = false
        try {
        diag.SetSourceManager(sourceManager)
        // Resolve the invocation entry, not the retained process image. Both
        // Driver and the frontend shim use this same compiler-relative root.
        let maybeExePath = GetApplicationPath(args[0], environmentVars)
        if (let None <- maybeExePath) {
            return 1
        }
        let executablePath = maybeExePath.getOrThrow()
        let executableName = FileUtil.GetFileName(args[0])
        if (executableName == "cjc-frontend" || executableName == "cjc-frontend.exe") {
            let exitCode = ExecuteFrontendShim(args, executablePath)
            return exitCode
        }
        let driver = Driver(args, diag, executableName: executablePath)
        driver.EnvironmentSetup(environmentVars)
        if (!driver.ParseArgs()) {
            eprintln("Invalid options. Try: 'cjc --help' for more information.")
            return 1
        }
        let result = driver.ExecuteCompilation()
        if (!result) {
            return 1
        }
        } catch (e: Exception) {
            failed = true
            throw e
        } finally {
            // Frontend owners have joined their AST task before this outer
            // scope releases process resources. Attempt all three cleanups;
            // never replace the original compiler exception with a close error.
            var cleanupFailure: Option<Exception> = None
            try {
                TempFileManager.Instance().DeleteTempFiles()
            } catch (e: Exception) {
                cleanupFailure = Some(e)
            }
            try {
                RuntimeInit.GetInstance().CloseRuntime()
            } catch (e: Exception) {
                if (cleanupFailure.isNone()) { cleanupFailure = Some(e) }
            }
            try {
                diag.close()
            } catch (e: Exception) {
                if (cleanupFailure.isNone()) { cleanupFailure = Some(e) }
            }
            if (!failed) {
                if (let Some(e) <- cleanupFailure) { throw e }
            }
        }
    } catch (nullPointerException: NullPointerException) {
        try (iceSetter = TriggerPointSetter(nullPointerException.GetTriggerPoint())) {
            InternalError("null pointer")
        }
    }
    return 0
}
