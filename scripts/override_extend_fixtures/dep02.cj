package dep02
public interface I<T> { func f(a: T): Int64 }
public class A {}
extend A {
    public func f(a: Int64): Int64 { return 1 }
}
extend A <: I<Int64> {}
@Frozen
public func foo() { return A().f(5) }
