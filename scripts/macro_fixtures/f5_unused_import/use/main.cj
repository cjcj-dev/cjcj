// f5 use package (positive case): the imported package f5def is referenced ONLY
// through the @TwoFns macro call; no named entity from f5def is used directly.
// Expected reference behavior:
//   - both packages compile clean (rc 0) with NO "unused import" warning
//   - binary returns 1 + 2 = 3
// Expected selfhost (MacroExpand stub) behavior: FAIL — @TwoFns is not expanded,
// so gen_a/gen_b are undeclared; the used-macro record is also never made.
import f5def.*

@TwoFns
func placeholder(): Unit {}

main(): Int64 {
    gen_a() + gen_b()
}
