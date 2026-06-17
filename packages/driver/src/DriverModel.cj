package cangjie_compiler::driver

import std.collection.*
public import cangjie_compiler::option.{
    ArchType, BackendType, CompileTarget, EnvironmentType, LTOMode, OSType, OptimizationLevel, OutputMode,
    SanitizerType, TripleInfo, Vendor
}
import cangjie_compiler::option.enumIndex as OptionOptimizationLevelIndex

public enum ToolType {
    | UNKNOWN
    | FRONTEND
    | BACKEND
    | OTHER
    | INTERNAL_IMPLEMENTED
}

public enum ToolFutureState {
    | SUCCESS
    | RUNNING
    | FAILED
}

public enum ToolID {
    | CJC
    | CLANG
    | OPT
    | LLC
    | LD
    | LLD
    | LD64_LLD
    | AR
    | LLVM_AR
    | OBJCOPY
    | LLVM_OBJCOPY
    | DSYMUTIL
    | CODESIGN
    | STRIP
    | CMD
}

public enum TempFileKind {
    | O_CJO
    | O_CJO_FLAG
    | O_FULL_BCHIR
    | O_BCHIR
    | T_BC
    | O_BC
    | O_EXE
    | O_DYLIB
    | O_STATICLIB
    | O_MACRO
    | O_CHIR
    | T_OPT_BC
    | O_OPT_BC
    | T_ASM
    | O_OBJ
    | T_OBJ
    | T_EXE_MAC
    | T_DYLIB_MAC
}

private func toolTypeIndex(value: ToolType): Int64 {
    return match (value) {
        case ToolType.UNKNOWN => 0
        case ToolType.FRONTEND => 1
        case ToolType.BACKEND => 2
        case ToolType.OTHER => 3
        case ToolType.INTERNAL_IMPLEMENTED => 4
    }
}

extend ToolType <: Equatable<ToolType> {
    public operator func ==(right: ToolType): Bool { return toolTypeIndex(this) == toolTypeIndex(right) }
    public operator func !=(right: ToolType): Bool { return !(this == right) }
}

private func futureStateIndex(value: ToolFutureState): Int64 {
    return match (value) {
        case ToolFutureState.SUCCESS => 0
        case ToolFutureState.RUNNING => 1
        case ToolFutureState.FAILED => 2
    }
}

extend ToolFutureState <: Equatable<ToolFutureState> {
    public operator func ==(right: ToolFutureState): Bool { return futureStateIndex(this) == futureStateIndex(right) }
    public operator func !=(right: ToolFutureState): Bool { return !(this == right) }
}

public func OptimizationLevelIndex(value: OptimizationLevel): Int64 {
    return OptionOptimizationLevelIndex(value)
}

public class OrderedInput {
    public let value: String
    public let index: UInt64

    public init(value: String, index: UInt64) {
        this.value = value
        this.index = index
    }
}

public class TempFileInfo {
    public var fileName: String
    public var filePath: String
    public var rawPath: String
    public var isFrontendOutput: Bool
    public var isForeignInput: Bool

    public init(
        fileName!: String = "",
        filePath!: String = "",
        rawPath!: String = "",
        isFrontendOutput!: Bool = false,
        isForeignInput!: Bool = false
    ) {
        this.fileName = fileName
        this.filePath = filePath
        this.rawPath = rawPath
        this.isFrontendOutput = isFrontendOutput
        this.isForeignInput = isForeignInput
    }
}

public class EnvironmentOptions {
    public let allVariables: HashMap<String, String> = HashMap<String, String>()
    public var cangjieHome: Option<String> = None
    public let cangjiePaths: ArrayList<String> = ArrayList<String>()
    public let libraryPaths: ArrayList<String> = ArrayList<String>()
    public let paths: ArrayList<String> = ArrayList<String>()
    public var macOSSDKRoot: Option<String> = None

    public init() {}
}

extend TripleInfo {
    public func OSTypeToString(): String {
        return OSToString()
    }
}

@When[os == "Linux"]
public func HostOS(): OSType { return OSType.LINUX }

@When[os == "Windows"]
public func HostOS(): OSType { return OSType.WINDOWS }

@When[os == "macOS"]
public func HostOS(): OSType { return OSType.DARWIN }

@When[os != "Linux" && os != "Windows" && os != "macOS"]
public func HostOS(): OSType { return OSType.UNKNOWN }

@When[os == "macOS"]
public func HostVendor(): Vendor { return Vendor.APPLE }

@When[os != "macOS"]
public func HostVendor(): Vendor { return Vendor.UNKNOWN }

@When[os == "macOS"]
public func HostEnvironment(): EnvironmentType { return EnvironmentType.NOT_AVAILABLE }

@When[os != "macOS"]
public func HostEnvironment(): EnvironmentType { return EnvironmentType.GNU }

@When[arch == "x86_64"]
public func HostArch(): ArchType { return ArchType.X86_64 }

@When[arch == "aarch64"]
public func HostArch(): ArchType { return ArchType.AARCH64 }

@When[arch != "x86_64" && arch != "aarch64"]
public func HostArch(): ArchType { return ArchType.UNKNOWN }

public func HostTripleInfo(): TripleInfo {
    let info = TripleInfo()
    info.arch = HostArch()
    info.vendor = HostVendor()
    info.os = HostOS()
    info.env = HostEnvironment()
    return info
}
