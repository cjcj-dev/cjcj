package objc.lang
import objc.internal.*
@ObjCMirror["NSObject"]
public interface ObjCId {}
public struct ObjCPointer<T> {
    public let pointer: CPointer<Unit>
    public init(value: T) { pointer = CPointer<Unit>() }
    public init() { pointer = CPointer<Unit>() }
}
public struct ObjCFunc<T> {
    public init(value: T) {}
    public init() {}
}
public class ObjCBlock<T> {
    public init(abi: CPointer<CangjieBlockABI>) {}
    public init(value: T) {}
    public init() {}
}
