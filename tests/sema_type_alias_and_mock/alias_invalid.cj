type Count = Int64
main() {
    let named = Count(value: 1)
    let invalid = Count(true)
    let wrong: Bool = Count(1)
    let control: Int64 = Int64(1)
}
