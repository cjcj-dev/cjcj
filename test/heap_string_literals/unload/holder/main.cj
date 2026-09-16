package literal_retainer
import std.runtime.gc
foreign { func observeRetainedLiteral(data: CPointer<UInt8>, size: Int64): Unit }
class Holder {
    var text: String
    init(text: String) { this.text = text }
}
let holder = Holder("")
public func retainLiteral(value: String): Unit { holder.text = value }
@C
public func readRetainedLiteral(arg: CPointer<Unit>): CPointer<Unit> {
    unsafe {
        let handle = acquireArrayRawData(holder.text.rawData())
        observeRetainedLiteral(handle.pointer, holder.text.size)
        releaseArrayRawData(handle)
    }
    return arg
}
@C
public func collectRetainedLiteral(arg: CPointer<Unit>): CPointer<Unit> {
    gc(heavy: true)
    return arg
}
