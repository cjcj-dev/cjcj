import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.mock.*
import std.unittest.mock.mockmacro.*

public struct Cell {
    public var value: Int64
    public init(v: Int64) { value = v }
}
public class Holder {
    public var cell = Cell(3)
}
public class Primary {
    public Primary(public var value: Int64) {}
    public func read(): Int64 { value }
    public func write(v: Int64): Unit { value = v }
}
@Test
class FieldBackportTest {
    @TestCase
    func compoundStructFieldUsesOneGetterAndSetter(): Unit {
        let original = Holder()
        let wrapped = spy(original)
        @On(wrapped.cell).getsOriginal().once()
        @On(wrapped.cell = _).setsOriginal().once()
        wrapped.cell.value += 4
        @Expect(original.cell.value, 7)
        let control = Holder()
        control.cell.value += 4
        @Expect(control.cell.value, 7)
    }
    @TestCase
    func primaryMemberRefsUseAccessors(): Unit {
        let original = Primary(3)
        let wrapped = spy(original)
        @On(wrapped.value).returns(41).once()
        @On(wrapped.value = 7).setsOriginal().once()
        @Expect(wrapped.read(), 41)
        wrapped.write(7)
        @Expect(original.value, 7)
        let control = Primary(3)
        control.write(7)
        @Expect(control.read(), 7)
    }
}
