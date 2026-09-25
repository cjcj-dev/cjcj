package sealed_fixture
sealed interface Root {}
class A <: Root {}
class B <: Root {}
func closed(x: Root): Int64 {
    match (x) {
        case _: A => 1
        case _: B => 2
    }
}
