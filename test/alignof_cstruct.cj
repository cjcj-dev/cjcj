@C
struct RuntimeHeapParamC {
    let regionSize: UIntNative
    let heapSize: UIntNative
    let exemptionThreshold: Float64
    let heapUtilization: Float64
    let heapGrowth: Float64
    let heapSizeSet: Bool
    let softHeapSize: UIntNative
    let softHeapSizeSet: Bool

    init(regionSize: UIntNative, heapSize: UIntNative, exemptionThreshold: Float64, heapUtilization: Float64,
        heapGrowth: Float64, heapSizeSet: Bool, softHeapSize: UIntNative, softHeapSizeSet: Bool) {
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

@C
struct RuntimeGCParamC {
    let gcThreshold: UIntNative
    let garbageThreshold: Float64
    let gcInterval: UInt64
    let backupGCInterval: UInt64
    let concGCThreads: UInt32
    let youngGCThreads: UInt32
    let oldGCThreads: UInt32
    let staticGCThreads: Bool
    let maxTenuringThreshold: UInt32
    let zTenuringThreshold: Int32
    let maxTenuringThresholdSet: Bool
    let zTenuringThresholdSet: Bool

    init(gcThreshold: UIntNative, garbageThreshold: Float64, gcInterval: UInt64, backupGCInterval: UInt64,
        concGCThreads: UInt32, youngGCThreads: UInt32, oldGCThreads: UInt32, staticGCThreads: Bool,
        maxTenuringThreshold: UInt32, zTenuringThreshold: Int32, maxTenuringThresholdSet: Bool,
        zTenuringThresholdSet: Bool) {
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

@C
struct RuntimeLogParamC {
    let logLevel: Int32
    init(logLevel: Int32) { this.logLevel = logLevel }
}

@C
struct RuntimeConcurrencyParamC {
    let thStackSize: UIntNative
    let coStackSize: UIntNative
    let processorNum: UInt32
    init(thStackSize: UIntNative, coStackSize: UIntNative, processorNum: UInt32) {
        this.thStackSize = thStackSize
        this.coStackSize = coStackSize
        this.processorNum = processorNum
    }
}

@C
struct RuntimeConfigParamC {
    let heapParam: RuntimeHeapParamC
    let gcParam: RuntimeGCParamC
    let logParam: RuntimeLogParamC
    let coParam: RuntimeConcurrencyParamC
    init(heapParam: RuntimeHeapParamC, gcParam: RuntimeGCParamC, logParam: RuntimeLogParamC,
        coParam: RuntimeConcurrencyParamC) {
        this.heapParam = heapParam
        this.gcParam = gcParam
        this.logParam = logParam
        this.coParam = coParam
    }
}

func alignment<T>(): UIntNative where T <: CType {
    return alignOf<T>()
}

func check(name: String, actual: UIntNative, expected: UIntNative): Int64 {
    println("CHECK ${name} actual=${actual} expected=${expected}")
    if (actual != expected) { return 1 }
    return 0
}

main(): Int64 {
    var failures: Int64 = 0
    failures += check("Int64.align", alignOf<Int64>(), 8)
    failures += check("Int64.size", sizeOf<Int64>(), 8)
    failures += check("Bool.align", alignOf<Bool>(), 1)
    failures += check("Bool.size", sizeOf<Bool>(), 1)
    failures += check("Int32.align", alignOf<Int32>(), 4)
    failures += check("Int32.size", sizeOf<Int32>(), 4)
    failures += check("Heap.align", alignOf<RuntimeHeapParamC>(), 8)
    failures += check("Heap.size", sizeOf<RuntimeHeapParamC>(), 64)
    failures += check("GC.align", alignOf<RuntimeGCParamC>(), 8)
    failures += check("GC.size", sizeOf<RuntimeGCParamC>(), 64)
    failures += check("Log.align", alignOf<RuntimeLogParamC>(), 4)
    failures += check("Log.size", sizeOf<RuntimeLogParamC>(), 4)
    failures += check("Conc.align", alignOf<RuntimeConcurrencyParamC>(), 8)
    failures += check("Conc.size", sizeOf<RuntimeConcurrencyParamC>(), 24)
    failures += check("Cfg.align", alignOf<RuntimeConfigParamC>(), 8)
    failures += check("Cfg.size", sizeOf<RuntimeConfigParamC>(), 160)
    failures += check("generic.Log.align", alignment<RuntimeLogParamC>(), 4)
    failures += check("generic.Heap.align", alignment<RuntimeHeapParamC>(), 8)
    println("ALIGNOF_FAILURES=${failures}")
    return failures
}
