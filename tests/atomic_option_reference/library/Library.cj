package aor_regression

import std.sync.*

public class Cell {
    public let value: Int64
    public init(value: Int64) { this.value = value }
}

// Keep generic Option parameters in a separately compiled package. In
// particular, do not replace None<T> with a concrete Option<Object> here.
public class GenericSlot<T> where T <: Object {
    private let slot: AtomicOptionReference<T>
    public init(initial: Option<T>) { slot = AtomicOptionReference<T>(initial) }
    public func read(): Option<T> { slot.load() }
    public func put(value: Option<T>): Unit { slot.store(value) }
    public func exchange(value: Option<T>): Option<T> { slot.swap(value) }
    public func replace(old: Option<T>, value: Option<T>): Bool { slot.compareAndSwap(old, value) }
}

public func checkNone(): Bool {
    let slot = GenericSlot<Cell>(None)
    if (!slot.read().isNone()) { return false }
    println("AOR_ASSERT ctor_none")
    slot.put(None)
    if (!slot.read().isNone()) { return false }
    println("AOR_ASSERT store_none")
    if (!slot.exchange(None).isNone() || !slot.read().isNone()) { return false }
    println("AOR_ASSERT swap_none")
    return true
}

public func checkSome(): Bool {
    let a = Cell(17)
    let b = Cell(29)
    let slot = GenericSlot<Cell>(Some(a))
    if (slot.read().getOrThrow().value != 17) { return false }
    println("AOR_ASSERT ctor_some")
    slot.put(Some(b))
    if (slot.read().getOrThrow().value != 29) { return false }
    println("AOR_ASSERT store_some")
    if (slot.exchange(Some(a)).getOrThrow().value != 29 || slot.read().getOrThrow().value != 17) { return false }
    println("AOR_ASSERT swap_some")
    if (slot.exchange(None).getOrThrow().value != 17 || !slot.read().isNone()) { return false }
    println("AOR_ASSERT some_to_none")
    return true
}

public func checkControls(): Bool {
    let a = Cell(31)
    let b = Cell(43)
    let slot = GenericSlot<Cell>(Some(a))
    if (slot.replace(Some(b), None) || !slot.replace(Some(a), Some(b))) { return false }
    if (slot.read().getOrThrow().value != 43 || !slot.replace(Some(b), None) || !slot.read().isNone()) { return false }
    println("AOR_ASSERT cas")
    let ref = AtomicReference<Cell>(a)
    ref.store(b)
    if (ref.swap(a).value != 43 || ref.load().value != 31) { return false }
    println("AOR_ASSERT class")
    let integer = AtomicInt64(7)
    integer.store(11)
    if (integer.swap(13) != 11 || !integer.compareAndSwap(13, 19) || integer.load() != 19) { return false }
    println("AOR_ASSERT primitive")
    return true
}
