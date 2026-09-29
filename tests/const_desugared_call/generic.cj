package const_desugared_call

struct Callable<T> {
    public const init() {}
    public const operator func ()(values: Array<T>): Int64 { 7 }
}

const callable = Callable<Int64>()
const result = callable()
