package cangjie_compiler::driver

import cangjie_compiler::utils.Directory
import std.collection.*
import std.convert.*

public struct GCCVersion {
    public let major: UInt8
    public let minor: UInt8
    public let build: UInt8

    public init(major!: UInt8 = 0u8, minor!: UInt8 = 0u8, build!: UInt8 = 0u8) {
        this.major = major
        this.minor = minor
        this.build = build
    }

    public operator func <(right: GCCVersion): Bool {
        if (major != right.major) { return major < right.major }
        if (minor != right.minor) { return minor < right.minor }
        return build < right.build
    }

    public operator func ==(right: GCCVersion): Bool {
        return major == right.major && minor == right.minor && build == right.build
    }
}

public class GCCPath {
    public let libPath: String
    public let gccVersion: GCCVersion

    public init(libPath: String, gccVersion: GCCVersion) {
        this.libPath = libPath
        this.gccVersion = gccVersion
    }
}

public class GCCPathScanner {
    private let tripleTarget: TripleInfo
    private let forFiles: ArrayList<String> = ArrayList<String>()
    private let searchPaths: ArrayList<String> = ArrayList<String>()

    public init(tripleTarget: TripleInfo, files: ArrayList<String>, searchPaths: ArrayList<String>) {
        this.tripleTarget = tripleTarget
        for (file in files) { forFiles.add(file) }
        for (path in searchPaths) { this.searchPaths.add(path) }
    }

    public func Scan(): Option<GCCPath> {
        var selectedPath = ""
        var selectedVersion = GCCVersion()
        for (dirPrefix in searchPaths) {
            let gccDirName = FileUtil.JoinPath(dirPrefix, "gcc")
            let directories = GCCPathScanner.GetAllMatchingSubDirectories(tripleTarget, FileUtil.GetDirectories(gccDirName))
            for (directory in directories) {
                if (let Some(version) <- GCCPathScanner.StrToGCCVersion(directory.name)) {
                    if (selectedVersion < version && AllForFilesExist(directory.path)) {
                        selectedPath = directory.path
                        selectedVersion = version
                    }
                }
            }
        }
        if (selectedPath.isEmpty()) {
            return None
        }
        return GCCPath(selectedPath, selectedVersion)
    }

    private static func GetAllMatchingSubDirectories(target: TripleInfo, directories: Array<Directory>): ArrayList<Directory> {
        let possibleDirectories = ArrayList<Directory>()
        for (directory in directories) {
            if (IsCompatiableTripleName(target, directory.name) || IsPossibleMatchingTripleName(target, directory.name)) {
                for (subDirectory in FileUtil.GetDirectories(directory.path)) {
                    possibleDirectories.add(subDirectory)
                }
            }
        }
        return possibleDirectories
    }

    public static func StrToGCCVersion(versionStr: String): Option<GCCVersion> {
        if (versionStr.isEmpty()) { return None }
        let parts = SplitString(versionStr, ".")
        if (parts.size > 3) { return None }
        let nums = ArrayList<UInt8>()
        for (part in parts) {
            if (part.isEmpty()) { return None }
            for (byte in part.toArray()) {
                if (byte < b'0' || byte > b'9') { return None }
            }
            if (let Some(parsed) <- TryParseGCCVersionPart(part)) {
                if (parsed > 255u64) { return None }
                nums.add(UInt8(parsed))
            } else {
                return None
            }
        }
        while (nums.size < 3) {
            nums.add(0u8)
        }
        return GCCVersion(major: nums[0], minor: nums[1], build: nums[2])
    }

    private func AllForFilesExist(path: String): Bool {
        for (file in forFiles) {
            if (!FileUtil.FileExist(FileUtil.JoinPath(path, file))) {
                return false
            }
        }
        return true
    }
}

private func TryParseGCCVersionPart(value: String): Option<UInt64> {
    try {
        return UInt64.parse(value)
    } catch (e: Exception) {
        return None
    }
}

private func IsCompatiableTripleName(info: TripleInfo, name: String): Bool {
    if (info.os == OSType.LINUX && info.env == EnvironmentType.GNU && info.vendor == Vendor.UNKNOWN) {
        let arch = info.ArchToString()
        return name == arch + "-linux-gnu" || name == arch + "-pc-linux-gnu" ||
            name == arch + "-suse-linux" || name == arch + "-redhat-linux" ||
            name == arch + "-openEuler-linux" || name == info.ToFullTripleString()
    }
    let tripleName = info.ToFullTripleString()
    if (tripleName == "x86_64-unknown-windows-gnu") {
        return name == tripleName || name == "x86_64-w64-mingw32"
    }
    return false
}

public func IsPossibleMatchingTripleName(info: TripleInfo, name: String): Bool {
    let parts = SplitString(name, "-")
    if (parts.size != 3 && parts.size != 4) { return false }
    if (parts[0] != info.ArchToString()) { return false }
    if (parts[parts.size - 2] != info.OSToString()) { return false }
    if (parts[parts.size - 1] != info.EnvironmentToString()) { return false }
    return true
}
