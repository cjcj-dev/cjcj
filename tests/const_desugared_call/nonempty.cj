package const_desugared_call

struct Callable {
    public const init() {}
    public const operator func ()(values: Array<Int64>): Int64 { 7 }
}

const callable = Callable()
const result = callable(1, 2)
