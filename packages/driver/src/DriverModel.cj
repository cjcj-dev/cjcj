package cangjie_compiler::driver

import std.collection.*

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

public enum ArchType {
    | X86_64
    | AARCH64
    | ARM32
    | UNKNOWN
}

public enum OSType {
    | LINUX
    | WINDOWS
    | DARWIN
    | IOS
    | UNKNOWN
}

public enum EnvironmentType {
    | GNU
    | OHOS
    | ANDROID
    | MINGW32
    | SIMULATOR
    | NOT_AVAILABLE
}

public enum BackendType {
    | CJNATIVE
    | UNKNOWN
}

public enum OptimizationLevel {
    | O0
    | O1
    | O2
    | O3
    | Os
    | Oz
}

public enum OutputMode {
    | EXECUTABLE
    | STATIC_LIB
    | SHARED_LIB
    | CHIR
    | OBJ
}

public enum LTOMode {
    | NO_LTO
    | FULL_LTO
    | THIN_LTO
}

public enum SanitizerType {
    | NONE
    | ADDRESS
    | THREAD
    | HWADDRESS
}

public enum CompileTarget {
    | DEFAULT
    | EXECUTABLE
    | STATIC_LIB
    | DYNAMIC_LIB
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

private func osTypeIndex(value: OSType): Int64 {
    return match (value) {
        case OSType.LINUX => 0
        case OSType.WINDOWS => 1
        case OSType.DARWIN => 2
        case OSType.IOS => 3
        case OSType.UNKNOWN => 4
    }
}

extend OSType <: Equatable<OSType> {
    public operator func ==(right: OSType): Bool { return osTypeIndex(this) == osTypeIndex(right) }
    public operator func !=(right: OSType): Bool { return !(this == right) }
}

private func archTypeIndex(value: ArchType): Int64 {
    return match (value) {
        case ArchType.X86_64 => 0
        case ArchType.AARCH64 => 1
        case ArchType.ARM32 => 2
        case ArchType.UNKNOWN => 3
    }
}

extend ArchType <: Equatable<ArchType> {
    public operator func ==(right: ArchType): Bool { return archTypeIndex(this) == archTypeIndex(right) }
    public operator func !=(right: ArchType): Bool { return !(this == right) }
}

private func envTypeIndex(value: EnvironmentType): Int64 {
    return match (value) {
        case EnvironmentType.GNU => 0
        case EnvironmentType.OHOS => 1
        case EnvironmentType.ANDROID => 2
        case EnvironmentType.MINGW32 => 3
        case EnvironmentType.SIMULATOR => 4
        case EnvironmentType.NOT_AVAILABLE => 5
    }
}

extend EnvironmentType <: Equatable<EnvironmentType> {
    public operator func ==(right: EnvironmentType): Bool { return envTypeIndex(this) == envTypeIndex(right) }
    public operator func !=(right: EnvironmentType): Bool { return !(this == right) }
}

private func backendTypeIndex(value: BackendType): Int64 {
    return match (value) {
        case BackendType.CJNATIVE => 0
        case BackendType.UNKNOWN => 1
    }
}

extend BackendType <: Equatable<BackendType> {
    public operator func ==(right: BackendType): Bool { return backendTypeIndex(this) == backendTypeIndex(right) }
    public operator func !=(right: BackendType): Bool { return !(this == right) }
}

public func OptimizationLevelIndex(value: OptimizationLevel): Int64 {
    return match (value) {
        case OptimizationLevel.O0 => 0
        case OptimizationLevel.O1 => 1
        case OptimizationLevel.O2 => 2
        case OptimizationLevel.O3 => 3
        case OptimizationLevel.Os => 4
        case OptimizationLevel.Oz => 5
    }
}

extend OptimizationLevel <: Equatable<OptimizationLevel> {
    public operator func ==(right: OptimizationLevel): Bool { return OptimizationLevelIndex(this) == OptimizationLevelIndex(right) }
    public operator func !=(right: OptimizationLevel): Bool { return !(this == right) }
}

private func outputModeIndex(value: OutputMode): Int64 {
    return match (value) {
        case OutputMode.EXECUTABLE => 0
        case OutputMode.STATIC_LIB => 1
        case OutputMode.SHARED_LIB => 2
        case OutputMode.CHIR => 3
        case OutputMode.OBJ => 4
    }
}

extend OutputMode <: Equatable<OutputMode> {
    public operator func ==(right: OutputMode): Bool { return outputModeIndex(this) == outputModeIndex(right) }
    public operator func !=(right: OutputMode): Bool { return !(this == right) }
}

private func ltoModeIndex(value: LTOMode): Int64 {
    return match (value) {
        case LTOMode.NO_LTO => 0
        case LTOMode.FULL_LTO => 1
        case LTOMode.THIN_LTO => 2
    }
}

extend LTOMode <: Equatable<LTOMode> {
    public operator func ==(right: LTOMode): Bool { return ltoModeIndex(this) == ltoModeIndex(right) }
    public operator func !=(right: LTOMode): Bool { return !(this == right) }
}

private func sanitizerTypeIndex(value: SanitizerType): Int64 {
    return match (value) {
        case SanitizerType.NONE => 0
        case SanitizerType.ADDRESS => 1
        case SanitizerType.THREAD => 2
        case SanitizerType.HWADDRESS => 3
    }
}

extend SanitizerType <: Equatable<SanitizerType> {
    public operator func ==(right: SanitizerType): Bool { return sanitizerTypeIndex(this) == sanitizerTypeIndex(right) }
    public operator func !=(right: SanitizerType): Bool { return !(this == right) }
}

private func compileTargetIndex(value: CompileTarget): Int64 {
    return match (value) {
        case CompileTarget.DEFAULT => 0
        case CompileTarget.EXECUTABLE => 1
        case CompileTarget.STATIC_LIB => 2
        case CompileTarget.DYNAMIC_LIB => 3
    }
}

extend CompileTarget <: Equatable<CompileTarget> {
    public operator func ==(right: CompileTarget): Bool { return compileTargetIndex(this) == compileTargetIndex(right) }
    public operator func !=(right: CompileTarget): Bool { return !(this == right) }
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

public class TripleInfo {
    public var arch: ArchType
    public var os: OSType
    public var env: EnvironmentType
    public var backend: BackendType
    public var apiLevel: String
    public var raw: String

    public init() {
        arch = HostArch()
        os = HostOS()
        env = EnvironmentType.NOT_AVAILABLE
        backend = BackendType.CJNATIVE
        apiLevel = ""
        raw = ""
    }

    public func IsMacOS(): Bool { return os == OSType.DARWIN }
    public func IsMinGW(): Bool { return os == OSType.WINDOWS && env == EnvironmentType.GNU }

    public func OSTypeToString(): String {
        return match (os) {
            case OSType.LINUX => "linux"
            case OSType.WINDOWS => "windows"
            case OSType.DARWIN => "darwin"
            case OSType.IOS => "ios"
            case OSType.UNKNOWN => "unknown"
        }
    }

    public func ArchToString(): String {
        return match (arch) {
            case ArchType.X86_64 => "x86_64"
            case ArchType.AARCH64 => "aarch64"
            case ArchType.ARM32 => "arm"
            case ArchType.UNKNOWN => "unknown"
        }
    }

    public func EnvironmentToString(): String {
        return match (env) {
            case EnvironmentType.GNU => "gnu"
            case EnvironmentType.OHOS => "ohos"
            case EnvironmentType.ANDROID => "android"
            case EnvironmentType.MINGW32 => "mingw32"
            case EnvironmentType.SIMULATOR => "simulator"
            case EnvironmentType.NOT_AVAILABLE => "unknown"
        }
    }

    public func ToFullTripleString(): String {
        if (!raw.isEmpty()) {
            return raw
        }
        let envName = EnvironmentToString()
        if (envName == "unknown") {
            return ArchToString() + "-unknown-" + OSTypeToString()
        }
        return ArchToString() + "-unknown-" + OSTypeToString() + "-" + envName
    }

    public func GetEffectiveTripleString(): String {
        return ToFullTripleString()
    }
}

public func HostOS(): OSType { return OSType.LINUX }

public func HostArch(): ArchType { return ArchType.X86_64 }
