package rawarray_debug

public func genericSize<T>(values: Array<T>): Int64 {
    return values.size
}

public func concreteSize(values: Array<Int64>): Int64 {
    return values.size
}
