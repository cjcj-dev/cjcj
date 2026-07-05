// f5 control case (negative): a genuinely unused wildcard import MUST still be
// reported as unused. This proves the positive case above is a real suppression
// driven by macro usage, not blanket disabling of the unused-import check.
// Expected reference behavior:
//   - compiles (rc 0) but emits warning: unused import 'std.collection.*'
// Expected selfhost behavior: this control does not involve macros, so it is a
// pure unused-import-check comparison independent of macro expansion.
import std.collection.*

main(): Int64 {
    0
}
