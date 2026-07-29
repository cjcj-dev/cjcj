public open class Monkey {
    protected open func say() {}
}
public type GoodMonkey = Monkey
public open class LittleMonkey <: GoodMonkey {
    protected override func say() {}
}
main(): Int64 {
    let m: GoodMonkey = LittleMonkey()
    0
}
