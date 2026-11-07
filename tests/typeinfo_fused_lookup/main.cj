package typeinfo_fused_lookup

// Generic interface: the package needs the method outer TypeInfo, so each
// interface dispatch gets one fused mtable/outer-TypeInfo lookup.
interface Shape<T> {
    func area(): T
}

class Square <: Shape<Int64> {
    Square(let side: Int64) {}
    public func area(): Int64 {
        side * side
    }
}

class Line <: Shape<Int64> {
    public func area(): Int64 {
        0
    }
}

class Faulty <: Shape<Int64> {
    var calls = 0
    public func area(): Int64 {
        calls++
        if (calls % 2 == 0) {
            throw IllegalStateException("faulty")
        }
        calls
    }
}

// Non-generic interface with non-generic implementors: no outer TypeInfo is
// needed, the original single mtable lookup stays.
interface Plain {
    func value(): Int64
}

class PlainImpl <: Plain {
    public func value(): Int64 {
        7
    }
}

// Class virtual dispatch keeps the vtable path.
open class Base {
    public open func id(): Int64 {
        1
    }
}

class Derived <: Base {
    public override func id(): Int64 {
        2
    }
}

func fusedSite(s: Shape<Int64>): Int64 {
    s.area()
}

func plainSite(p: Plain): Int64 {
    p.value()
}

func classSite(b: Base): Int64 {
    b.id()
}

func loopSite(shapes: Array<Shape<Int64>>): Int64 {
    var sum = 0
    for (s in shapes) {
        sum += s.area()
    }
    sum
}

func optionLoop(o: Option<Shape<Int64>>, n: Int64): Int64 {
    var sum = 0
    for (_ in 0..n) {
        if (let Some(s) <- o) {
            sum += s.area()
        }
    }
    sum
}

func throwingSite(s: Shape<Int64>, n: Int64): Int64 {
    var caught = 0
    var sum = 0
    for (_ in 0..n) {
        try {
            sum += s.area()
        } catch (e: IllegalStateException) {
            caught++
        }
    }
    caught * 100 + sum
}

func check(name: String, ok: Bool): Bool {
    if (!ok) {
        println("FAIL ${name}")
    }
    ok
}

main(): Int64 {
    let sq: Shape<Int64> = Square(3)
    let shapes: Array<Shape<Int64>> = [Square(2), Line(), Square(4)]
    let empty: Array<Shape<Int64>> = []
    var ok = true
    ok = check("fusedSite", fusedSite(sq) == 9 && fusedSite(Line()) == 0) && ok
    ok = check("plainSite", plainSite(PlainImpl()) == 7) && ok
    ok = check("classSite", classSite(Derived()) == 2 && classSite(Base()) == 1) && ok
    ok = check("loopSite", loopSite(shapes) == 20) && ok
    ok = check("zeroTrip", loopSite(empty) == 0) && ok
    ok = check("optionNone", optionLoop(None, 0) == 0 && optionLoop(None, 5) == 0) && ok
    ok = check("optionSome", optionLoop(Some(sq), 3) == 27) && ok
    // Faulty returns 1, throws, returns 3, throws: two caught, sum 4.
    ok = check("throwing", throwingSite(Faulty(), 4) == 204) && ok
    if (!ok) {
        return 1
    }
    println("typeinfo_fused_lookup OK")
    0
}
