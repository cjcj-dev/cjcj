package sealed_fixture
sealed abstract class Root {}
open class A <: Root {}
class B <: Root {}
func notClosed(x: Root): Int64 {
    match (x) {
        case _: A => 1
        case _: B => 2
    }
}
