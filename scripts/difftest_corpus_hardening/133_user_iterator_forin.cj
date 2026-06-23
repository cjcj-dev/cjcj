class RangeIter <: Iterator<Int64> {
    var cur: Int64
    let stop: Int64

    public init(start: Int64, stop: Int64) {
        this.cur = start
        this.stop = stop
    }

    public func next(): Option<Int64> {
        if (cur >= stop) {
            return None
        }
        let v = cur
        cur += 1
        return Some(v)
    }
}

class Counter <: Iterable<Int64> {
    let n: Int64

    public init(n: Int64) {
        this.n = n
    }

    public func iterator(): Iterator<Int64> {
        return RangeIter(0, n)
    }
}

main() {
    let c = Counter(5)
    var sum = 0
    for (v in c) {
        sum += v
    }
    println(sum)
}
