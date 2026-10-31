package cjcj::compiler_unittest

import cjcj::chir.ConstructorReturnsReceiver
import cjcj::chir.ReturnTypeShouldBeVoid
import cjcj::frontend.CompileStage
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ConstructorReceiverPipelineTest {
    @TestCase
    public func managedConstructorABIFlowsThroughRealFrontend(): Unit {
        let result = CompileSource("""
            package receiver_pipeline
            public open class Base {
                public var value: Int64 = 0
                public init(v: Int64) { value = v }
                public func read(): Int64 { value }
            }
            public class Derived <: Base {
                public init(v: Int64) { super(v); value = value + 1 }
                public init() { this(40) }
                ~init() {}
            }
            public struct Control {
                public let value: Int64
                public init(v: Int64) { value = v }
            }
            public func build(): Int64 { Derived().read() + Control(1).value }
            public func root(): Object { Object() }
            """, stage: CompileStage.CHIR)
        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
        let packages = result.instance.chirData.getOrThrow().GetAllRealCHIRPackages()
        @Assert(packages.size == 1)
        var baseConstructors = 0
        var derivedConstructors = 0
        var structConstructors = 0
        for (fn in packages[0].GetGlobalFunctions()) {
            if (!fn.IsConstructor() || fn.GetParentCustomTypeDef().isNone()) { continue }
            let owner = fn.GetParentCustomTypeDef().getOrThrow().GetSrcCodeIdentifier()
            if (owner == "Base" || owner == "Derived") {
                @Expect(ConstructorReturnsReceiver(fn), true)
                @Expect(ReturnTypeShouldBeVoid(fn), false)
                @Expect(fn.GetReturnType().getOrThrow() == fn.GetParam(0).GetType().getOrThrow(), true)
                @Expect(fn.GetReturnValue().isSome(), true)
                if (owner == "Base") { baseConstructors++ } else { derivedConstructors++ }
            } else if (owner == "Control") {
                @Expect(ConstructorReturnsReceiver(fn), false)
                @Expect(ReturnTypeShouldBeVoid(fn), true)
                structConstructors++
            }
        }
        @Expect(baseConstructors, 1)
        @Expect(derivedConstructors, 2)
        @Expect(structConstructors, 1)
    }
}
