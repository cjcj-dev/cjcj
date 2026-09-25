interface I { func f(): Int64 { 1 } }
abstract class B <: I {}
class C <: B { public func f(): Int64 { 2 } }
main() { C().f() - 2 }
