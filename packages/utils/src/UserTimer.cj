package cjcj::utils

import std.collection.*
import std.time.*

@When[os == "macOS" || os == "Windows" || env == "ohos"]
private type system_clock = DateTime

@When[os != "macOS" && os != "Windows" && env != "ohos"]
private type system_clock = MonoTime

private type ResultDataType = HashMap<String, ArrayList<(String, Int64)>>

@When[os == "macOS" || os == "Windows" || env == "ohos"]
private func now(): system_clock {
    return DateTime.nowUTC()
}

@When[os != "macOS" && os != "Windows" && env != "ohos"]
private func now(): system_clock {
    return MonoTime.now()
}

private class Info {
    let title: String
    let subtitle: String
    let desc: String
    var start: system_clock
    var costMs: Int64 = 0
    var isDone: Bool = false

    init(title: String, subtitle: String, desc: String) {
        this.title = title
        this.subtitle = subtitle
        this.desc = desc
        start = now()
    }
}

public class UserTimer <: UserBase {
    private static let singleton = UserTimer()
    private let infoList = ArrayList<Info>()

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
                    info.start = now()
                    info.isDone = false
                }
                return
            }
        }
        infoList.add(Info(title, subtitle, desc))
    }

    public func Stop(title: String, subtitle: String, desc: String): Unit {
        for (info in infoList) {
            if (info.title == title && info.subtitle == subtitle && info.desc == desc) {
                CJC_ASSERT(!info.isDone)
                let end = now()
                let duration = end - info.start
                info.costMs += duration.toMilliseconds()
                info.isDone = true
                return
            }
        }
        CJC_ASSERT(false)
    }

    protected override func GetJson(): String {
        let (result, _) = GetDataAndOrder()
        let builder = StringBuilder()
        builder.append("{")
        for ((title, entries) in result) {
            builder.append("\n   \"")
            builder.append(title)
            builder.append("\": {")
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
            builder.append("   \n    },")
        }
        var output = builder.toString()
        if (!result.isEmpty()) {
            output = output[0..output.size - 1]
        }
        return output + "\n}\n"
    }

    private func GetDataAndOrder(): (ResultDataType, ArrayList<String>) {
        let result = ResultDataType()
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
        return (result, order)
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
