package ref_struct_owner

public class Anchor {
    public let value: Int64
    public init(value: Int64) { this.value = value }
}
public struct Slot {
    public var value: Anchor
    public init(value: Anchor) { this.value = value }
    public mut func put(value: Anchor): Unit {
        if (value.value < 0) { throw Exception("negative") }
        this.value = value
    }
    public mut func relay(value: Anchor): Unit { put(value) }
}
public class Holder {
    public var slot: Slot = Slot(Anchor(1))
}
var globalSlot = Slot(Anchor(2))

public func heapSite(holder: Holder, value: Anchor): Int64 {
    holder.slot.put(value)
    return holder.slot.value.value
}
public func globalSite(value: Anchor): Int64 {
    globalSlot.put(value)
    return globalSlot.value.value
}
public func localSite(value: Anchor): Int64 {
    var localSlot = Slot(Anchor(3))
    localSlot.put(value)
    return localSlot.value.value
}
public func forwardSite(holder: Holder, value: Anchor): Int64 {
    holder.slot.relay(value)
    return holder.slot.value.value
}
public func trySite(holder: Holder, value: Anchor): Int64 {
    try { holder.slot.put(value) } catch (_: Exception) { return -1 }
    return holder.slot.value.value
}
public func genericCopy<T>(value: T): T { value }
public func tupleControl(value: Anchor): Int64 {
    let pair = genericCopy<(Anchor, Int64)>((value, 9))
    return pair[0].value + pair[1]
}
public func primitiveControl(value: Int64): Int64 { value + 1 }
