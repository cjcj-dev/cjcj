// Negative control (local mode): an abstract modal member is still required.
interface I1 { func foo(this @local?): Int64 }
struct S <: I1 {}

main(): Int64 { 0 }
