public open class Holder {
    public let features: Int64
    public init(features: Int64) { this.features = features }
}

func bump(common!: Int64): Int64 {
    return common + 1
}

main() {
    let features = 3
    let open = Holder(5)
    println(features + bump(common: open.features))
}
