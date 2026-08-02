package hfixh2_345

public func alignment<T>(): UIntNative where T <: CType {
    return alignOf<T>()
}

public func concreteAlignment(): UIntNative {
    return alignment<Int64>()
}
