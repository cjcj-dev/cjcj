package cangjie_compiler::utils

public enum ProfileRecorderType {
    | INVALID_TYPE
    | TIMER
    | MEMORY
    | ALL
}

private func profileRecorderTypeMask(value: ProfileRecorderType): UInt16 {
    return match (value) {
        case ProfileRecorderType.INVALID_TYPE => 0u16
        case ProfileRecorderType.TIMER => 1u16
        case ProfileRecorderType.MEMORY => 2u16
        case ProfileRecorderType.ALL => 3u16
    }
}

public class ProfileRecorder <: Resource {
    private let title: String
    private let subtitle: String
    private let desc: String
    private var closed: Bool = false

    public init(title: String, subtitle: String, desc!: String = "") {
        this.title = title
        this.subtitle = subtitle
        this.desc = desc
        Start(title, subtitle, desc: desc)
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        try {
            Stop(title, subtitle, desc: desc)
        } catch (e: Exception) {
            ()
        }
        closed = true
    }

    public static func SetPackageName(name: String): Unit {
        UserTimer.Instance().SetPackageName(name)
        UserMemoryUsage.Instance().SetPackageName(name)
        UserCodeInfo.Instance().SetPackageName(name)
    }

    public static func SetOutputDir(path: String): Unit {
        UserTimer.Instance().SetOutputDir(path)
        UserMemoryUsage.Instance().SetOutputDir(path)
        UserCodeInfo.Instance().SetOutputDir(path)
    }

    public static func Enable(en: Bool, `type`!: ProfileRecorderType = ProfileRecorderType.ALL): Unit {
        if ((profileRecorderTypeMask(`type`) & profileRecorderTypeMask(ProfileRecorderType.TIMER)) != 0u16) {
            UserTimer.Instance().Enable(en)
        }
        if ((profileRecorderTypeMask(`type`) & profileRecorderTypeMask(ProfileRecorderType.MEMORY)) != 0u16) {
            UserMemoryUsage.Instance().Enable(en)
        }
        UserCodeInfo.Instance().Enable(UserTimer.Instance().IsEnable() || UserMemoryUsage.Instance().IsEnable())
    }

    public static func Start(title: String, subtitle: String, desc!: String = ""): Unit {
        if (UserTimer.Instance().IsEnable()) {
            UserTimer.Instance().Start(title, subtitle, desc)
        }
        if (UserMemoryUsage.Instance().IsEnable()) {
            UserMemoryUsage.Instance().Start(title, subtitle, desc)
        }
    }

    public static func Stop(title: String, subtitle: String, desc!: String = ""): Unit {
        if (UserTimer.Instance().IsEnable()) {
            UserTimer.Instance().Stop(title, subtitle, desc)
        }
        if (UserMemoryUsage.Instance().IsEnable()) {
            UserMemoryUsage.Instance().Stop(title, subtitle, desc)
        }
    }

    public static func RecordCodeInfo(item: String, getData: () -> Int64): Unit {
        if (UserTimer.Instance().IsEnable() || UserMemoryUsage.Instance().IsEnable()) {
            UserCodeInfo.Instance().RecordInfo(item, getData())
        }
    }

    public static func RecordCodeInfo(item: String, value: Int64): Unit {
        UserCodeInfo.Instance().RecordInfo(item, value)
    }

    public static func GetResult(`type`!: ProfileRecorderType = ProfileRecorderType.ALL): String {
        let builder = StringBuilder()
        if ((profileRecorderTypeMask(`type`) & (profileRecorderTypeMask(ProfileRecorderType.TIMER) |
            profileRecorderTypeMask(ProfileRecorderType.MEMORY))) != 0u16) {
            builder.append(UserCodeInfo.Instance().GetResult())
        }
        if ((profileRecorderTypeMask(`type`) & profileRecorderTypeMask(ProfileRecorderType.TIMER)) != 0u16) {
            builder.append(UserTimer.Instance().GetResult())
        }
        if ((profileRecorderTypeMask(`type`) & profileRecorderTypeMask(ProfileRecorderType.MEMORY)) != 0u16) {
            builder.append(UserMemoryUsage.Instance().GetResult())
        }
        return builder.toString()
    }
}
