package devirt_boxed_receiver
interface Readable {
    func read(): Int64
}
struct Payload <: Readable {
    public func read(): Int64 { return 37 }
}
public func readPayload(): Int64 {
    let receiver: Readable = Payload()
    return receiver.read()
}
main(): Int64 { return readPayload() }
