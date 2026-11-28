package frozenmodals

public class FrozenBox<T> {
    public init() {}

    @Frozen
    public func plain(): Int64 {
        let localValue: String @local! = "payload"
        this.required(localValue) + 1
    }

    @Frozen
    public func required(value: String @local!): Int64 {
        if (value.size == 7) { 41 } else { -1 }
    }

    @Frozen
    public func unusedFull(this @local!): Int64 { 1 }

    @Frozen
    public func unusedHalf(this @local?): Int64 { 2 }
}
