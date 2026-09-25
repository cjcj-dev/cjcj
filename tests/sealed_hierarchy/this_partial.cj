package sealed_fixture
sealed abstract class Root {
    func classify(): Int64 {
        match (this) {
            case _: A => 1
            case _ => 2
        }
    }
}
class A <: Root {}
class B <: Root {}
