package devirt_open_receiver
public open class Base {
    public open func value(): Int64 { return 41 }
}
public func readOpen(receiver: Base): Int64 { return receiver.value() }
main(): Int64 { return readOpen(Base()) }
