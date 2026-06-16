package cangjie_compiler::driver

import std.collection.*
import cangjie_compiler::frontend_tool.ExecuteFrontend

public func ExecuteFrontendPhase(driver: Driver): Bool {
    let frontendArgs = driver.driverOptions.GenerateFrontendOptions()
    if (driver.driverOptions.enableVerbose) {
        PrintFrontendCommand(driver.cangjieHome, frontendArgs)
    }
    let exitCode = ExecuteFrontend(driver.executableName, frontendArgs, driver.driverOptions.environment.allVariables)
    if (exitCode != 0) {
        return false
    }
    return ReconcileFrontendOutputs(driver.driverOptions)
}

private func PrintFrontendCommand(cangjieHome: String, args: Array<String>): Unit {
    let exeExtension = if (HostOS() == OSType.WINDOWS) { ".exe" } else { "" }
    let frontendPath = FileUtil.JoinPath(FileUtil.JoinPath(cangjieHome, "bin"), "cjc-frontend" + exeExtension)
    let builder = StringBuilder()
    builder.append(GetCommandLineArgumentQuoted(frontendPath))
    for (arg in args) {
        builder.append(" ")
        builder.append(GetCommandLineArgumentQuoted(arg))
    }
    println(FileUtil.Normalize(builder.toString()))
}

private func ReconcileFrontendOutputs(opts: DriverOptions): Bool {
    if (opts.srcFiles.isEmpty()) {
        return true
    }
    if (opts.IsEmitCHIREnable() || opts.scanDepPkg) {
        return true
    }
    if (!opts.frontendOutputFiles.isEmpty()) {
        return VerifyFrontendOutputs(opts.frontendOutputFiles)
    }
    let expectedOutputs = PredictFrontendBitcodeOutputs(opts)
    if (expectedOutputs.isEmpty()) {
        eprintln("error: frontend completed but did not report bitcode outputs.")
        return false
    }
    if (!VerifyFrontendOutputs(expectedOutputs)) {
        return false
    }
    for (output in expectedOutputs) {
        opts.frontendOutputFiles.add(output)
    }
    return true
}

private func VerifyFrontendOutputs(outputs: ArrayList<TempFileInfo>): Bool {
    for (output in outputs) {
        if (!FileUtil.FileExist(output.filePath) || FileUtil.IsDir(output.filePath)) {
            eprintln("error: frontend output bitcode was not generated: " + output.filePath)
            return false
        }
    }
    return true
}

private func PredictFrontendBitcodeOutputs(opts: DriverOptions): ArrayList<TempFileInfo> {
    let outputs = ArrayList<TempFileInfo>()
    let fileName = PredictPrimaryFrontendOutputName(opts)
    if (fileName.isEmpty()) {
        return outputs
    }
    let info = TempFileInfo(fileName: fileName, rawPath: fileName, isFrontendOutput: true)
    let bcInfo = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.T_BC)
    bcInfo.rawPath = bcInfo.filePath
    bcInfo.isFrontendOutput = true
    outputs.add(bcInfo)
    return outputs
}

private func PredictPrimaryFrontendOutputName(opts: DriverOptions): String {
    if (opts.compilePackage && !opts.moduleName.isEmpty()) {
        return ToCjoFileName(opts.moduleName)
    }
    if (!opts.srcFiles.isEmpty()) {
        return FileUtil.GetFileNameWithoutExtension(opts.srcFiles[0])
    }
    return opts.moduleName
}

private func ToCjoFileName(fullPackageName: String): String {
    if (let Some(pos) <- fullPackageName.indexOf("::")) {
        return fullPackageName[pos + 2..] + "@" + fullPackageName[0..pos]
    }
    return fullPackageName
}
