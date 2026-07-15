package cjcj::utils

import std.collection.*
import std.env.atExit

public class UserCodeInfo <: UserBase {
    private static let singleton = UserCodeInfo()
    private let codeInfo = ArrayList<(String, Int64)>()

    private init() {
        super()
        atExit({ => OutputResult() })
    }

    public static func Instance(): UserCodeInfo {
        return singleton
    }

    public func RecordInfo(item: String, value: Int64): Unit {
        codeInfo.add((item, value))
    }

    protected override func GetJson(): String {
        let builder = StringBuilder()
        builder.append("{")
        for ((item, value) in codeInfo) {
            builder.append("\n   \"")
            builder.append(item)
            builder.append("\": ")
            builder.append(value.toString())
            builder.append(",")
        }
        var output = builder.toString()
        if (!codeInfo.isEmpty()) {
            output = output[0..output.size - 1]
        }
        return output + "\n}\n"
    }

    protected override func GetSuffix(): String {
        return ".info.prof"
    }
}
