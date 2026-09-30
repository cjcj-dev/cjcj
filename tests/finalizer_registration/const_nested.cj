package std.core

public open class Object {
    public const init() {}
}

public interface CType {}

public open class Middle <: Object {
    public const init() { super() }
}

public class Finalized <: Middle {
    public const init() { super() }
    ~init() {}
}

public class Holder <: Object {
    public let value: Finalized
    public const init(value: Finalized) {
        super()
        this.value = value
    }
}

public const nested = Holder(Finalized())
public const shared = nested
