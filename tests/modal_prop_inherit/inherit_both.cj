package modalpropinherit

public interface Seek {
    func seek(n: Int64): Int64
    func seek(this @local!, n: Int64): Int64 {
        throw Exception()
    }
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

public class Buffer <: Seek {
    var size: Int64 = 42
    public func seek(n: Int64): Int64 {
        size + n
    }
}

main(): Int64 {
    let b = Buffer()
    if (b.length == 42) { 0 } else { 1 }
}
