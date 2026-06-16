package cangjie_compiler::driver

import std.env.*

main(): Int64 {
    let args = getCommandLine()
    let environmentVars = StringifyEnvironment()
    if (args.isEmpty()) {
        return 1
    }
    let executablePath = GetApplicationPath(args[0], environmentVars) ?? args[0]
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
