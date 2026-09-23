import f1def.*

@Keep
func value(): Int64 { 42 }

main(): Int64 {
    if (value() != 42) { return 1 }
    println("MACRO_VALUE_ASSERT value=42")
    return 0
}
