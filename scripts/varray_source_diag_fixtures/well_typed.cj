type Alias = VArray<Int64, $2>

main() {
    let value = Alias(repeat: 1)
    let _ = value[0]
}
