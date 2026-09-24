package builder_head_wrapper
interface Acceptor<T> {
    func accept(value: T): Int64
}
class FunctionAcceptor <: Acceptor<() -> Int64> {
    public func accept(value: () -> Int64): Int64 { return value() }
}
func use(acceptor: Acceptor<() -> Int64>, value: () -> Int64): Int64 {
    return acceptor.accept(value)
}
main(): Int64 {
    let value = 41
    return use(FunctionAcceptor(), { => value })
}
