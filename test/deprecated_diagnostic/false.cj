struct D {
    @Deprecated[message: "use alternate", strict: false]
    public init() {}
}
main(): Int64 {
    let d = D()
    return 0
}
