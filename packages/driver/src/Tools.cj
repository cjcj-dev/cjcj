package cangjie_compiler::driver

public class ToolInfo {
    public let name: String

    public init(name: String) {
        this.name = name
    }
}

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
