package cjcj::driver

import std.collection.*
import std.env.*
import std.fs.Directory as FSDirectory
import std.fs.File
public import cjcj::utils.{DIR_SEPARATOR, FileUtil, GenerateRandomHexString}


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

@When[os != "Windows"]
public func GetCommandLineArgumentQuoted(value: String): String {
    return GetSingleQuoted(value)
}

@When[os == "Windows"]
public func GetCommandLineArgumentQuoted(value: String): String {
    return FileUtil.GetQuoted(value)
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
    let failureReason = Box<String>("")
    if (let Some(content) <- FileUtil.ReadFileContent(settingsPath, failureReason)) {
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

public func CopyFile(src: String, dest: String): Bool {
    try {
        let bytes = File.readFrom(src)
        let dir = FileUtil.GetDirPath(dest)
        if (!FileUtil.FileExist(dir)) {
            FSDirectory.create(dir, recursive: true)
        }
        File.writeTo(dest, bytes)
        return true
    } catch (e: Exception) {
        return false
    }
}

public func RemovePath(path: String): Bool {
    if (FileUtil.IsDir(path)) {
        return FileUtil.RemoveDirectoryRecursively(path)
    }
    return FileUtil.Remove(path)
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
