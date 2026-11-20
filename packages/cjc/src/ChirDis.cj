package cjcj::cjc

import cjcj::basic.PrintVersion
import cjcj::chir.{CHIRBuilder, CHIRContext, CHIRDeserializer, CHIRPrinter, ToCHIRPhase}
import cjcj::utils.{CHIR_READABLE_FILE_EXTENSION, FileUtil}
import std.core.Box as CoreBox

// Installed under the upstream tool name. Use the reader linked into this
// compiler so its wire identifier, attribute word and intrinsic numbers agree.
func RunChirDis(args: Array<String>): Int64 {
    if (args.size == 2 && args[1] == "-v") { PrintVersion(); return 0 }
    if (args.size == 2 && args[1] == "-h") { println("Usage: chir-dis file.chir"); return 0 }
    if (args.size != 2 || args[1].isEmpty() || args[1].startsWith("-")) {
        eprintln("Usage: chir-dis file.chir")
        return 1
    }
    try {
        let context = CHIRContext()
        let phase = CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)
        if (!CHIRDeserializer.Deserialize(args[1], CHIRBuilder(context), phase)) { return 1 }
        let output = "./" + FileUtil.GetFileNameWithoutExtension(args[1]) + CHIR_READABLE_FILE_EXTENSION
        let pkg = context.GetCurPackage().getOrThrow()
        CHIRPrinter.PrintCHIRSerializeInfo(phase.value, output)
        CHIRPrinter.PrintPackage(pkg, output)
        return 0
    } catch (e: Exception) {
        eprintln("chir-dis: " + e.message)
        return 1
    }
}
