// f4 use package: attribute macro invoked with a bracketed attribute argument.
// Expected reference behavior:
//   - both packages compile clean (rc 0)
//   - @Attr[note] passes the "note" attribute tokens; decl returned unchanged;
//     binary returns 5
// Expected selfhost (MacroExpand stub) behavior: FAIL — @Attr is not expanded.
import f4def.*

@Attr[note]
func decorated(): Int64 { 5 }

main(): Int64 {
    decorated()
}
