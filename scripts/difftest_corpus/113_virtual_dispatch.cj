public open class Base {
    public open func greet(): Int64 {
        return 10
    }

    public open func inherited(): Int64 {
        return 30
    }
}

public class Sub <: Base {
    public override func greet(): Int64 {
        return 20
    }
}

main() {
    let base = Base()
    let sub = Sub()
    println(base.greet())
    println(sub.greet())
    println(sub.inherited())
}
