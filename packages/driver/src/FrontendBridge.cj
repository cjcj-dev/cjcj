package cjcj::driver

import std.collection.*
import cjcj::basic.{DiagFormat as BasicDiagFormat, DiagnosticEngine}
import cjcj::frontend.{CompilerInvocation, DumpAction}
import cjcj::frontend_tool.{DefaultCompilerInstance, Driver as FrontendToolDriver,
    DriverOptions as FrontendToolDriverOptions, ExecuteFrontendByDriver, IncrementalCompilerInstance,
    NeedCreateIncrementalCompilerInstance}
import cjcj::option.{DiagFormat as OptionDiagFormat, GlobalOptions}

public func ExecuteFrontendPhase(driver: Driver): Bool {
    if (!PrepareFrontendOutputs(driver.driverOptions)) {
        return false
    }
    let compilerInvocation = CompilerInvocation()
    compilerInvocation.globalOptions = GlobalOptions(driver.driverOptions)
    compilerInvocation.globalOptions.executablePath = driver.executableName
    if (compilerInvocation.globalOptions.scanDepPkg) {
        compilerInvocation.frontendOptions.dumpAction = DumpAction.DUMP_DEP_PKG
    }
    let diag = DiagnosticEngine()
    let errorCountLimit: Option<UInt64> = if (compilerInvocation.globalOptions.errorCountLimit.hasValue) {
        Some(compilerInvocation.globalOptions.errorCountLimit.value)
    } else {
        None
    }
    diag.SetErrorCountLimit(errorCountLimit)
    diag.RegisterHandler(match (compilerInvocation.globalOptions.diagFormat) {
        case OptionDiagFormat.JSON => BasicDiagFormat.JSON
        case OptionDiagFormat.NO_COLOR => BasicDiagFormat.NO_COLOR
        case OptionDiagFormat.DEFAULT => BasicDiagFormat.DEFAULT
    })
    let frontendInstance: DefaultCompilerInstance = if (
        NeedCreateIncrementalCompilerInstance(compilerInvocation.globalOptions)) {
        IncrementalCompilerInstance(compilerInvocation, diag)
    } else {
        DefaultCompilerInstance(compilerInvocation, diag)
    }
    let frontendOptions = FrontendToolDriverOptions()
    let frontendDriver = FrontendToolDriver(driverOptions: frontendOptions)
    if (!ExecuteFrontendByDriver(frontendInstance, frontendDriver)) {
        return false
    }
    if (driver.driverOptions.enableVerbose) {
        PrintFrontendCommand(driver.cangjieHome, driver.driverOptions.GenerateFrontendOptions())
    }
    ApplyFrontendOutputs(driver.driverOptions, frontendOptions)
    if (!PublishFrontendBitcodeOutputs(driver.driverOptions)) {
        return false
    }
    return PublishFrontendCjoOutputs(driver.driverOptions)
}

private func GetFrontendExecutablePath(cangjieHome: String): String {
    let exeExtension = if (HostOS() == OSType.WINDOWS) { ".exe" } else { "" }
    return FileUtil.JoinPath(FileUtil.JoinPath(cangjieHome, "bin"), "cjc-frontend" + exeExtension)
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
    var copied = true
    for (info in opts.cjoOutputFiles) {
        let target = TempFileManager.Instance().CreateNewFileInfo(info, TempFileKind.O_CJO).filePath
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
