interface I { func f(): Int64 { 1 } }
abstract class B <: I {}
abstract class C <: B { public func f(): Int64 }
main() {}
