// G10 valid-program negative control: enum_payload.
enum Value { Number(Int64) | Empty }
main(): Int64 {
    let x = Value.Number(42)
    let v = match (x) { case Number(n) => n; case Empty => 0 }
    if (v != 42) { return 1 }
    return 0
}
