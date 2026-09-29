package const_desugared_call

struct Callable<T> {
    public const init() {}
    public const operator func ()(values: Array<T>): Int64 { 7 }
}
public const func invoke(): Int64 {
    let callable = Callable<Int64>()
    callable()
}
