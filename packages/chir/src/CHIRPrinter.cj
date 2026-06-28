package cangjie_compiler::chir

import std.fs.File

public class CHIRPrinter {
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
