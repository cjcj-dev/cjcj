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
public const answer: Int64 = number
public const instance = Finalized()
public const shared = instance
