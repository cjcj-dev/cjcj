package trivial_statics_multiple

interface I<T> {
    static func f1(value: T): Int64
}
open class C <: I<Int64> & I<String> {
    public static func f1(value: String): Int64 { return f1(35) }
    public static func f1(value: Int64): Int64 { return value + 7 }
    public func fromInstance(): Int64 { return f1(35) }
}
public func callString(): Int64 { return C.f1("test") }
public func callInt(): Int64 { return C.f1(35) }
func dispatch<T, U>(value: U): Int64 where T <: I<U> {
    return T.f1(value)
}
public func entry(): Int64 {
    return C.f1("test") - 42
}
