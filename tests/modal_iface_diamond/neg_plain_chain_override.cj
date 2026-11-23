// Negative control: plain defaults along an override chain keep the upstream rule (official cjc rejects it too).
interface I1 { func foo(): Int64 { 1 } }
interface I2 <: I1 { func foo(): Int64 { 2 } }
struct S <: I2 & I1 {}

main(): Int64 { S().foo() }
