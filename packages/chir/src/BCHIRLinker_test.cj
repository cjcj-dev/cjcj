package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class BCHIRLinkerTest {
    // BCHIRLinker.cpp:22-36 starts an empty definition with Push(JUMP).
    // Run with cjpm test -g so BCHIR.cpp:55-59's strict Resize contract is active.
    @TestCase
    public func constEvalStartsWithJump(): Unit {
        let linker = BCHIRLinker()
        let values = linker.RunForConstEval(ArrayList<BCHIR>())
        let code = linker.GetLinkedBCHIR().GetLinkedByteCode()
        @Expect(values.isEmpty(), true)
        @Expect(code.Size() > 0, true)
        @Expect(code.Get(0), OpCodeIndex(OpCode.JUMP))
        @Expect(code.Get(code.Size() - 1), OpCodeIndex(OpCode.EXIT))
    }

    @TestCase
    public func definitionStillSupportsStrictGrowth(): Unit {
        let code = BCHIRLinker().GetLinkedBCHIR().GetLinkedByteCode()
        code.PushOp(OpCode.JUMP)
        code.Resize(3)
        @Expect(code.Size(), 3)
        @Expect(code.Get(0), OpCodeIndex(OpCode.JUMP))
        @Expect(code.Get(1), 0)
        @Expect(code.Get(2), 0)
    }
}
