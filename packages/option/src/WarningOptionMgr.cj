package cangjie_compiler::option

import cangjie_compiler::basic.WarningOptionMgr as BasicWarningOptionMgr

public class WarningOptionMgr {
    public static func UpdateFlags(newVal: Bool): Unit {
        BasicWarningOptionMgr.UpdateFlags(newVal)
    }

    public static func UpdateFlag(index: UInt64, newVal: Bool): Unit {
        BasicWarningOptionMgr.UpdateFlag(index, newVal)
    }

    public static func IsSuppressed(index: UInt64): Bool {
        return BasicWarningOptionMgr.IsSuppressed(index)
    }
}
