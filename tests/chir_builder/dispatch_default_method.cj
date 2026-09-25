package dispatch_default_method
interface ParentReader {
    func read(): Int64
}
interface DefaultReader <: ParentReader {
    func read(): Int64 { return 41 }
}
class ReaderImpl <: DefaultReader {}
func call(value: DefaultReader): Int64 { return value.read() }
main(): Int64 {
    println(call(ReaderImpl()))
    return 0
}
