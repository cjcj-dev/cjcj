package sealed_fixture
sealed abstract class Root<T> {}
class A <: Root<Int64> {}
class B <: Root<Int64> {}
func notClosed(x: Root<Int64>): Int64 {
    match (x) {
        case _: A => 1
        case _: B => 2
    }
}
