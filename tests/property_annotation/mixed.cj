package property_annotation

@Annotation
public class Mark {
    public let value: Int64
    public const init(value: Int64) { this.value = value }
}

@Annotation
public class First {
    public let value: Int64
    public const init(value: Int64) { this.value = value }
}

public class Subject {
    private var storage: Int64 = 0
    @First[7]
    @Mark[1 + 2]
    public mut prop value: Int64 {
        get() { storage }
        set(v) { storage = v }
    }
}
