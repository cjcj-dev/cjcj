package cangjie_compiler::utils

import std.collection.*
import std.time.*

private class UserTimerInfo {
    let title: String
    let subtitle: String
    let desc: String
    var start: DateTime
    var costMs: Int64 = 0
    var isDone: Bool = false

    init(title: String, subtitle: String, desc: String) {
        this.title = title
        this.subtitle = subtitle
        this.desc = desc
        start = DateTime.nowUTC()
    }
}

public class UserTimer <: UserBase {
    private static let singleton = UserTimer()
    private let infoList = ArrayList<UserTimerInfo>()

    private init() {
        super()
    }

    public static func Instance(): UserTimer {
        return singleton
    }

    public func Start(title: String, subtitle: String, desc: String): Unit {
        for (info in infoList) {
            if (info.title == title && info.subtitle == subtitle && info.desc == desc) {
                if (info.isDone) {
                    info.start = DateTime.nowUTC()
                    info.isDone = false
                }
                return
            }
        }
        infoList.add(UserTimerInfo(title, subtitle, desc))
    }

    public func Stop(title: String, subtitle: String, desc: String): Unit {
        for (info in infoList) {
            if (info.title == title && info.subtitle == subtitle && info.desc == desc) {
                CJC_ASSERT(!info.isDone)
                let duration = DateTime.nowUTC() - info.start
                info.costMs += duration.toMilliseconds()
                info.isDone = true
                return
            }
        }
        CJC_ABORT_WITH_MSG("profile timer stopped before start")
    }

    protected override func GetJson(): String {
        let result = HashMap<String, ArrayList<(String, Int64)>>()
        let order = ArrayList<String>()
        for (info in infoList) {
            if (!info.isDone) {
                printUnfinishedTimer(info.title)
                continue
            }
            let currentEntries = result.get(info.title)
            let entries = if (let Some(existing) <- currentEntries) {
                existing
            } else {
                let created = ArrayList<(String, Int64)>()
                result.add(info.title, created)
                order.add(info.title)
                created
            }
            entries.add((info.subtitle, info.costMs))
        }
        let builder = StringBuilder()
        builder.append("{")
        for (title in order) {
            builder.append("\n   \"")
            builder.append(title)
            builder.append("\": {")
            if (let Some(entries) <- result.get(title)) {
                for ((subtitle, costMs) in entries) {
                    builder.append("\n      \"")
                    builder.append(subtitle)
                    builder.append("\": ")
                    builder.append(costMs.toString())
                    builder.append(",")
                }
                if (!entries.isEmpty()) {
                    var tmp = builder.toString()
                    tmp = tmp[0..tmp.size - 1]
                    builder.reset()
                    builder.append(tmp)
                }
            }
            builder.append("   \n    },")
        }
        var output = builder.toString()
        if (!order.isEmpty()) {
            output = output[0..output.size - 1]
        }
        return output + "\n}\n"
    }

    protected override func GetSuffix(): String {
        return ".time.prof"
    }
}

@When[os == "Windows"]
private func printUnfinishedTimer(title: String): Unit {
    println("[ ${title} ] only has beginning time, does not have ending time")
}

@When[os != "Windows"]
private func printUnfinishedTimer(title: String): Unit {
    println("[ \u{001b}[31;1m${title}\u{001b}[0m ] only has beginning time, does not have ending time")
}
