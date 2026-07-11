package cjcj::ast

import cjcj::utils.Identifiable

public struct Ptr<T> <: Equatable<Ptr<T>> & Hashable where T <: Object & Identifiable {
    public let value: T

    public init(v: T) {
        value = v
    }

    public operator func ==(right: Ptr<T>): Bool {
        return refEq(value, right.value)
    }

    public operator func !=(right: Ptr<T>): Bool {
        return !refEq(value, right.value)
    }

    public func hashCode(): Int64 {
        return value.objectId.hashCode()
    }
}
