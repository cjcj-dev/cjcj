package cjcj::utils

import std.collection.*
import std.convert.*
import std.fs.File

private let DISPLAY_PRECISION: Int64 = 2

private class UserMemoryInfo {
    let title: String
    let subtitle: String
    let desc: String
    var start: Float64
    var end: Float64 = 0.0

    init(title: String, subtitle: String, desc: String, start: Float64) {
        this.title = title
        this.subtitle = subtitle
        this.desc = desc
        this.start = start
    }
}

public class UserMemoryUsage <: UserBase {
    private static let singleton = UserMemoryUsage()
    private let titleOrder = ArrayList<String>()
    private let titleInfoMap = HashMap<String, ArrayList<UserMemoryInfo>>()

    private init() {
        super()
    }

    public static func Instance(): UserMemoryUsage {
        return singleton
    }

    public func Start(title: String, subtitle: String, desc: String): Unit {
        if (!titleOrder.contains(title)) {
            titleOrder.add(title)
        }
        let currentInfos = titleInfoMap.get(title)
        let infos = if (let Some(existing) <- currentInfos) {
            existing
        } else {
            let created = ArrayList<UserMemoryInfo>()
            titleInfoMap.add(title, created)
            created
        }
        for (info in infos) {
            if (info.subtitle == subtitle) {
                info.start = Sampling()
                return
            }
        }
        infos.add(UserMemoryInfo(title, subtitle, desc, Sampling()))
    }

    public func Stop(title: String, subtitle: String, desc: String): Unit {
        let _ = desc
        if (let Some(infos) <- titleInfoMap.get(title)) {
            for (info in infos) {
                if (info.subtitle == subtitle) {
                    info.end = Sampling()
                    return
                }
            }
        }
    }

    protected override func GetJson(): String {
        let builder = StringBuilder()
        builder.append("{")
        for (title in titleOrder) {
            builder.append("\n   \"")
            builder.append(title)
            builder.append("\": {")
            if (let Some(infos) <- titleInfoMap.get(title)) {
                for (info in infos) {
                    builder.append("\n      \"")
                    builder.append(info.subtitle)
                    builder.append("\": ")
                    builder.append(formatFloat2(info.end))
                    builder.append(",")
                }
                if (!infos.isEmpty()) {
                    var tmp = builder.toString()
                    tmp = tmp[0..tmp.size - 1]
                    builder.reset()
                    builder.append(tmp)
                }
            }
            builder.append("   \n    },")
        }
        var output = builder.toString()
        if (!titleOrder.isEmpty()) {
            output = output[0..output.size - 1]
        }
        return output + "\n}\n"
    }

    protected override func GetSuffix(): String {
        return ".mem.prof"
    }

    private static func Sampling(): Float64 {
        try {
            let content = String.fromUtf8(File.readFrom("/proc/self/statm"))
            let parts = content.trimAscii().split(" ")
            if (parts.size >= 2) {
                let rssPages = Int64.parse(parts[1])
                return Float64(rssPages) * 4.0 / 1024.0
            }
        } catch (e: Exception) {
            ()
        }
        return 0.0
    }
}

private func formatFloat2(value: Float64): String {
    let scaled = Int64(value * 100.0 + 0.5)
    let whole = scaled / 100
    let frac = scaled % 100
    return whole.toString() + "." + FillZero(frac, DISPLAY_PRECISION)
}
