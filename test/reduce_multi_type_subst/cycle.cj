package generic_cycle
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::sema.*
@Test
class GenericCycleTest {
    @TestCase
    func FiniteCycleTerminates(): Unit {
        let tm = TypeManager()
        let generic = tm.GetGenericsTy(GenericParamDecl())
        let root = TupleTy([])
        let child = TupleTy([generic])
        root.typeArgs.add(child)
        child.typeArgs.add(root)
        let result = GetAllGenericTys(root)
        println("TARGET_ASSERT finite-cycle count=${result.size}")
        @Expect(result.size, 1)
        @Expect(Ptr<GenericsTy>(result[0]) == Ptr<GenericsTy>(generic))
    }
}
