package const_desugared_call

struct Callable {
    public const init() {}
    public const operator func ()(values: Array<Int64>): Int64 { 7 }
}
public const func invoke(): Int64 {
    let callable = Callable()
    callable(1, 2)
}
