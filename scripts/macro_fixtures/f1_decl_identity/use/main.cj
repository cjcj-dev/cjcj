// f1 use package: applies the identity decl macro to a function.
// Expected reference behavior:
//   - macro package compiles clean (rc 0)
//   - user package compiles clean (rc 0); @Keep expands to the func unchanged
//   - binary runs and returns 42
// Expected selfhost (MacroExpand stub) behavior: FAIL — @Keep is never
// expanded, so the macro call is left unhandled / 'value' is undeclared.
import f1def.*

@Keep
func value(): Int64 { 42 }

main(): Int64 {
    value()
}
