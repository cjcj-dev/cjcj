package cjcj::utils

import std.sync.AtomicBool

private let processingSignalOrException = AtomicBool(false)

public func writeICEMessage(errorCode: Int64): Unit {
    ICE.PrintVersionFromError()
    eprintln(ICE.MSG_PART_ONE + SIGNAL_MSG_PART_ONE + errorCode.toString() + SIGNAL_MSG_PART_TWO +
        ICE.MSG_PART_TWO + ICE.GetTriggerPoint().toString())
}

public func threadDelaySynchronizer(): Unit {
    if (processingSignalOrException.swap(true)) {
        var count: Int64 = 100000
        while (count > 0) {
            count--
        }
    }
}
