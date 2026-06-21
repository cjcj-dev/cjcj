struct Cfg {
    let fileID: UInt64
    public init(fileID!: UInt64 = 0u64) {
        this.fileID = fileID
    }
}

main() {
    let a = Cfg()
    let b = Cfg(fileID: 7u64)
    println(a.fileID)
    println(b.fileID)
}
