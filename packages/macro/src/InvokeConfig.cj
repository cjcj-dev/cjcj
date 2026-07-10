package cjcj::macro_pkg

public enum RTLogLevel {
    | RTLOG_VERBOSE
    | RTLOG_DEBUGY
    | RTLOG_INFO
    | RTLOG_WARNING
    | RTLOG_ERROR
    | RTLOG_FATAL_WITHOUT_ABORT
    | RTLOG_FATAL
    | RTLOG_OFF
}

public class HeapParam {
    public var regionSize: UIntNative
    public var heapSize: UIntNative
    public var exemptionThreshold: Float64
    public var heapUtilization: Float64
    public var heapGrowth: Float64
    public var allocationRate: Float64
    public var allocationWaitTime: UIntNative

    public init(regionSize: UIntNative, heapSize: UIntNative, exemptionThreshold: Float64,
        heapUtilization: Float64, heapGrowth: Float64, allocationRate: Float64, allocationWaitTime: UIntNative) {
        this.regionSize = regionSize
        this.heapSize = heapSize
        this.exemptionThreshold = exemptionThreshold
        this.heapUtilization = heapUtilization
        this.heapGrowth = heapGrowth
        this.allocationRate = allocationRate
        this.allocationWaitTime = allocationWaitTime
    }
}

public class GCParam {
    public var gcThreshold: UIntNative
    public var garbageThreshold: Float64
    public var gcInterval: UInt64
    public var backupGCInterval: UInt64
    public var gcThreads: Int32

    public init(gcThreshold: UIntNative, garbageThreshold: Float64, gcInterval: UInt64,
        backupGCInterval: UInt64, gcThreads: Int32) {
        this.gcThreshold = gcThreshold
        this.garbageThreshold = garbageThreshold
        this.gcInterval = gcInterval
        this.backupGCInterval = backupGCInterval
        this.gcThreads = gcThreads
    }
}

public class LogParam {
    public var logLevel: RTLogLevel

    public init(logLevel: RTLogLevel) {
        this.logLevel = logLevel
    }
}

public class ConcurrencyParam {
    public var thStackSize: UIntNative
    public var coStackSize: UIntNative
    public var processorNum: UInt32

    public init(thStackSize: UIntNative, coStackSize: UIntNative, processorNum: UInt32) {
        this.thStackSize = thStackSize
        this.coStackSize = coStackSize
        this.processorNum = processorNum
    }
}

public class ConfigParam {
    public var heapParam: HeapParam
    public var gcParam: GCParam
    public var logParam: LogParam
    public var coroutineParam: ConcurrencyParam

    public init(heapParam: HeapParam, gcParam: GCParam, logParam: LogParam, coroutineParam: ConcurrencyParam) {
        this.heapParam = heapParam
        this.gcParam = gcParam
        this.logParam = logParam
        this.coroutineParam = coroutineParam
    }
}

public let G_COROUTINE_NAME_SIZE: Int64 = 32

public class CoroutineAttr {
    public var name: String = ""
    public var stackSize: UIntNative = 0

    public init() {}
}
