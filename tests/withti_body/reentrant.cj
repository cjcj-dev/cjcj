package withti_reentrant

// This generic caller precedes the receiver method and resolves it from a
// TryApply. With --apc=1 both declarations belong to the same LLVM module.
public func enter<T>(value: Deferred<T>, hook: () -> Unit): Int64 {
    try {
        return value.late(hook)
    } catch (e: IllegalStateException) {
        return 29
    }
}

public struct Deferred<T> {
    public let value: T
    public init(value: T) { this.value = value }
    public func late(hook: () -> Unit): Int64 {
        hook()
        return 17
    }
}
