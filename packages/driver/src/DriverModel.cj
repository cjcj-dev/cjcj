package cjcj::driver

public import cjcj::option.{
    ArchType, BackendType, CompileTarget, EnvironmentType, LTOMode, OSType, OptimizationLevel, OutputMode,
    SanitizerType, TripleInfo, Vendor
}
public import cjcj::option.EnvironmentOptions as OptionEnvironmentOptions
public import cjcj::option.MaybeString as OptionMaybeString
public import cjcj::option.OrderedInput as OptionOrderedInput
public import cjcj::option.TempFileInfo as OptionTempFileInfo
public import cjcj::option.TempFileKind
public import cjcj::option.TempFileManager
public import cjcj::option.{DylibSuffix, ObjSuffix, TempFileKindSuffix}
import cjcj::option.enumIndex as OptionOptimizationLevelIndex

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

public type OrderedInput = OptionOrderedInput

public type TempFileInfo = OptionTempFileInfo

public type EnvironmentOptions = OptionEnvironmentOptions
public type MaybeString = OptionMaybeString

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
