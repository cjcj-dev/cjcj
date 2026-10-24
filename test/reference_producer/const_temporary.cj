package std.core

public open class Object {
    public const init() {}
}

public interface CType {}

public class Finalized <: Object {
    public const init() { super() }
    ~init() {}
}

public const number: Int64 = 41

public const func temporaryValue(): Int64 {
    let temporary = Finalized()
    return number
}

public const answer = temporaryValue()
