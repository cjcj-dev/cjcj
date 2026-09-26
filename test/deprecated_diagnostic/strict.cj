struct D {
    @Deprecated[message: "use alternate", strict: true]
    public init() {}
}
main(): Int64 {
    let d = D()
    return 0
}
