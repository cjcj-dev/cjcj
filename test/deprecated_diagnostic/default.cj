struct D {
    @Deprecated[message: "use alternate"]
    public init() {}
}
main(): Int64 {
    let d = D()
    return 0
}
