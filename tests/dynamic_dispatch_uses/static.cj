package dispatch_uses_static

public interface Measured {
    static prop size: Int64
}

public func readSize<T>(): Int64 where T <: Measured {
    T.size
}
