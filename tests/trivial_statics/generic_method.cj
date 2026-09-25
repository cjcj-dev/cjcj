package trivial_statics_generic
interface Identity {
    static func identity<T>(value: T): T
}
class C <: Identity {
    public static func identity<T>(value: T): T { return value }
}
func dispatch<T>(): Int64 where T <: Identity {
    return T.identity<Int64>(42)
}
public func entry(): Int64 { return dispatch<C>() - 42 }
