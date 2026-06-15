package cangjie_compiler::option

public class TripleInfo {
    public var arch: ArchType = ArchType.X86_64
    public var vendor: Vendor = Vendor.UNKNOWN
    public var os: OSType = OSType.LINUX
    public var env: EnvironmentType = EnvironmentType.GNU
    public var apiLevel: String = ""

    public init() {}

    public func ArchToString(): String {
        return match (arch) {
            case ArchType.X86_64 => "x86_64"
            case ArchType.AARCH64 => "aarch64"
            case ArchType.ARM64 => "arm64"
            case ArchType.ARM32 => "arm"
            case ArchType.UNKNOWN => "unknown"
        }
    }

    public func OSToString(): String {
        return match (os) {
            case OSType.WINDOWS => "windows"
            case OSType.LINUX => "linux"
            case OSType.DARWIN => "darwin"
            case OSType.IOS => "ios"
            case OSType.UNKNOWN => "unknown"
        }
    }

    public func VendorToString(): String {
        return match (vendor) {
            case Vendor.PC => "pc"
            case Vendor.APPLE => "apple"
            case Vendor.UNKNOWN => "unknown"
        }
    }

    public func EnvironmentToSimpleString(): String {
        return match (env) {
            case EnvironmentType.OHOS => "ohos"
            case EnvironmentType.GNU => "gnu"
            case EnvironmentType.ANDROID => "android"
            case EnvironmentType.SIMULATOR => "simulator"
            case EnvironmentType.NOT_AVAILABLE => ""
        }
    }

    public func EnvironmentToString(): String {
        if (env == EnvironmentType.ANDROID) { return "android" + apiLevel }
        return EnvironmentToSimpleString()
    }

    public func ToTripleString(): String {
        if (vendor == Vendor.APPLE) {
            var triple = ArchToString() + "-" + VendorToString() + "-" + OSToString()
            if (os == OSType.IOS) { triple += apiLevel }
            if (env != EnvironmentType.NOT_AVAILABLE) { triple += "-" + EnvironmentToString() }
            return triple
        }
        return ArchToString() + "-" + OSToString() + "-" + EnvironmentToString()
    }

    public func ToFullTripleString(): String {
        var systemStr = OSToString()
        let envStr = EnvironmentToString()
        if (systemStr != "unknown" && envStr != "unknown") {
            systemStr = systemStr + "-" + envStr
        }
        return ArchToString() + "-" + VendorToString() + "-" + systemStr
    }

    public func GetEffectiveTripleString(): String {
        let triple = ToTripleString()
        if (triple == "aarch64-linux-ohos") { return "aarch64-linux-gnu" }
        if (triple == "arm-linux-ohos") { return "armv7a-linux-gnu" }
        if (triple == "x86_64-windows-gnu") { return "x86_64-w64-mingw32" }
        if (triple == "aarch64-ios-simulator") { return "arm64-apple-ios17.5-simulator" }
        if (StartsWith(triple, "arm-linux-android")) {
            return "armv7a-linux-androideabi" + triple["arm-linux-android".size..]
        }
        return triple
    }

    public func GetOSFamily(): OSType { return os }
    public func IsMinGW(): Bool { return os == OSType.WINDOWS && env == EnvironmentType.GNU }
    public func IsMacOS(): Bool { return vendor == Vendor.APPLE && (os == OSType.DARWIN || os == OSType.IOS) }
    public func IsArm32(): Bool { return arch == ArchType.ARM32 }
    public func GetArchType(): ArchType { return arch }
    public func Equal(other: TripleInfo): Bool {
        return arch == other.arch && vendor == other.vendor && os == other.os && env == other.env
    }
}

public func BackendToString(backend: BackendType): String {
    return match (backend) {
        case BackendType.CJNATIVE => "cjnative"
        case BackendType.UNKNOWN => "unknown"
    }
}

public func IsUnsafeBackend(backendType: BackendType): Bool {
    return backendType == BackendType.CJNATIVE
}

public func IsPossibleMatchingTripleName(info: TripleInfo, name: String): Bool {
    let parts = SplitString(name, "-")
    if (parts.size != 3 && parts.size != 4) { return false }
    if (parts[0] != info.ArchToString()) { return false }
    if (parts[parts.size - 2] != info.OSToString()) { return false }
    if (parts[parts.size - 1] != info.EnvironmentToString()) { return false }
    return true
}

public func GetSharedLibraryExtension(osType: OSType): String {
    return match (osType) {
        case OSType.WINDOWS => ".dll"
        case OSType.DARWIN => ".dylib"
        case OSType.IOS => ".dylib"
        case OSType.LINUX => ".so"
        case OSType.UNKNOWN => ".so"
    }
}
