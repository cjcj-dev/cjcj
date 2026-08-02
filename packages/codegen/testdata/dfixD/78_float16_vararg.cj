package dfixd78

@C
foreign func dfixdSink(tag: Int32, ...): Int32

public func callLiteral(): Int32 {
    unsafe { dfixdSink(8, 1.5f16) }
}
