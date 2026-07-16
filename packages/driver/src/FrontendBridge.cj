package cjcj::driver

import std.collection.*
import cjcj::frontend_tool.DriverOptions as FrontendToolDriverOptions
import cjcj::frontend_tool.ExecuteFrontendWithResult

public func ExecuteFrontendPhase(driver: Driver): Bool {
    if (!PrepareFrontendOutputs(driver.driverOptions)) {
        return false
    }
    let frontendOptions = driver.driverOptions.GenerateFrontendOptions()
    let frontendArgs = BuildFrontendArgumentVector(driver.cangjieHome, frontendOptions)
    if (driver.driverOptions.enableVerbose) {
        PrintFrontendCommand(driver.cangjieHome, frontendOptions)
    }
    let result = ExecuteFrontendWithResult(driver.executableName, frontendArgs,
        driver.driverOptions.environment.allVariables, compileTarget: Some(driver.driverOptions.compileTarget),
        tempFolderPath: Some(TempFileManager.Instance().GetTempFolder()))
    if (result.exitCode != 0) {
        return false
    }
    ApplyFrontendOutputs(driver.driverOptions, result.driverOptions)
    if (!PublishFrontendBitcodeOutputs(driver.driverOptions)) {
        return false
    }
    if (!ReconcileFrontendOutputs(driver.driverOptions)) {
        return false
    }
    return PublishFrontendCjoOutputs(driver.driverOptions)
}

private func GetFrontendExecutablePath(cangjieHome: String): String {
    let exeExtension = if (HostOS() == OSType.WINDOWS) { ".exe" } else { "" }
    return FileUtil.JoinPath(FileUtil.JoinPath(cangjieHome, "bin"), "cjc-frontend" + exeExtension)
}

private func BuildFrontendArgumentVector(cangjieHome: String, options: Array<String>): Array<String> {
    let args = ArrayList<String>()
    args.add(GetFrontendExecutablePath(cangjieHome))
    for (option in options) {
        args.add(option)
    }
    return args.toArray()
}

private func PrepareFrontendOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts) || opts.IsEmitCHIREnable() ||
        !opts.frontendOutputFiles.isEmpty()) {
        return true
    }
    return true
}

private func ApplyFrontendOutputs(opts: DriverOptions, frontendOpts: FrontendToolDriverOptions): Unit {
    opts.frontendOutputFiles.clear()
    for (output in frontendOpts.frontendOutputFiles) {
        opts.frontendOutputFiles.add(TempFileInfo(
            fileName: output.fileName,
            filePath: output.filePath,
            rawPath: output.rawPath,
            isFrontendOutput: output.isFrontendOutput,
            isForeignInput: output.isForeignInput))
    }
    opts.cjoOutputFiles.clear()
    for (output in frontendOpts.cjoOutputFiles) {
        opts.cjoOutputFiles.add(TempFileInfo(
            fileName: output.fileName,
            filePath: output.filePath,
            rawPath: output.rawPath,
            isFrontendOutput: output.isFrontendOutput,
            isForeignInput: output.isForeignInput))
    }
    opts.inputCjoFile = frontendOpts.inputCjoFile
    opts.compilationCachedPath = frontendOpts.compilationCachedPath
    opts.compilationCachedDir = frontendOpts.compilationCachedDir
    opts.compilationCachedFileName = frontendOpts.compilationCachedFileName
    opts.incrementalCompileNoChange = frontendOpts.incrementalCompileNoChange
    CopyStringList(opts.symbolsNeedLocalized, frontendOpts.symbolsNeedLocalized)
    CopyStringArrayMap(opts.symbolsNeedLocalizedPerPkg, frontendOpts.symbolsNeedLocalizedPerPkg)
    opts.directBuiltinDependencies.clear()
    for (dep in frontendOpts.directBuiltinDependencies) {
        opts.directBuiltinDependencies.add(dep)
    }
    opts.indirectBuiltinDependencies.clear()
    for (dep in frontendOpts.indirectBuiltinDependencies) {
        opts.indirectBuiltinDependencies.add(dep)
    }
}

private func CopyStringList(target: ArrayList<String>, source: ArrayList<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}

private func CopyStringArrayMap(
    target: HashMap<String, ArrayList<String>>,
    source: HashMap<String, ArrayList<String>>
): Unit {
    target.clear()
    for ((key, values) in source) {
        let copiedValues = ArrayList<String>()
        for (value in values) {
            copiedValues.add(value)
        }
        target.add(key, copiedValues)
    }
}

private func PrintFrontendCommand(cangjieHome: String, args: Array<String>): Unit {
    let builder = StringBuilder()
    builder.append(GetCommandLineArgumentQuoted(GetFrontendExecutablePath(cangjieHome)))
    for (arg in args) {
        builder.append(" ")
        builder.append(GetCommandLineArgumentQuoted(arg))
    }
    println(FileUtil.Normalize(builder.toString()))
}

private func ReconcileFrontendOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts)) {
        return true
    }
    if (opts.IsEmitCHIREnable()) {
        return true
    }
    return VerifyFrontendOutputs(opts)
}

private func PublishFrontendCjoOutputs(opts: DriverOptions): Bool {
    // C++: Option/Option.h:1199-1202 and FrontendTool/FrontendTool.cpp:108,152-155.
    if (!HasFrontendSourceInput(opts) || (opts.IsEmitCHIREnable() && opts.outputMode != OutputMode.CHIR) ||
        opts.cjoOutputFiles.isEmpty()) {
        return true
    }
    // Publish each source package's serialized .cjo into the output directory under its
    // package-qualified name. The frontend registers these outputs (RegisterCjoOutputs) with fileName
    // set to ToCjoFileName(pkg); the on-disk path is a hashed cached file, so it is renamed on publish
    // for the importer to resolve it. When -o names a directory (e.g. --compile-macro), that
    // directory is the output location; otherwise the .cjo sits next to the -o file.
    let outputDir = if (opts.output.isEmpty()) {
        "."
    } else if (FileUtil.IsDir(opts.output)) {
        opts.output
    } else {
        FileUtil.GetDirPath(opts.output)
    }
    var copied = true
    for (info in opts.cjoOutputFiles) {
        let target = FileUtil.JoinPath(outputDir, info.fileName + ".cjo")
        if (info.filePath != target && !CopyFile(info.filePath, target)) {
            eprintln("error: failed to publish CJO output: " + target)
            copied = false
        }
    }
    return copied
}

private func PublishFrontendBitcodeOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts) || opts.IsEmitCHIREnable() ||
        opts.frontendOutputFiles.isEmpty() || !opts.saveTemps) {
        return true
    }
    var copied = true
    for (output in opts.frontendOutputFiles) {
        if (output.isForeignInput) {
            continue
        }
        let fileName = if (output.fileName.isEmpty()) {
            FileUtil.GetFileNameWithoutExtension(output.filePath)
        } else {
            output.fileName
        }
        let target = FileUtil.JoinPath(opts.tempFolderPath, fileName + ".bc")
        if (output.filePath != target && !CopyFile(output.filePath, target)) {
            eprintln("error: failed to publish bitcode output: " + target)
            copied = false
        } else {
            output.filePath = target
            output.rawPath = target
        }
    }
    return copied
}

private func HasFrontendSourceInput(opts: DriverOptions): Bool {
    return !opts.srcFiles.isEmpty() || opts.compilePackage || opts.scanDepPkg || opts.IsCompilingCJMPSpecific()
}

private func VerifyFrontendOutputs(opts: DriverOptions): Bool {
    for (output in opts.frontendOutputFiles) {
        if (!FileUtil.FileExist(output.filePath) || FileUtil.IsDir(output.filePath)) {
            eprintln("error: self-host frontend did not produce native bitcode output: " + output.filePath)
            return false
        }
    }
    return true
}
