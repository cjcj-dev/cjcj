// Erased receiver boxing: the payload size and reference layout are available
// only through the receiver TypeInfo in Range<T>.provide$withoutTI.
public interface Provider<T> {
    func provide(): Provider<T>
}

public struct Range<T> <: Provider<T> {
    var value: T

    public init(value: T) {
        this.value = value
    }

    public func provide(): Provider<T> {
        this
    }
}

main() {
    let provider: Provider<Int64> = Range<Int64>(1)
    let _ = provider.provide()
}
