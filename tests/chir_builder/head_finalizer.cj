package builder_head_finalizer
class Finalized {
    public let value: Int64
    public init(value: Int64) { this.value = value }
    ~init() {}
}
main(): Int64 {
    return Finalized(41).value
}
