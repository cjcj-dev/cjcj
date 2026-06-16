package cangjie_compiler::driver

import std.collection.*
import std.env.*
import std.fs.Directory as FSDirectory
import std.fs.File
import std.fs.FileInfo
import std.fs.canonicalize
import std.fs.exists
import std.fs.remove
import std.time.DateTime

public let DIR_SEPARATOR: String = "/"
private let FILE_PATH_MAX_LENGTH: Int64 = 4096

private func lastDirSplit(value: String): Option<Int64> {
    return value.lastIndexOf("/")
}

private func isSlash(byte: UInt8): Bool {
    return byte == b'/' || byte == b'\\'
}

private func appendPath(base: String, item: String): String {
    if (base.isEmpty() || base[base.size - 1] == b'/') {
        return base + item
    }
    return base + "/" + item
}

public func SplitString(value: String, delimiter: String): Array<String> {
    let result = ArrayList<String>()
    if (delimiter.isEmpty()) {
        result.add(value)
        return result.toArray()
    }
    var start: Int64 = 0
    while (start <= value.size) {
        let next = value.indexOf(delimiter, start)
        if (let Some(pos) <- next) {
            result.add(value[start..pos])
            start = pos + delimiter.size
        } else {
            result.add(value[start..])
            break
        }
    }
    return result.toArray()
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
}

public func GetSingleQuoted(value: String): String {
    let builder = StringBuilder()
    builder.append("'")
    for (byte in value.toArray()) {
        if (byte == b'\'') {
            builder.append("'\\''")
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    builder.append("'")
    return builder.toString()
}

public func GetCommandLineArgumentQuoted(value: String): String {
    return GetSingleQuoted(value)
}

public func PrependToPaths(prefix: String, paths: Array<String>, quoted!: Bool = false): Array<String> {
    let results = ArrayList<String>()
    for (item in paths) {
        let joined = prefix + item
        results.add(if (quoted) { FileUtil.GetQuoted(joined) } else { joined })
    }
    return results.toArray()
}

public func GetDarwinSDKVersion(sdkPath: String): Option<String> {
    let settingsPath = FileUtil.JoinPath(sdkPath, "SDKSettings.json")
    if (let Some(content) <- FileUtil.ReadFileContent(settingsPath)) {
        if (let Some(versionPos) <- content.indexOf("\"Version\"")) {
            let suffix = content[versionPos..]
            if (let Some(colonPos) <- suffix.indexOf(":")) {
                let afterColon = suffix[colonPos + 1..].trimAscii()
                if (afterColon.size > 1 && afterColon[0] == b'"') {
                    if (let Some(endPos) <- afterColon.indexOf("\"", 1)) {
                        return afterColon[1..endPos]
                    }
                }
            }
        }
    }
    return None
}

public class FileUtil {
    public static func Normalize(input: String): String {
        let builder = StringBuilder()
        var previousIsSlash = false
        for (byte in input.toArray()) {
            if (byte == 0u8) {
                break
            }
            if (isSlash(byte)) {
                if (!previousIsSlash) {
                    builder.append("/")
                }
                previousIsSlash = true
            } else {
                builder.append(String.fromUtf8([byte]))
                previousIsSlash = false
            }
        }
        return builder.toString()
    }

    public static func GetQuoted(value: String): String {
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }

    public static func JoinPath(base: String, item: String): String {
        return Normalize(appendPath(base, item))
    }

    public static func GetFileName(path: String): String {
        let normalized = Normalize(path)
        if (let Some(pos) <- lastDirSplit(normalized)) {
            return normalized[pos + 1..]
        }
        return normalized
    }

    public static func GetDirPath(path: String): String {
        let normalized = Normalize(path)
        if (let Some(pos) <- lastDirSplit(normalized)) {
            if (pos == 0) {
                return "/"
            }
            return normalized[0..pos]
        }
        return "."
    }

    public static func GetFileExtension(path: String): String {
        let name = GetFileName(path)
        if (let Some(pos) <- name.lastIndexOf(".")) {
            if (pos > 0 && pos + 1 < name.size) {
                return name[pos + 1..]
            }
        }
        return ""
    }

    public static func GetFileNameWithoutExtension(path: String): String {
        let name = GetFileName(path)
        if (let Some(pos) <- name.lastIndexOf(".")) {
            if (pos > 0) {
                return name[0..pos]
            }
        }
        return name
    }

    public static func GetFileBase(path: String): String {
        if (let Some(pos) <- path.lastIndexOf(".")) {
            return path[0..pos]
        }
        return path
    }

    public static func HasExtension(path: String, extension: String): Bool {
        return GetFileExtension(path) == extension
    }

    public static func IsDir(path: String): Bool {
        try {
            return FileInfo(path).isDirectory()
        } catch (e: Exception) {
            return false
        }
    }

    public static func FileExist(path: String): Bool {
        try {
            return exists(path)
        } catch (e: Exception) {
            return false
        }
    }

    public static func AccessExecutable(path: String): Bool {
        try {
            return FileInfo(path).canExecute()
        } catch (e: Exception) {
            return false
        }
    }

    public static func CanWrite(path: String): Bool {
        try {
            return FileInfo(path).canWrite()
        } catch (e: Exception) {
            return false
        }
    }

    public static func GetAbsPath(path: String): Option<String> {
        if (path.size > FILE_PATH_MAX_LENGTH) {
            return None
        }
        try {
            return Normalize(canonicalize(path).toString())
        } catch (e: Exception) {
            return None
        }
    }

    public static func ReadFileContent(path: String): Option<String> {
        try {
            return String.fromUtf8(File.readFrom(path))
        } catch (e: Exception) {
            return None
        }
    }

    public static func WriteToFile(path: String, content: String): Bool {
        let dir = GetDirPath(path)
        if (!FileExist(dir)) {
            try {
                FSDirectory.create(dir, recursive: true)
            } catch (e: Exception) {
                return false
            }
        }
        try {
            File.writeTo(path, content.toArray())
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func CopyFile(src: String, dest: String): Bool {
        try {
            let bytes = File.readFrom(src)
            let dir = GetDirPath(dest)
            if (!FileExist(dir)) {
                FSDirectory.create(dir, recursive: true)
            }
            File.writeTo(dest, bytes)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func RemovePath(path: String): Bool {
        try {
            remove(path, recursive: true)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public static func GetDirectories(path: String): Array<DirectoryEntry> {
        let result = ArrayList<DirectoryEntry>()
        try {
            for (info in FSDirectory.readFrom(path)) {
                if (info.isDirectory() || info.isSymbolicLink()) {
                    result.add(DirectoryEntry(info.path.toString(), info.name))
                }
            }
        } catch (e: Exception) {
            ()
        }
        return result.toArray()
    }

    public static func FindProgramByName(name: String, paths: Array<String>): String {
        if (name.isEmpty()) {
            return ""
        }
        if (name.contains("/")) {
            return name
        }
        for (dir in paths) {
            if (dir.isEmpty()) {
                continue
            }
            let candidate = JoinPath(dir, name)
            if (FileExist(candidate) && AccessExecutable(candidate)) {
                return candidate
            }
        }
        return ""
    }

    public static func SplitEnvironmentPaths(pathsString: String): Array<String> {
        let result = ArrayList<String>()
        for (entry in SplitString(pathsString, ":")) {
            if (!entry.isEmpty()) {
                if (let Some(absPath) <- GetAbsPath(entry)) {
                    result.add(absPath)
                } else {
                    result.add(entry)
                }
            }
        }
        return result.toArray()
    }

    public static func NormalizePath(path: String): String {
        if (path.isEmpty()) {
            return path
        }
        if (GetDirPath(path) == ".") {
            return JoinPath(".", GetFileName(path))
        }
        return Normalize(path)
    }

    public static func GenerateRandomHexString(): String {
        return DateTime.nowUTC().hashCode().toString()
    }
}

public class DirectoryEntry {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        this.path = path
        this.name = name
    }
}

public func GetApplicationPath(argv0: String, environmentVars: HashMap<String, String>): Option<String> {
    if (argv0.contains("/")) {
        return FileUtil.GetAbsPath(argv0)
    }
    if (let Some(pathValue) <- environmentVars.get("PATH")) {
        let found = FileUtil.FindProgramByName(argv0, FileUtil.SplitEnvironmentPaths(pathValue))
        if (!found.isEmpty()) {
            return FileUtil.GetAbsPath(found)
        }
    }
    return None
}

public func StringifyEnvironment(): HashMap<String, String> {
    let result = HashMap<String, String>()
    for (item in getVariables()) {
        result.add(item[0], item[1])
    }
    return result
}
