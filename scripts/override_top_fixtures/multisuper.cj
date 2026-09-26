package multisuper

public interface AAA {
    func foo(x: Int64): Int64
}

public interface BBB {
    func foo(x: Int64): Int64
}

public class CCC <: AAA & BBB {
    public func foo(x: Int64): Int64 {
        x
    }
}

main() {
    CCC().foo(1)
}
