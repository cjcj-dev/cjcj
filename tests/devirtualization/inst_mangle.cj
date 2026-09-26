package devirt_inst_mangle

interface Slot<T> {
    func secondInst(): T
}

class Impl<T> <: Slot<T> {
    let stored: T
    public init(stored: T) {
        this.stored = stored
    }
    public func secondInst(): T {
        return stored
    }
}

interface OpenSlot {
    func secondGeneric<T>(x: T): T
}

class OpenImpl <: OpenSlot {
    public func secondGeneric<T>(x: T): T {
        return x
    }
}

public func chooseInst(): Int64 {
    let receiver: Slot<Int64> = Impl<Int64>(29)
    let openReceiver: OpenSlot = OpenImpl()
    return receiver.secondInst() + openReceiver.secondGeneric<Int64>(3)
}

main(): Int64 {
    return chooseInst()
}
