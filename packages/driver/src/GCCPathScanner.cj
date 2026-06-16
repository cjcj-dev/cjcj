package cangjie_compiler::driver

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
            for (directory in FileUtil.GetDirectories(gccDirName)) {
                if (!IsCompatibleTripleName(tripleTarget, directory.name)) {
                    continue
                }
                for (subDirectory in FileUtil.GetDirectories(directory.path)) {
                    if (let Some(version) <- GCCPathScanner.StrToGCCVersion(subDirectory.name)) {
                        if (selectedVersion < version && AllForFilesExist(subDirectory.path)) {
                            selectedPath = subDirectory.path
                            selectedVersion = version
                        }
                    }
                }
            }
        }
        if (selectedPath.isEmpty()) {
            return None
        }
        return GCCPath(selectedPath, selectedVersion)
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

private func IsCompatibleTripleName(info: TripleInfo, name: String): Bool {
    if (name == info.ToFullTripleString()) { return true }
    let arch = info.ArchToString()
    if (info.os == OSType.LINUX && info.env == EnvironmentType.GNU) {
        return name == arch + "-linux-gnu" || name == arch + "-pc-linux-gnu" ||
            name == arch + "-suse-linux" || name == arch + "-redhat-linux" ||
            name == arch + "-openEuler-linux"
    }
    if (info.os == OSType.WINDOWS) {
        return name == "x86_64-w64-mingw32"
    }
    return false
}

public func IsPossibleMatchingTripleName(info: TripleInfo, name: String): Bool {
    if (IsCompatibleTripleName(info, name)) {
        return true
    }
    if (!name.contains(info.ArchToString())) {
        return false
    }
    if (info.os == OSType.LINUX && !name.contains("linux")) {
        return false
    }
    if (info.os == OSType.WINDOWS && !name.contains("mingw") && !name.contains("windows")) {
        return false
    }
    return true
}
