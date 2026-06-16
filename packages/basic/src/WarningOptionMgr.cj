package cangjie_compiler::basic

import std.collection.*

public class WarningOptionMgr {
    private static let suppressedFlags: ArrayList<Bool> = initFlags()

    private static func initFlags(): ArrayList<Bool> {
        let flags = ArrayList<Bool>()
        for (_ in 0..WarnGroupIndex(WarnGroup.NONE)) {
            flags.add(false)
        }
        return flags
    }

    public static func UpdateFlags(newVal: Bool): Unit {
        var idx: Int64 = 0
        while (idx < suppressedFlags.size) {
            suppressedFlags[idx] = newVal
            idx++
        }
    }

    public static func UpdateFlags(newFlags: Array<Bool>): Unit {
        suppressedFlags.clear()
        for (flag in newFlags) {
            suppressedFlags.add(flag)
        }
    }

    private static func RequireValidIndex(index: UInt64): Int64 {
        let idx = Int64(index)
        if (idx < 0 || idx >= suppressedFlags.size) {
            throw IllegalStateException("warning option index out of range")
        }
        return idx
    }

    public static func UpdateFlag(index: UInt64, newVal: Bool): Unit {
        suppressedFlags[RequireValidIndex(index)] = newVal
    }

    public static func IsSuppressed(index: UInt64): Bool {
        return suppressedFlags[RequireValidIndex(index)]
    }
}
