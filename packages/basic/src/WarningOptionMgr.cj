package cangjie_compiler::basic

import std.collection.*

foreign {
    func abort(): Unit
}

public class WarningOptionMgr {
    private static let ins: WarningOptionMgr = WarningOptionMgr()
    private let suppressedFlags: ArrayList<Bool> = WarningOptionMgr.initFlags()

    private init() {}

    private static func initFlags(): ArrayList<Bool> {
        let flags = ArrayList<Bool>()
        for (_ in 0..WarnGroupIndex(WarnGroup.NONE)) {
            flags.add(false)
        }
        return flags
    }

    public static func UpdateFlags(newFlags: Array<Bool>): Unit {
        let flags = GetInstance().suppressedFlags
        flags.clear()
        for (flag in newFlags) {
            flags.add(flag)
        }
    }

    public static func UpdateFlag(index: UInt64, newVal: Bool): Unit {
        let flags = GetInstance().suppressedFlags
        if (index >= UInt64(flags.size)) {
            unsafe { abort() }
        }
        flags[Int64(index)] = newVal
    }

    public func IsSuppressed(index: UInt64): Bool {
        if (index >= UInt64(suppressedFlags.size)) {
            unsafe { abort() }
        }
        return suppressedFlags[Int64(index)]
    }

    public static func GetInstance(): WarningOptionMgr {
        return ins
    }
}
