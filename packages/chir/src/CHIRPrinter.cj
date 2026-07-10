package cjcj::chir

import std.fs.File
import cjcj::utils.FileUtil

public class CHIRPrinter {
    public static func PrintCHIRSerializeInfo(phase: ToCHIRPhase, path: String): Unit {
        if (path.isEmpty()) {
            eprintln("path empty")
            return
        }
        let realDirPath = FileUtil.GetAbsPath(FileUtil.GetDirPath(path))
        if (realDirPath.isNone()) {
            eprintln("realDirPath false")
            return
        }
        let fileNameWithExt = FileUtil.GetFileName(path)
        let fullPath = FileUtil.JoinPath(realDirPath.getOrThrow(), fileNameWithExt)
        try {
            File.writeTo(fullPath, ("ToCHIRPhase: " + PhaseToString(phase) + "\n").toArray())
        } catch (e: Exception) {
            eprintln("open file: " + fullPath + " failed!")
            return
        }
    }

    public static func PrintPackage(pkg: Package): Unit {
        println(pkg.ToString())
    }

    public static func PrintPackage(pkg: Package, fullPath: String): Unit {
        try {
            File.appendTo(fullPath, (pkg.ToString() + "\n").toArray())
        } catch (e: Exception) {
            eprintln("open file: " + fullPath + " failed!")
            return
        }
    }
}
