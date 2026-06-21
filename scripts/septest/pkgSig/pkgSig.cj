package pkgSig

import std.collection.*

public class FailureReason {
    public var value: String = ""

    public init() {}
}

public func fill(path: String, buffer: ArrayList<UInt8>, failedReason: FailureReason): Bool {
    buffer.add(7u8)
    failedReason.value = path
    return true
}
