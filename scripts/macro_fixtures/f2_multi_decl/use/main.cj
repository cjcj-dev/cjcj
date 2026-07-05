// f2 use package: one macro call expands to two functions.
// Expected reference behavior:
//   - both packages compile clean (rc 0)
//   - gen_a() and gen_b() exist after expansion; binary returns 1 + 2 = 3
// Expected selfhost (MacroExpand stub) behavior: FAIL — @TwoFns is not
// expanded, so gen_a/gen_b are undeclared.
import f2def.*

@TwoFns
func placeholder(): Unit {}

main(): Int64 {
    gen_a() + gen_b()
}
