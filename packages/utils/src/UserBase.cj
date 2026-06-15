package cangjie_compiler::utils

public open class UserBase {
    protected var enable: Bool = false
    protected var packageName: String = ""
    protected var outputDir: String = "."

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
            ()
        }
    }

    public func WriteJson(context: String, suffix: String): Unit {
        var name = packageName
        if (let Some(pos) <- name.indexOf("/")) {
            name = name[0..pos] + "-" + name[pos + 1..]
        }
        let filename = name + suffix
        FileUtil.WriteToFile(FileUtil.JoinPath(outputDir, filename), context)
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

    protected open func GetSuffix(): String {
        return ""
    }

    protected open func GetJson(): String {
        return ""
    }
}
