interface A {}
interface B {}
open class C <: A & B {}
func g<T>(x: T): Int64 where T <: A { let _ = x; return 1 }
func g<T>(x: T): Int64 where T <: B { let _ = x; return 2 }
main(): Int64 {
    return 0
}
