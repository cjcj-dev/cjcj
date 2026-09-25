package sealed_fixture
sealed abstract class Root {}
class A <: Root {}
class B <: Root {}
func columns(x: Root, flag: Bool): Int64 {
    match ((x, flag)) {
        case (_: A, true) => 1
        case (_: B, true) => 2
        case (_, false) => 3
    }
}
