package sealed_fixture
sealed abstract class Root {
    func classify(): Int64 {
        match (this) {
            case _: A => 1
            case _: B => 2
            case _ => 3
        }
    }
}
class A <: Root {}
class B <: Root {}
