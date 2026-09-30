package mangle_annotations

@Annotation
public class Mark {
    public let value: Int64
    public const init(value: Int64) { this.value = value }
}

@Mark[3]
public func annotated(x: Int64): Int64 {
    let f = { y: Int64 => x + y }
    f(3)
}
