interface I { func f(): Int64 { 1 } }
abstract class B <: I {}
class C <: B {}
main() { C().f() - 1 }
