open class A {
    public open func tag(): Int64 {
        return 1
    }
}

class B <: A {
    public override func tag(): Int64 {
        return 2
    }

    public func extra(): Int64 {
        return 42
    }
}

func check(x: A): Unit {
    if (x is B) {
        println("is B")
    } else {
        println("not B")
    }

    match (x as B) {
        case Some(b) => println(b.extra())
        case None => println("as None")
    }
}

main() {
    let a: A = A()
    let b: A = B()
    check(a)
    check(b)
}
