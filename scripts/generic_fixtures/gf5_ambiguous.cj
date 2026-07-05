interface A {}
interface B {}
open class C <: A & B {}
func g<T>(x: T): Int64 where T <: A { return 1 }
func g<T>(x: T): Int64 where T <: B { return 2 }
main(): Int64 {
    println(g(C()))
    return 0
}
