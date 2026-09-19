package cjcj::ast

import cjcj::utils.Identifiable

public struct Ptr<T> <: Comparable<Ptr<T>> & Equatable<Ptr<T>> & Hashable where T <: Object & Identifiable {
    public let value: T
    // C++ SafePointer.h:317-319 compares stored T* bits; cache identity so TreeSet
    // compare does not virtual-dispatch objectId (GetMTable) on the hot path.
    private let id: Int64

    public init(v: T) {
        value = v
        id = v.objectId
    }

    public operator func ==(right: Ptr<T>): Bool {
        return refEq(value, right.value)
    }

    public operator func !=(right: Ptr<T>): Bool {
        return !refEq(value, right.value)
    }

    public operator func <(right: Ptr<T>): Bool {
        return id < right.id
    }

    public func compare(right: Ptr<T>): Ordering {
        if (id < right.id) {
            return Ordering.LT
        }
        if (right.id < id) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    public func hashCode(): Int64 {
        return id.hashCode()
    }
}
