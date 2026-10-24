package std.core

public open class Object {
    public const init() {}
}

public interface CType {}

public class Plain <: Object {
    public const init() { super() }
}

public const number: Int64 = 41
public const answer: Int64 = number
public const instance = Plain()
public const shared = instance
