// Negative control (local mode): two unrelated modal defaults are a genuine conflict.
interface I1 { func foo(this @local?): Int64 { 7 } }
interface I3 { func foo(this @local?): Int64 { 9 } }
struct S <: I1 & I3 {}

main(): Int64 { 0 }
