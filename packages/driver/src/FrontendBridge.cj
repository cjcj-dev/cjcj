package cangjie_compiler::driver

import std.collection.*
import std.fs.Directory as FSDirectory
import cangjie_compiler::frontend_tool.DriverOptions as FrontendToolDriverOptions
import cangjie_compiler::frontend_tool.ExecuteFrontendWithResult
import cangjie_compiler::utils.FailureReason as UtilsFailureReason

public func ExecuteFrontendPhase(driver: Driver): Bool {
    if (!PrepareFrontendOutputs(driver.driverOptions)) {
        return false
    }
    if (HasFrontendSourceInput(driver.driverOptions)) {
        SeedBuiltinDependenciesFromSources(driver)
    }
    let frontendArgs = driver.driverOptions.GenerateFrontendOptions()
    if (driver.driverOptions.enableVerbose) {
        PrintFrontendCommand(driver.cangjieHome, frontendArgs)
    }
    let result = ExecuteFrontendWithResult(driver.executableName, frontendArgs,
        driver.driverOptions.environment.allVariables)
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

private func SeedBuiltinDependenciesFromSources(driver: Driver): Unit {
    driver.driverOptions.directBuiltinDependencies.add("std.core")
    let seen = HashSet<String>()
    for (sourceFile in driver.driverOptions.srcFiles) {
        let reason = UtilsFailureReason()
        match (FileUtil.ReadFileContent(sourceFile, reason)) {
            case Some(content) =>
                for (line in content.split("\n")) {
                    match (ExtractImportStdPackage(line)) {
                        case Some(pkg) => AddDirectStdBuiltinDependency(driver, pkg)
                        case None => ()
                    }
                }
            case None => ()
        }
    }
}

private func AddDirectStdBuiltinDependency(driver: Driver, pkg: String): Unit {
    if (let None <- StandardLibName(pkg)) {
        return
    }
    driver.driverOptions.directBuiltinDependencies.add(pkg)
}

private func AddIndirectStdBuiltinDependency(driver: Driver, pkg: String, seen: HashSet<String>): Unit {
    if (let None <- StandardLibName(pkg)) {
        return
    }
    if (!driver.driverOptions.directBuiltinDependencies.contains(pkg)) {
        driver.driverOptions.indirectBuiltinDependencies.add(pkg)
    }
    AddStdBuiltinDependencyClosure(driver, pkg, seen)
}

private func AddStdBuiltinDependencyClosure(driver: Driver, pkg: String, seen: HashSet<String>): Unit {
    if (seen.contains(pkg)) {
        return
    }
    seen.add(pkg)
    let modulePath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "modules"),
        driver.driverOptions.GetCangjieLibTargetPathName())
    let cjoPath = FileUtil.FindSerializationFile(pkg, ".cjo", [modulePath])
    if (cjoPath.isEmpty()) {
        return
    }
    let deps = ExtractStdPackagesFromCjo(cjoPath)
    for (dep in deps) {
        if (dep != pkg) {
            AddIndirectStdBuiltinDependency(driver, dep, seen)
        }
    }
}

private func ExtractStdPackagesFromCjo(cjoPath: String): HashSet<String> {
    let out = HashSet<String>()
    let (ok, data, _) = FileUtil.ReadBinaryFileToBuffer(cjoPath)
    if (!ok) {
        return out
    }
    var builder = StringBuilder()
    for (byte in data) {
        if (byte >= 0x20u8 && byte <= 0x7eu8) {
            builder.append(String.fromUtf8([byte]))
        } else {
            AddStdPackageRefsFromText(builder.toString(), out)
            builder = StringBuilder()
        }
    }
    AddStdPackageRefsFromText(builder.toString(), out)
    return out
}

private func AddStdPackageRefsFromText(text: String, out: HashSet<String>): Unit {
    var idx: Int64 = 0
    while (idx + 4 <= text.size) {
        if (!StartsWithAt(text, idx, "std.")) {
            idx++
            continue
        }
        var end = idx
        while (end < text.size && IsStdPackageNameChar(text[end])) {
            end++
        }
        if (let Some(pkg) <- LongestStdPackagePrefix(text[idx..end])) {
            out.add(pkg)
        }
        idx = end
    }
}

private func ExtractImportStdPackage(line: String): Option<String> {
    let trimmed = StripLineComment(line).trimAscii()
    if (!trimmed.startsWith("import ")) {
        return None
    }
    var pos = "import ".size
    while (pos < trimmed.size && (trimmed[pos] == b' ' || trimmed[pos] == b'\t')) {
        pos++
    }
    let start = pos
    while (pos < trimmed.size && IsImportNameChar(trimmed[pos])) {
        pos++
    }
    if (pos <= start) {
        return None
    }
    var raw = trimmed[start..pos]
    while (raw.endsWith(".")) {
        raw = raw[0..raw.size - 1]
    }
    return LongestStdPackagePrefix(raw)
}

private func StripLineComment(line: String): String {
    if (let Some(pos) <- line.indexOf("//")) {
        return line[0..pos]
    }
    return line
}

private func LongestStdPackagePrefix(name: String): Option<String> {
    var current = name
    while (!current.isEmpty()) {
        if (let Some(_) <- StandardLibName(current)) {
            return Some(current)
        }
        if (let Some(pos) <- LastDotPos(current)) {
            current = current[0..pos]
        } else {
            return None
        }
    }
    return None
}

private func LastDotPos(value: String): Option<Int64> {
    var idx = value.size - 1
    while (idx >= 0) {
        if (value[idx] == b'.') {
            return Some(idx)
        }
        idx--
    }
    return None
}

private func StartsWithAt(value: String, start: Int64, prefix: String): Bool {
    if (start < 0 || start + prefix.size > value.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < prefix.size) {
        if (value[start + idx] != prefix[idx]) {
            return false
        }
        idx++
    }
    return true
}

private func IsStdPackageNameChar(byte: UInt8): Bool {
    return (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') ||
        (byte >= b'0' && byte <= b'9') || byte == b'_' || byte == b'.'
}

private func IsImportNameChar(byte: UInt8): Bool {
    return IsStdPackageNameChar(byte) || byte == b':'
}

private func PrepareFrontendOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts) || opts.IsEmitCHIREnable() || opts.frontendOnlyAction ||
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
    opts.inputCjoFile = frontendOpts.inputCjoFile
    opts.compilationCachedPath = frontendOpts.compilationCachedPath
    opts.compilationCachedDir = frontendOpts.compilationCachedDir
    opts.compilationCachedFileName = frontendOpts.compilationCachedFileName
    opts.incrementalCompileNoChange = frontendOpts.incrementalCompileNoChange
    for (dep in frontendOpts.directBuiltinDependencies) {
        opts.directBuiltinDependencies.add(dep)
    }
    for (dep in frontendOpts.indirectBuiltinDependencies) {
        opts.indirectBuiltinDependencies.add(dep)
    }
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
    if (!HasFrontendSourceInput(opts)) {
        return true
    }
    if (opts.IsEmitCHIREnable() || opts.frontendOnlyAction) {
        return true
    }
    return VerifyFrontendOutputs(opts)
}

private func PublishFrontendCjoOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts) || opts.IsEmitCHIREnable() || opts.frontendOnlyAction ||
        opts.frontendOutputFiles.isEmpty()) {
        return true
    }
    let sourceDir = FileUtil.GetDirPath(opts.frontendOutputFiles[0].filePath)
    let outputDir = if (opts.output.isEmpty()) { "." } else { FileUtil.GetDirPath(opts.output) }
    var copied = true
    try {
        for (info in FSDirectory.readFrom(sourceDir)) {
            if (!info.isRegular() || FileUtil.GetFileExtension(info.name) != "cjo") {
                continue
            }
            let source = FileUtil.JoinPath(sourceDir, info.name)
            let target = FileUtil.JoinPath(outputDir, info.name)
            if (source != target && !CopyFile(source, target)) {
                eprintln("error: failed to publish CJO output: " + target)
                copied = false
            }
        }
    } catch (e: Exception) {
        return true
    }
    return copied
}

private func PublishFrontendBitcodeOutputs(opts: DriverOptions): Bool {
    if (!HasFrontendSourceInput(opts) || opts.IsEmitCHIREnable() || opts.frontendOnlyAction ||
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
