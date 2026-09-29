// Compile alongside the pinned std.core sources: RawArray is a core-only builtin.
package std.core

public struct LayoutCell<T> {
    public var value: T
    public init(value: T) { this.value = value }
}
public func layoutRawGet<T>(array: RawArray<T>, index: Int64): T {
    return arrayGet(array, index)
}
public func layoutRawSet<T>(array: RawArray<T>, index: Int64, value: T): Unit {
    arraySet(array, index, value)
}
public func layoutRawRef<T>(array: RawArray<LayoutCell<T>>, index: Int64): T {
    return arrayGetUnchecked(array, index).value
}
public func layoutRawStaticGet(array: RawArray<Int64>, index: Int64): Int64 {
    return arrayGet(array, index)
}
public func layoutRawStaticSet(array: RawArray<Int64>, index: Int64, value: Int64): Unit {
    arraySet(array, index, value)
}
