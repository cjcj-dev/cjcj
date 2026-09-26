package cjcj::utils

import std.fs.File

public abstract class UserBase {
    protected var enable: Bool = false
    protected var packageName: String = ""
    protected var outputDir: String = ""

    public init() {}

    public open func GetResult(): String {
        if (!enable) {
            return ""
        }
        return GetJson()
    }

    public func OutputResult(): Unit {
        if (!enable) {
            return
        }
        try {
            WriteJson(GetResult(), GetSuffix())
        } catch (e: Exception) {
            eprintln("Get an exception while running function 'OutputResult' !!!\n")
        }
    }

    private func firstDirSeparator(name: String, from: Int64): Option<Int64> {
        var pos = from
        while (pos < name.size) {
            let byte = name[pos]
            var sep: Int64 = 0
            while (sep < DIR_SEPARATOR.size) {
                if (byte == DIR_SEPARATOR[sep]) {
                    return pos
                }
                sep++
            }
            pos++
        }
        return None
    }

    public func WriteJson(context: String, suffix: String): Unit {
        var name = packageName
        var from: Int64 = 0
        while (let Some(pos) <- firstDirSeparator(name, from)) {
            name = name[0..pos] + "-" + name[(pos + 1)..]
            from = pos + 1
        }
        let filename = name + suffix
        try {
            File.writeTo(FileUtil.JoinPath(outputDir, filename), context.toArray())
        } catch (e: Exception) {
            ()
        }
    }

    public func Enable(en: Bool): Unit {
        enable = en
    }

    public func IsEnable(): Bool {
        return enable
    }

    public func SetPackageName(name: String): Unit {
        packageName = name
    }

    public func SetOutputDir(path: String): Unit {
        if (FileUtil.IsDir(path)) {
            outputDir = path
        } else {
            outputDir = FileUtil.GetDirPath(path)
        }
    }

    protected func GetSuffix(): String

    protected func GetJson(): String
}
