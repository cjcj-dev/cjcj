package mangle_locals
import std.collection

public func named(x: Int64, value!: Int64 = 7): Int64 { x + value }
public func reuse(x: Int64): Int64 {
    var total = 0
    if (x > 0) {
        let value = x
        func local(): Int64 { value }
        total += local()
    } else {
        let value = -x
        func local(): Int64 { value }
        total += local()
    }
    let (_, _) = (x, x + 1)
    let (_, _) = (x + 2, x + 3)
    named(total)
}
let (_, _) = (1, 2)
let (_, _) = (3, 4)
public func primitive(a: Int8, b: Int16, c: Int32, d: Int64, e: UInt8, f: UInt16,
    g: UInt32, h: UInt64, i: Float16, j: Float32, k: Float64, l: Rune, m: Bool): Unit {}
public func pointer(value: CPointer<Int64>): CPointer<Int64> { value }
public func cstring(value: CString): CString { value }
public func paren(value: (Int64)): Int64 { value }
public func option(value: ?Int64): Int64 { value ?? 0 }

public func qualified(value: collection.ArrayList<Int64>): Int64 { value.size }
public func constrained<T>(value: T): T where T <: ToString { value }
public class Link<T> {
    public let next: Option<Link<T>>
    public init(next: Option<Link<T>>) { this.next = next }
}
public func recurse(value: Link<Int64>): Option<Link<Int64>> { value.next }
