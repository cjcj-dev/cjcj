package pkgA4

protected open class Base {
    public init() {}

    public func value(): Int64 {
        return 17
    }
}

public class A <: Base {
    public init() {
        super()
    }
}

public class B <: Base {
    public init() {
        super()
    }
}

public func makeA(): A {
    return A()
}

public func makeB(): B {
    return B()
}
