type Alias = VArray<Int64, $2>

main() {
    let value = Alias(1) { _ => 0 }
}
