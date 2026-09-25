package dep03
public interface I<T> { func f(a: T): Int64 }
public open class A {
    public open func f(a: Int64): Int64 { return a + 1 }
}
extend A <: I<Int64> {}
public class B <: A {
    public func f(a: Int64): Int64 { return a + 1 }
}
@Frozen
public func foo() { B().f(1) }
