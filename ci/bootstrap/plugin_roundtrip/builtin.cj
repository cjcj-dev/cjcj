extend Int64 {
    public func pluginRoundtripValue(): Int64 { return this + 1 }
}
main(): Int64 {
    let n: Int64 = 41
    return n.pluginRoundtripValue() - 42
}
