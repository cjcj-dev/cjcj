package cjcj::macro_pkg

public enum RTLogLevel {
    | RTLOG_VERBOSE
    | RTLOG_DEBUG
    | RTLOG_INFO
    | RTLOG_REPORT
    | RTLOG_WARNING
    | RTLOG_ERROR
    | RTLOG_FAIL
    | RTLOG_FATAL
    | RTLOG_OFF
}

public class HeapParam {
    public var regionSize: UIntNative
    public var heapSize: UIntNative
    public var exemptionThreshold: Float64
    public var heapUtilization: Float64
    public var heapGrowth: Float64
    public var heapSizeSet: Bool
    // API sizes are KB; the set bit distinguishes explicit zero from default.
    public var softHeapSize: UIntNative
    public var softHeapSizeSet: Bool

    public init(regionSize: UIntNative, heapSize: UIntNative, exemptionThreshold: Float64,
        heapUtilization: Float64, heapGrowth: Float64, heapSizeSet!: Bool = false,
        softHeapSize!: UIntNative = 0, softHeapSizeSet!: Bool = false) {
        this.regionSize = regionSize
        this.heapSize = heapSize
        this.exemptionThreshold = exemptionThreshold
        this.heapUtilization = heapUtilization
        this.heapGrowth = heapGrowth
        this.heapSizeSet = heapSizeSet
        this.softHeapSize = softHeapSize
        this.softHeapSizeSet = softHeapSizeSet
    }
}

public class GCParam {
    public var gcThreshold: UIntNative
    public var garbageThreshold: Float64
    public var gcInterval: UInt64
    public var backupGCInterval: UInt64
    public var concGCThreads: UInt32
    public var youngGCThreads: UInt32
    public var oldGCThreads: UInt32
    public var staticGCThreads: Bool
    public var maxTenuringThreshold: UInt32
    public var zTenuringThreshold: Int32
    public var maxTenuringThresholdSet: Bool
    public var zTenuringThresholdSet: Bool

    public init(gcThreshold: UIntNative, garbageThreshold: Float64, gcInterval: UInt64,
        backupGCInterval: UInt64, concGCThreads: UInt32, youngGCThreads: UInt32, oldGCThreads: UInt32,
        staticGCThreads: Bool, maxTenuringThreshold: UInt32, zTenuringThreshold: Int32,
        maxTenuringThresholdSet: Bool, zTenuringThresholdSet: Bool) {
        this.gcThreshold = gcThreshold
        this.garbageThreshold = garbageThreshold
        this.gcInterval = gcInterval
        this.backupGCInterval = backupGCInterval
        this.concGCThreads = concGCThreads
        this.youngGCThreads = youngGCThreads
        this.oldGCThreads = oldGCThreads
        this.staticGCThreads = staticGCThreads
        this.maxTenuringThreshold = maxTenuringThreshold
        this.zTenuringThreshold = zTenuringThreshold
        this.maxTenuringThresholdSet = maxTenuringThresholdSet
        this.zTenuringThresholdSet = zTenuringThresholdSet
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
    public var coParam: ConcurrencyParam

    public init(heapParam: HeapParam, gcParam: GCParam, logParam: LogParam, coParam: ConcurrencyParam) {
        this.heapParam = heapParam
        this.gcParam = gcParam
        this.logParam = logParam
        this.coParam = coParam
    }
}

public let G_COROUTINE_NAME_SIZE: Int64 = 32

public class CoroutineAttr {
    public var name: String = ""
    public var stackSize: UIntNative = 0

    public init() {}
}
