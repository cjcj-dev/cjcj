package sealed_fixture
sealed abstract class Root {}
class A <: Root {}
class B <: Root {}
func alternatives(x: Root): Int64 {
    match (x) {
        case _: A | _: B => 1
    }
}
