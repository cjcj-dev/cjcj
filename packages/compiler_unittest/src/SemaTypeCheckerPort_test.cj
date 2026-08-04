package cjcj::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::frontend.CompileStage

@Test
public class SemaTypeCheckerPortTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:145 CheckInvalidVariadicOverload
    private func CheckInvalidVariadicOverload(code: String, expectResolvedFunction: Bool): Unit {
        let result = CompileSource(code, stage: CompileStage.SEMA)
        let memberCalls = ArrayList<CallExpr>()
        Walker(RequireFirstPackage(result).files[0], visitPre: { node: Node =>
            if (let Some(call) <- (node as CallExpr)) {
                if (let Some(baseFunc) <- call.baseFunc) {
                    if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                        if (memberAccess.field.Val() == "f") {
                            memberCalls.add(call)
                        }
                    }
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()

        @Assert(memberCalls.size == 1)
        @Expect(result.diag.GetErrorCount(), 2u64)
        let memberCall = memberCalls[0]
        if (!expectResolvedFunction) {
            @Expect(memberCall.resolvedFunction.isNone())
            return
        }
        @Assert(memberCall.resolvedFunction.isSome())
        let resolvedFunction = memberCall.resolvedFunction.getOrThrow()
        @Expect(!resolvedFunction.TestAttr(Attribute.IS_BROKEN))
        @Expect(!resolvedFunction.hasVariableLenArg)
        let memberAccess = (memberCall.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
        @Assert(memberAccess.target.isSome())
        @Expect(memberAccess.target.getOrThrow() == resolvedFunction)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:173 CheckInvalidVariadicFunctionReference
    private func CheckInvalidVariadicFunctionReference(code: String): Unit {
        let result = CompileSource(code, stage: CompileStage.SEMA)
        let functionReferences = ArrayList<MemberAccess>()
        Walker(RequireFirstPackage(result).files[0], visitPre: { node: Node =>
            if (let Some(memberAccess) <- (node as MemberAccess)) {
                if (memberAccess.field.Val() == "f") {
                    functionReferences.add(memberAccess)
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()

        @Assert(functionReferences.size == 1)
        @Expect(result.diag.GetErrorCount(), 2u64)
        let functionReference = functionReferences[0]
        @Assert(functionReference.target.isSome())
        let target = (functionReference.target.getOrThrow() as FuncDecl).getOrThrow()
        @Expect(!target.TestAttr(Attribute.IS_BROKEN))
        @Expect(!target.hasVariableLenArg)
        @Expect(functionReference.targets.size, 1)
        @Assert(functionReference.targets[0].isSome())
        @Expect(functionReference.targets[0].getOrThrow() == target)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:52 TEST_F(TypeCheckerTest, DISABLED_TypecheckTest)
    @TestCase
    public func typecheckTest(): Unit {
        let result = CompileSource("""
            main() {
                var t: Int32
                t = 1
                return 0
            }
            """, stage: CompileStage.SEMA)

        @Assert(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)

        let retKinds = ArrayList<TypeKind>()
        let localKinds = ArrayList<TypeKind>()
        let pkg = RequireFirstPackage(result)
        Walker(pkg.files[0], visitPre: { curNode: Node =>
            if (let Some(decl) <- (curNode as FuncDecl)) {
                let funcTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
                retKinds.add(funcTy.retTy.kind)
            }
            if (let Some(varDecl) <- (curNode as VarDecl)) {
                if (varDecl.identifier.Val() == "t") {
                    localKinds.add(varDecl.TyKind())
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()

        @Expect(retKinds.size, 1)
        @Expect(retKinds[0], TypeKind.TYPE_INT64)
        @Expect(localKinds.size, 1)
        @Expect(localKinds[0], TypeKind.TYPE_INT32)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:228 InvalidVariadicFunctionIsNotCallTarget
    @TestCase
    public func InvalidVariadicFunctionIsNotCallTarget(): Unit {
        CheckInvalidVariadicOverload("""
            class H {
                func f(...x: Int64): Unit
            }
            main() { H().f(1) }
            """, false)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:239 InvalidVariadicAfterValidOverloadDoesNotAffectCallTarget
    @TestCase
    public func InvalidVariadicAfterValidOverloadDoesNotAffectCallTarget(): Unit {
        CheckInvalidVariadicOverload("""
            class H {
                func f(x: Int64): Unit
                func f(...x: Int64): Unit
            }
            main() { H().f(1) }
            """, true)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:251 InvalidVariadicBeforeValidOverloadDoesNotAffectCallTarget
    @TestCase
    public func InvalidVariadicBeforeValidOverloadDoesNotAffectCallTarget(): Unit {
        CheckInvalidVariadicOverload("""
            class H {
                func f(...x: Int64): Unit
                func f(x: Int64): Unit
            }
            main() { H().f(1) }
            """, true)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:263 InvalidVariadicAfterValidOverloadDoesNotAffectFunctionReference
    @TestCase
    public func InvalidVariadicAfterValidOverloadDoesNotAffectFunctionReference(): Unit {
        CheckInvalidVariadicFunctionReference("""
            class H {
                func f(x: Int64): Unit
                func f(...x: Int64): Unit
            }
            main() { let functionReference = H().f }
            """)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:275 InvalidVariadicBeforeValidOverloadDoesNotAffectFunctionReference
    @TestCase
    public func InvalidVariadicBeforeValidOverloadDoesNotAffectFunctionReference(): Unit {
        CheckInvalidVariadicFunctionReference("""
            class H {
                func f(...x: Int64): Unit
                func f(x: Int64): Unit
            }
            main() { let functionReference = H().f }
            """)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:287 InvalidVariadicAfterValidImplementationDoesNotAffectInterfaceConformance
    @TestCase
    public func InvalidVariadicAfterValidImplementationDoesNotAffectInterfaceConformance(): Unit {
        CheckInvalidVariadicOverload("""
            interface I {
                func f(x: Int64): Unit
            }
            class H <: I {
                func f(x: Int64): Unit {}
                func f(...x: Int64): Unit
            }
            main() { H().f(1) }
            """, true)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Sema/TypeCheckerTest.cpp:303 InvalidVariadicBeforeValidImplementationDoesNotAffectInterfaceConformance
    @TestCase
    public func InvalidVariadicBeforeValidImplementationDoesNotAffectInterfaceConformance(): Unit {
        CheckInvalidVariadicOverload("""
            interface I {
                func f(x: Int64): Unit
            }
            class H <: I {
                func f(...x: Int64): Unit
                func f(x: Int64): Unit {}
            }
            main() { H().f(1) }
            """, true)
    }
}
