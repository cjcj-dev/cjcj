package cjcj::chir

import std.fs.File
import cjcj::utils.FileUtil

public class CHIRPrinter {
    public static func PrintCHIRSerializeInfo(phase: ToCHIRPhase, path: String): Unit {
        if (path.isEmpty()) {
            eprintln("path empty")
            throw IllegalArgumentException("CHIR dump path empty")
        }
        let realDirPath = FileUtil.GetAbsPath(FileUtil.GetDirPath(path))
        if (realDirPath.isNone()) {
            eprintln("realDirPath false")
            throw IllegalArgumentException("CHIR dump realDirPath false: " + path)
        }
        let fileNameWithExt = FileUtil.GetFileName(path)
        let fullPath = FileUtil.JoinPath(realDirPath.getOrThrow(), fileNameWithExt)
        let content = ("ToCHIRPhase: " + PhaseToString(phase) + "\n").toArray()
        try {
            File.writeTo(fullPath, content)
        } catch (e: Exception) {
            eprintln("open file: " + fullPath + " failed! " + e.message)
            throw e
        }
    }

    public static func PrintPackage(pkg: Package): Unit {
        println(pkg.ToString())
    }

    // C++ CHIRPrinter.cpp:86-96 — open/write failure is reported; selfhost additionally
    // separates ToString from I/O so a printer exception is not mislabeled as open failure.
    // Dump request failure must not look like a successful compile with empty output.
    public static func PrintPackage(pkg: Package, fullPath: String): Unit {
        let text: String
        try {
            text = pkg.ToString() + "\n"
        } catch (e: Exception) {
            eprintln("CHIR dump ToString failed for " + fullPath + ": " + e.message)
            throw e
        }
        try {
            File.appendTo(fullPath, text.toArray())
        } catch (e: Exception) {
            eprintln("open file: " + fullPath + " failed! " + e.message)
            throw e
        }
    }
}
