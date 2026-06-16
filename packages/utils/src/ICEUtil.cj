package cangjie_compiler::utils

import cangjie_compiler::basic.ANSI_COLOR_RED
import cangjie_compiler::basic.ANSI_COLOR_RESET
import cangjie_compiler::basic.CANGJIE_COMPILER_VERSION
import std.sync.AtomicBool

public enum CompileStage {
    | FRONTEND
    | COMPILE_STAGE_NUMBER
}

public class ICE {
    public static let EXIT_CODE: Int64 = 2
    public static let MSG_PART_ONE: String = ANSI_COLOR_RED + "Internal Compiler Error: " + ANSI_COLOR_RESET
    public static let MSG_PART_TWO: String = "\nPlease report this to Cangjie team and include the project. Error Code: "
    public static let FRONTEND_TP: Int64 = -1
    public static let UNITTEST_TP: Int64 = -2
    public static let LSP_TP: Int64 = -3
    private static let writeOnceICEMessage = AtomicBool(false)
    private static var removeTempFileHook: Option<() -> Unit> = None
    private static var removeTempFileSignalSafeHook: Option<() -> Unit> = None

    public static func PrintVersionFromError(): Unit {
        eprintln(CANGJIE_COMPILER_VERSION)
    }

    public static func RegisterRemoveTempFileHook(hook: () -> Unit): Unit {
        removeTempFileHook = hook
    }

    public static func RegisterRemoveTempFileSignalSafeHook(hook: () -> Unit): Unit {
        removeTempFileSignalSafeHook = hook
    }

    public static func ClearRemoveTempFileHooks(): Unit {
        removeTempFileHook = None
        removeTempFileSignalSafeHook = None
    }

    public static func RemoveTempFile(): Unit {
        if (let Some(hook) <- removeTempFileHook) {
            hook()
        }
    }

    public static func RemoveTempFileSignalSafe(): Unit {
        if (let Some(hook) <- removeTempFileSignalSafeHook) {
            hook()
        } else {
            RemoveTempFile()
        }
    }

    public static func GetTriggerPoint(): Int64 {
        return TriggerPointSetter.triggerPoint
    }

    public static func CanWriteOnceICEMessage(): Bool {
        return !writeOnceICEMessage.swap(true)
    }
}

public class TriggerPointSetter <: Resource {
    public static var interpreterTP: Int64 = 2
    public static var writeCahedTP: Int64 = 3
    public static var triggerPoint: Int64 = 1
    private var closed: Bool = false

    public init(stage: CompileStage) {
        SetICETriggerPoint(stage)
    }

    public init(tp: Int64) {
        SetICETriggerPoint(tp: tp)
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        SetICETriggerPoint()
        closed = true
    }

    public static func SetICETriggerPoint(stage: CompileStage): Unit {
        if (triggerPoint == ICE.LSP_TP) {
            return
        }
        triggerPoint = match (stage) {
            case CompileStage.FRONTEND => 0
            case CompileStage.COMPILE_STAGE_NUMBER => 1
        }
    }

    public static func SetICETriggerPoint(tp!: Int64 = ICE.FRONTEND_TP): Unit {
        if (tp == ICE.LSP_TP) {
            triggerPoint = tp
        } else if (tp == ICE.FRONTEND_TP) {
            triggerPoint = 1
        } else {
            triggerPoint = tp
        }
    }
}

public func InternalError(message: String): Unit {
    if (ICE.CanWriteOnceICEMessage()) {
        ICE.PrintVersionFromError()
        eprintln(ICE.MSG_PART_ONE + message + ICE.MSG_PART_TWO + ICE.GetTriggerPoint().toString())
        let triggerPoint = ICE.GetTriggerPoint()
        if (triggerPoint == ICE.LSP_TP || triggerPoint == ICE.UNITTEST_TP) {
            return
        }
        ICE.RemoveTempFile()
        throw IllegalStateException(message)
    }
}

public func InternalError(pred: Bool, message: String): Unit {
    if (!pred) {
        InternalError(message)
    }
}
