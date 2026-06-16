package cangjie_compiler::driver

public func RunDriverMain(args: Array<String>): Int64 {
    let environmentVars = StringifyEnvironment()
    if (args.isEmpty()) {
        return 1
    }
    let executablePath = GetApplicationPath(args[0], environmentVars) ?? args[0]
    let executableName = FileUtil.GetFileName(args[0])
    if (executableName == "cjc-frontend" || executableName == "cjc-frontend.exe") {
        let exitCode = ExecuteFrontendShim(args, executablePath)
        TempFileManager.Instance().DeleteTempFiles()
        return exitCode
    }
    let driver = Driver(args, executableName: executablePath)
    driver.EnvironmentSetup(environmentVars)
    if (!driver.ParseArgs()) {
        eprintln("Invalid options. Try: 'cjc --help' for more information.")
        TempFileManager.Instance().DeleteTempFiles()
        return 1
    }
    let result = driver.ExecuteCompilation()
    TempFileManager.Instance().DeleteTempFiles()
    return if (result) { 0 } else { 1 }
}
