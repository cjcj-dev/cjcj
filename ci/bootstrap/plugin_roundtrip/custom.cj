struct PluginRoundtripValue {
    public let value: Int64
    public init(value: Int64) { this.value = value }
}
extend PluginRoundtripValue {
    public func answer(): Int64 { return value }
}
main(): Int64 { return PluginRoundtripValue(42).answer() - 42 }
