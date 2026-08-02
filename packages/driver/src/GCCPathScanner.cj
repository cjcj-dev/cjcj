package cjcj::driver

import cjcj::utils.{CJC_ASSERT, Directory, Stoi}
import std.collection.*

public struct GCCVersion {
    public var major: UInt8
    public var minor: UInt8
    public var build: UInt8

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
        if (searchPaths.isEmpty()) {
            return None
        }
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
        let hasInvalidDigits = { c: UInt8 => c < b'0' || c > b'9' }

        var ver = GCCVersion()
        let majorEndIndexOpt = versionStr.indexOf(".")
        if (let Some(majorEndIndexFound) <- majorEndIndexOpt) {
            if (majorEndIndexFound == 0) {
                return None
            }
        }
        var majorEndIndex = majorEndIndexOpt ?? versionStr.size
        var invalidMajorVer = false
        for (byte in versionStr[0..majorEndIndex].toArray()) {
            if (hasInvalidDigits(byte)) {
                invalidMajorVer = true
                break
            }
        }
        if (invalidMajorVer) {
            return None
        }
        let majorVer = Stoi(versionStr[0..majorEndIndex])
        if (let None <- majorVer) {
            return None
        }
        CJC_ASSERT(majorVer.getOrThrow() >= 0 && majorVer.getOrThrow() <= 255)
        ver.major = UInt8(majorVer.getOrThrow())

        if (majorEndIndex == versionStr.size) {
            return ver
        }

        let minorEndIndexOpt = versionStr.indexOf(".", majorEndIndex + 1)
        if (let Some(minorEndIndexFound) <- minorEndIndexOpt) {
            if (minorEndIndexFound == majorEndIndex + 1) {
                return None
            }
        }

        var minorEndIndex = minorEndIndexOpt ?? versionStr.size
        var invalidMinorVer = false
        for (byte in versionStr[majorEndIndex + 1..minorEndIndex].toArray()) {
            if (hasInvalidDigits(byte)) {
                invalidMinorVer = true
                break
            }
        }
        if (invalidMinorVer) {
            return None
        }

        let minorVer = Stoi(versionStr[majorEndIndex + 1..minorEndIndex])
        if (let None <- minorVer) {
            return None
        }
        CJC_ASSERT(minorVer.getOrThrow() >= 0 && minorVer.getOrThrow() <= 255)
        ver.minor = UInt8(minorVer.getOrThrow())

        if (minorEndIndex == versionStr.size) {
            return ver
        }

        if (versionStr.size == minorEndIndex + 1) {
            return None
        }

        var invalidBuildVer = false
        for (byte in versionStr[minorEndIndex + 1..].toArray()) {
            if (hasInvalidDigits(byte)) {
                invalidBuildVer = true
                break
            }
        }
        if (invalidBuildVer) {
            return None
        }

        let buildVer = Stoi(versionStr[minorEndIndex + 1..])
        if (let None <- buildVer) {
            return None
        }
        CJC_ASSERT(buildVer.getOrThrow() >= 0 && buildVer.getOrThrow() <= 255)
        ver.build = UInt8(buildVer.getOrThrow())
        return ver
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
