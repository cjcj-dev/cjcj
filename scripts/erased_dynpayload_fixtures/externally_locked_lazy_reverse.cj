// A minimal generic mutating receiver that makes ReplaceFunction step 5 copy
// the managed, TypeInfo-bearing payload back into its without-TI receiver.
public struct ExternallyLockedLazy<T> {
    var value: T

    public init(value: T) {
        this.value = value
    }

    public mut func compute(value: T): Unit {
        this.value = value
    }
}

public func callCompute<T>(lazy: ExternallyLockedLazy<T>, value: T): Unit {
    var local = lazy
    local.compute(value)
}

main() {
    let lazy = ExternallyLockedLazy<Int64>(1)
    callCompute<Int64>(lazy, 2)
}
