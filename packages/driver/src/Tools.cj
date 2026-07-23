package cjcj::driver

public class ToolInfo {
    public let name: String

    public init(name: String) {
        this.name = name
    }
}

// Mirrors include/cangjie/Driver/Tools.inc: the _WIN32 branch names every
// tool with its .exe suffix.
@When[os == "Windows"]
public func ToolName(id: ToolID): String {
    return match (id) {
        case ToolID.CJC => "cjc.exe"
        case ToolID.CLANG => "clang.exe"
        case ToolID.OPT => "opt.exe"
        case ToolID.LLC => "llc.exe"
        case ToolID.LD => "ld.exe"
        case ToolID.LLD => "ld.lld.exe"
        case ToolID.LD64_LLD => "ld64.lld.exe"
        case ToolID.AR => "ar.exe"
        case ToolID.LLVM_AR => "llvm-ar.exe"
        case ToolID.OBJCOPY => "objcopy.exe"
        case ToolID.LLVM_OBJCOPY => "llvm-objcopy.exe"
        case ToolID.DSYMUTIL => "dsymutil.exe"
        case ToolID.CODESIGN => "codesign.exe"
        case ToolID.STRIP => "strip.exe"
        case ToolID.CMD => "cmd.exe"
    }
}

@When[os != "Windows"]
public func ToolName(id: ToolID): String {
    return match (id) {
        case ToolID.CJC => "cjc"
        case ToolID.CLANG => "clang"
        case ToolID.OPT => "opt"
        case ToolID.LLC => "llc"
        case ToolID.LD => "ld"
        case ToolID.LLD => "ld.lld"
        case ToolID.LD64_LLD => "ld64.lld"
        case ToolID.AR => "ar"
        case ToolID.LLVM_AR => "llvm-ar"
        case ToolID.OBJCOPY => "objcopy"
        case ToolID.LLVM_OBJCOPY => "llvm-objcopy"
        case ToolID.DSYMUTIL => "dsymutil"
        case ToolID.CODESIGN => "codesign"
        case ToolID.STRIP => "strip"
        case ToolID.CMD => "cmd"
    }
}
