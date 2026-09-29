// G10 valid-program negative control: enum.
enum Choice { Yes | No }
main(): Int64 {
    let x = Choice.Yes
    let v = match (x) { case Yes => 42; case No => 0 }
    if (v != 42) { return 1 }
    return 0
}
