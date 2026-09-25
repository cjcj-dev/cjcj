type Alias = VArray<Int64, $2>

main() {
    let value: VArray<Int32, $2> = Alias(repeat: 1)
    let _ = value[0]
}
