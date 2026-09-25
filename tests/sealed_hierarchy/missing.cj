package sealed_fixture
sealed abstract class Root {}
class A <: Root {}
class B <: Root {}
func missing(x: Root): Int64 {
    match (x) {
        case _: A => 1
    }
}
