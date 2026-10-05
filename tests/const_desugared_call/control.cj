package const_desugared_call

struct Callable {
    public const init() {}
    public const operator func ()(value: Int64): Int64 { value }
}
public const func invoke(): Int64 {
    let callable = Callable()
    callable(7)
}
