package const_desugared_call

struct Callable {
    public const init() {}
    public const operator func ()(value: Int64): Int64 { value }
}

const callable = Callable()
const result = callable(7)
