package modalpropextend

public interface Seek {
    func seek(n: Int64): Int64
    prop length: Int64 {
        get() {
            seek(0)
        }
    }
    prop length: Int64 @local! {
        get() {
            exclave {seek(0)}
        }
    }
}

public class Inner <: Seek {
    public func seek(n: Int64): Int64 {
        7 + n
    }
}

public class Wrapper<T> where T <: Seek {
    let inner: T
    public init(inner: T) {
        this.inner = inner
    }
}

extend<T> Wrapper<T> <: Seek where T <: Seek {
    public func seek(n: Int64): Int64 {
        inner.seek(n)
    }
    public prop length: Int64 {
        get() {
            inner.seek(0) * 6
        }
    }
}

main(): Int64 {
    let w = Wrapper<Inner>(Inner())
    if (w.length == 42) { 0 } else { 1 }
}
