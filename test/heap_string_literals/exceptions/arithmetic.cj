import std.runtime.gc
foreign {
    func literalZeroInput(): Int64
    func checkExceptionLiteral(ptr: CPointer<UInt8>, size: Int64): Unit
    func exceptionAssertionsDone(): Int32
}
func divide(value: Int64): Int64 { return 7 / value }
func observe(value: String): Unit {
    unsafe {
        let handle = acquireArrayRawData(value.rawData())
        checkExceptionLiteral(handle.pointer, value.size)
        releaseArrayRawData(handle)
    }
}
main(): Int64 {
    var message = ""
    try { let _ = divide(unsafe { literalZeroInput() }) }
    catch (error: ArithmeticException) { message = error.message }
    observe(message)
    gc(heavy: true)
    observe(message)
    return Int64(unsafe { exceptionAssertionsDone() })
}
