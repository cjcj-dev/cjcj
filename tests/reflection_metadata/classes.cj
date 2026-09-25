package reflection_attrs

public abstract class ImplicitOpen {
    public init() {}
}

public abstract class GenericOpen<T> {
    public init() {}
}

public open class ExplicitOpen {
    public init() {}
}

public class Closed {
    public init() {}
}

public interface Contract {}
