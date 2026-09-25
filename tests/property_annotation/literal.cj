package property_annotation

@Annotation
public class Mark {
    public let value: Int64
    public const init(value: Int64) { this.value = value }
}

public class Subject {
    private var storage: Int64 = 0
    @Mark[3]
    public mut prop value: Int64 {
        get() { storage }
        set(v) { storage = v }
    }
}
