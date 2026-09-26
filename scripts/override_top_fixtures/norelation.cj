package norelation

public interface AAA {
    func foo(x: Int64): Int64
}

public interface BBB {
    func foo(x: Int64): Int64
}

func posion<T>(x: T): Int64 where T <: AAA & BBB {
    0
}

public func goo<R>(x: R): Int64 where R <: BBB {
    x.foo(1)
}

main() {}
