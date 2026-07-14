package cjcj::ast

import cjcj::utils.Identifiable

public struct Ptr<T> <: Comparable<Ptr<T>> & Equatable<Ptr<T>> & Hashable where T <: Object & Identifiable {
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

    // C++ SafePointer.h:316-319 Ptr::operator< compares pointer identity.
    public operator func <(right: Ptr<T>): Bool {
        return value.objectId < right.value.objectId
    }

    // Comparable adapter for C++ SafePointer.h:316-319 Ptr::operator<.
    public func compare(right: Ptr<T>): Ordering {
        if (this < right) {
            return Ordering.LT
        }
        if (right < this) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    public func hashCode(): Int64 {
        return value.objectId.hashCode()
    }
}
