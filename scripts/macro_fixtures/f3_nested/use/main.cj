// f3 use package: a macro whose output contains another macro call.
// @Outer -> "@Inner let outer_v = 0" -> "let inner_v = 7".
// Expected reference behavior:
//   - both packages compile clean (rc 0)
//   - after nested expansion a global `inner_v = 7` exists; binary returns 7
// Expected selfhost (MacroExpand stub) behavior: FAIL — neither @Outer nor the
// nested @Inner is expanded.
import f3def.*

@Outer
let placeholder = 0

main(): Int64 {
    inner_v
}
