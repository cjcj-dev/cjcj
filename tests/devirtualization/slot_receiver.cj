package devirt_slot_receiver
interface Slots {
    func first(): Int64
    func second(): Int64
}
class Impl <: Slots {
    public func first(): Int64 { return 11 }
    public func second(): Int64 { return 29 }
}
public func chooseSecond(): Int64 {
    let receiver: Slots = Impl()
    return receiver.second()
}
main(): Int64 { return chooseSecond() }
