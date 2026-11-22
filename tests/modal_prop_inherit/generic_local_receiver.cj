package modalpropgeneric

public interface Source {
    func next(): Int64
}

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
            7
        }
    }
}

public class Buffer <: Source & Seek {
    var size: Int64 = 42
    public func next(): Int64 {
        1
    }
    public func seek(n: Int64): Int64 {
        size + n
    }
}

// Same shape as std.io readToEnd: the @local! receiver must select `length @local!`.
func localLength<T>(from: T @local!): Int64 where T <: Source & Seek {
    let sum = from.length
    sum
}

func plainLength<T>(from: T): Int64 where T <: Source & Seek {
    from.length
}

main(): Int64 {
    let b = Buffer()
    if (localLength(b) == 7 && plainLength(b) == 42) { 0 } else { 1 }
}
