import literal_import.*
import std.runtime.gc

foreign {
    func checkLiteralBytes(ptr: CPointer<UInt8>, size: Int64, id: Int32): Int32
    func checkLiteralShare(first: UIntNative, second: UIntNative, delta: Int64): Int32
    func checkOrdinaryAggregate(first: Int64, second: Int64): Int32
    func literalAssertionsDone(): Int32
}

let globalLiteral = "abc-世界"
const constantLiteral = "abc-世界"

class LiteralHolder {
    var text: String
    init(text: String) { this.text = text }
}

let initializedHolder = LiteralHolder("abc-世界")

public struct PlainValue {
    public let first: Int64
    public let second: Int64
    public init(first: Int64, second: Int64) {
        this.first = first
        this.second = second
    }
}

public func copyPlain(value: PlainValue): PlainValue { return value }


func observe(value: String, id: Int32): Unit {
    unsafe {
        let handle = acquireArrayRawData(value.rawData())
        let _ = checkLiteralBytes(handle.pointer, value.size, id)
        releaseArrayRawData(handle)
    }
}

func share(left: String, right: String, delta: Int64): Unit {
    unsafe {
        let first = acquireArrayRawData(left.rawData())
        let second = acquireArrayRawData(right.rawData())
        let _ = checkLiteralShare(first.pointer.toUIntNative(), second.pointer.toUIntNative(), delta)
        releaseArrayRawData(second)
        releaseArrayRawData(first)
    }
}

main(): Int64 {
    let holder = LiteralHolder("abc-世界")
    observe(holder.text, 0)
    observe("abc-世界", 0)
    observe("世界", 1)
    share(holder.text, "abc-世界", 0)
    observe("世界abc", 5)
    observe("abc", 4)
    share("世界abc", "abc", 6)
    let _ = observe(globalLiteral, 0)
    let _ = observe(initializedHolder.text, 0)
    let _ = observe(constantLiteral, 0)
    let _ = observe("A\u{0}B", 2)
    let _ = observe(importedLiteral(), 3)
    let _ = observe(importedGlobal, 3)
    let ordinary: Array<UInt8> = [0x61, 0x62, 0x63]
    unsafe {
        let handle = acquireArrayRawData(ordinary)
        let _ = checkLiteralBytes(handle.pointer, ordinary.size, 4)
        releaseArrayRawData(handle)
    }
    let plain = copyPlain(PlainValue(7, 9))
    unsafe { let _ = checkOrdinaryAggregate(plain.first, plain.second) }
    if ("".size != 0 || String.empty.size != 0 || String().size != 0) { return 80 }
    let emptyLiteralHolder = LiteralHolder("")
    let emptyValueHolder = LiteralHolder(String.empty)
    gc(heavy: true)
    if (emptyLiteralHolder.text.size != 0 || emptyValueHolder.text.size != 0) { return 81 }
    let _ = observe(holder.text, 0)
    let _ = observe(globalLiteral, 0)
    let _ = observe(importedLiteral(), 3)
    return Int64(unsafe { literalAssertionsDone() })
}
