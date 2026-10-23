package cjcj::sema.initialization_tests

import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import cjcj::basic.{DiagCategory, DiagKind, DiagKindRefactor}
import cjcj::compiler_unittest.*
import cjcj::frontend.CompileStage

// Compile actual source through parser/imports/SEMA. A parse or SDK error must
// fail these tests, rather than count as rejection of the intended bad read.
private func ExpectInitializationDiagnostic(code: String, immutable!: Bool = false): Unit {
    @Assert(!getVariable("CANGJIE_HOME").getOrThrow().isEmpty())
    let result = CompileSource(code, stage: CompileStage.SEMA)
    @Assert(!result.ok)
    @Assert(result.instance.faithfulSemaInstance.isSome())
    let diag = result.instance.faithfulSemaInstance.getOrThrow().diag.getOrThrow()
    let marker = if (immutable) { "// expected-let-error" } else { "// expected-init-error" }
    var expectedLine: Int64 = 0
    var line: Int64 = 1
    for (text in code.split("\n")) {
        if (text.contains(marker)) { expectedLine = line }
        line++
    }
    @Assert(expectedLine > 0)
    var found = false
    for (diagnostic in diag.GetCategoryDiagnostic(DiagCategory.SEMA)) {
        let expectedKind = if (immutable) {
            diagnostic.isRefactor && diagnostic.rKind == DiagKindRefactor.sema_cannot_assign_to_immutable
        } else {
            diagnostic.kind == DiagKind.sema_used_before_initialization
        }
        let diagnosticLine = if (diagnostic.isRefactor) {
            diagnostic.mainHint.range.begin.line
        } else { diagnostic.start.line }
        if (expectedKind && diagnosticLine == expectedLine) {
            found = true
        }
    }
    println("INITIALIZATION_ASSERT expected_line=${expectedLine} target_diagnostic=${found}")
    @Expect(found)
    @Expect(result.diag.GetErrorCount(), 1u64)
}

private func ExpectInitializationAccepted(code: String): Unit {
    @Assert(!getVariable("CANGJIE_HOME").getOrThrow().isEmpty())
    let result = CompileSource(code, stage: CompileStage.SEMA)
    @Expect(result.ok)
    @Expect(result.diag.GetErrorCount(), 0u64)
}

@Test
public class InitializationControlFlowTest {
    @TestCase
    public func InterpolatedToStringMayThrowBeforeAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            struct ThrowingText <: ToString {
                public func toString(): String { throw Exception() }
            }
            func read(value: ThrowingText): Int64 {
                var x: Int64
                try {
                    let text = "INTERPOLATE"
                    x = 1
                } catch (e: Exception) {}
                return x // expected-init-error
            }
            """.replace("INTERPOLATE", "$" + "{value}"))
    }

    @TestCase
    public func InterpolatedToStringMayThrowBeforeLaterPart(): Unit {
        ExpectInitializationDiagnostic("""
            struct ThrowingText <: ToString {
                public func toString(): String { throw Exception() }
            }
            func read(value: ThrowingText): Int64 {
                var x: Int64
                try {
                    let text = "INTERPOLATE"
                } catch (e: Exception) {}
                return x // expected-init-error
            }
            """.replace("INTERPOLATE", "$" + "{value}" + "$" + "{x = 1; 0}"))
    }

    @TestCase
    public func InterpolatedToStringWithInitializedValueIsLegal(): Unit {
        let result = CompileSource("""
            struct ThrowingText <: ToString {
                public func toString(): String { throw Exception() }
            }
            func read(value: ThrowingText): Int64 {
                var x: Int64 = 0
                try {
                    let text = "INTERPOLATE"
                    x = 1
                } catch (e: Exception) {}
                return x
            }
            """.replace("INTERPOLATE", "$" + "{value}"), stage: CompileStage.DESUGAR_AFTER_SEMA)
        @Assert(result.instance.faithfulSemaInstance.isSome())
        @Expect(result.ok)
        @Expect(result.diag.GetErrorCount(), 0u64)
    }

    @TestCase
    public func PrimitiveInterpolationDoesNotThrowException(): Unit {
        ExpectInitializationAccepted("""
            func read(value: Int64): Int64 {
                var x: Int64
                try {
                    let text = "INTERPOLATE"
                    x = 1
                } catch (e: Exception) {}
                return x
            }
            """.replace("INTERPOLATE", "$" + "{value}"))
    }

    @TestCase
    public func CatchOnlyAssignmentDoesNotInitialize(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                } catch (e: Exception) {
                    x = 7
                }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func TryOnlyAssignmentDoesNotInitializeAfterCatch(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                    x = 7
                } catch (e: Exception) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func CatchReadsStartAtTryEntry(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                    x = 7
                } catch (e: Exception) {
                    return x // expected-init-error
                }
                return x
            }
            """)
    }

    @TestCase
    public func AllTryAndCatchExitsInitialize(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                    x = 7
                } catch (e: Exception) {
                    x = 9
                }
                return x
            }
            """)
    }

    @TestCase
    public func TerminatingTryAllowsCatchInitialization(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                let x: Int64
                try {
                    throw Exception()
                } catch (e: Exception) {
                    x = 7
                }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyInitializesNormalExit(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                } catch (e: Exception) {} finally {
                    x = 7
                }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyDoesNotAssumeNormalTryExit(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { throw Exception() }
                    x = 7
                } finally {
                    let observed = x // expected-init-error
                }
                return x
            }
            """)
    }

    @TestCase
    public func TryInitializationSurvivesEmptyFinally(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                var x: Int64
                try {
                    x = 7
                } finally {}
                return x
            }
            """)
    }

    @TestCase
    public func DoWhileBreakDoesNotTerminateIfBranch(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do { break } while (false)
                } else {
                    x = 7
                }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func DoWhileContinueDoesNotTerminateIfBranch(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do { continue } while (false)
                } else {
                    x = 7
                }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func ConditionalLocalBreakBeforeReturnStillContinues(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool, stop: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do {
                        if (stop) { break }
                        return 1
                    } while (false)
                } else {
                    x = 7
                }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func ReturningDoWhileBranchIsExcluded(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do { return 1 } while (false)
                } else {
                    x = 7
                }
                return x
            }
            """)
    }

    @TestCase
    public func JumpInDifferentLoopDoesNotHideReturn(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do {
                        while (true) { break }
                        return 1
                    } while (false)
                } else {
                    x = 7
                }
                return x
            }
            """)
    }

    @TestCase
    public func AssignmentAfterLocalBreakInitializesBranch(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                if (flag) {
                    do { break } while (false)
                    x = 1
                } else {
                    x = 7
                }
                return x
            }
            """)
    }

    @TestCase
    public func MatchGuardDoesNotInitializeFallback(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool, gate: Bool): Int64 {
                var x: Int64
                match (flag) {
                    case true where (if (gate) {
                        x = 1
                        true
                    } else {
                        x = 2
                        true
                    }) => 0
                    case _ => x // expected-init-error
                }
            }
            """)
    }

    @TestCase
    public func MatchGuardInitializationIsAvailableInItsOwnArm(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool, gate: Bool): Int64 {
                var x: Int64
                match (flag) {
                    case true where (if (gate) {
                        x = 1
                        true
                    } else {
                        x = 2
                        true
                    }) => x
                    case _ => 0
                }
            }
            """)
    }

    @TestCase
    public func GuardAndFallbackAssignmentsMergeEvenWithLiteralActions(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool, gate: Bool): Int64 {
                var x: Int64
                match (flag) {
                    case true where (if (gate) {
                        x = 1
                        true
                    } else {
                        x = 2
                        true
                    }) => 0
                    case _ =>
                        x = 3
                        0
                }
                return x
            }
            """)
    }

    @TestCase
    public func PreviouslyInitializedValueSurvivesMatch(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool, gate: Bool): Int64 {
                var x: Int64 = 4
                match (flag) {
                    case true where gate => x = 1
                    case _ => x = 2
                }
                return x
            }
            """)
    }

    @TestCase
    public func CatchLetReassignmentRemainsRejected(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                let x: Int64
                try {
                    x = 1
                    if (flag) { throw Exception() }
                } catch (e: Exception) {
                    x = 2 // expected-let-error
                }
                return x
            }
            """, immutable: true)
    }

    @TestCase
    public func FinallyLetReassignmentRemainsRejected(): Unit {
        ExpectInitializationDiagnostic("""
            func read(): Int64 {
                let x: Int64
                try {
                    x = 1
                } finally {
                    x = 2 // expected-let-error
                }
                return x
            }
            """, immutable: true)
    }

    @TestCase
    public func ConditionalCatchWritePreventsLaterLetReassignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                let x: Int64
                try {
                    if (flag) { throw Exception() }
                } catch (e: Exception) { x = 1 }
                x = 2 // expected-let-error
                return x
            }
            """, immutable: true)
    }

    @TestCase
    public func FailedGuardWritePreventsFallbackLetReassignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool, gate: Bool): Int64 {
                let x: Int64
                match (flag) {
                    case true where (if (gate) {
                        x = 1
                        false
                    } else {
                        x = 2
                        false
                    }) => 0
                    case _ =>
                        x = 3 // expected-let-error
                        0
                }
                return x
            }
            """, immutable: true)
    }

    @TestCase
    public func TryWriteDoesNotLeakIntoSiblingIfBranch(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                if (flag) {
                    try { x = 1 } finally {}
                } else {
                    x = 2
                }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyReadsNonThrowingTryAssignment(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                var x: Int64
                try { x = 7 } finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyReadsAssignmentBeforeReturn(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                var x: Int64
                try { x = 7; return x } finally { let observed = x }
            }
            """)
    }

    @TestCase
    public func FinallyIncludesReturnBeforeAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { return 1 }
                    x = 7
                } finally { let observed = x } // expected-init-error
                return x
            }
            """)
    }

    @TestCase
    public func ReturnBranchDoesNotPreventOnlyReachableLetWrite(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                if (flag) {
                    try { x = 1 } finally {}
                    return 1
                }
                x = 2
                return x
            }
            """)
    }

    @TestCase
    public func MatchReturnBranchDoesNotPreventOnlyReachableLetWrite(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                match (flag) {
                    case true => x = 1; return 1
                    case _ => 0
                }
                x = 2
                return x
            }
            """)
    }

    @TestCase
    public func DirectConditionalLetWriteRemainsPossible(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                let x: Int64
                if (flag) { x = 1 }
                x = 2 // expected-let-error
                return x
            }
            """, immutable: true)
    }

    @TestCase
    public func MutuallyExclusiveLetWritesRemainAccepted(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                if (flag) { x = 1 } else { x = 2 }
                return x
            }
            """)
    }

    @TestCase
    public func ElseIfConditionWriteReachesBothSuccessors(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool, gate: Bool): Int64 {
                var x: Int64
                if (flag) { x = 1 }
                else if (if (gate) { x = 2; true } else { x = 3; false }) {
                    let observed = x
                } else { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func ForGuardDoesNotRunOnEmptyInput(): Unit {
        ExpectInitializationDiagnostic("""
            func read(n: Int64, gate: Bool): Int64 {
                var x: Int64
                for (i in 0..n where (if (gate) { x = 1; true } else { x = 2; true })) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func ForInputAlwaysRunsBeforeZeroTrips(): Unit {
        ExpectInitializationAccepted("""
            func read(gate: Bool): Int64 {
                var x: Int64
                for (i in (if (gate) { x = 1; 0..0 } else { x = 2; 0..0 })) {}
                return x
            }
            """)
    }

    @TestCase
    public func ForGuardWriteIsAvailableToBody(): Unit {
        ExpectInitializationAccepted("""
            func read(n: Int64, gate: Bool): Unit {
                var x: Int64
                for (i in 0..n where (if (gate) { x = 1; true } else { x = 2; true })) {
                    let observed = x
                }
            }
            """)
    }

    @TestCase
    public func BreakSkipsDoWhileConditionAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(stop: Bool, gate: Bool): Int64 {
                var x: Int64
                do { if (stop) { break } }
                while (if (gate) { x = 1; false } else { x = 2; false })
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func ContinueReachesDoWhileConditionAssignment(): Unit {
        ExpectInitializationAccepted("""
            func read(gate: Bool): Int64 {
                var x: Int64
                do { continue }
                while (if (gate) { x = 1; false } else { x = 2; false })
                return x
            }
            """)
    }

    @TestCase
    public func DoWhileBodyWriteReachesBreak(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                var x: Int64
                do { x = 7; break } while (false)
                return x
            }
            """)
    }

    @TestCase
    public func MatchLocalBreakDoesNotTerminateArm(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                var x: Int64
                match (flag) {
                    case true => do { break } while (false)
                    case _ => x = 7
                }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func SubscriptStoreChecksBase(): Unit {
        ExpectInitializationDiagnostic("""
            func write(): Unit {
                var values: Array<Int64>
                values[0] = 7 // expected-init-error
            }
            """)
    }

    @TestCase
    public func SubscriptStoreChecksIndex(): Unit {
        ExpectInitializationDiagnostic("""
            func write(values: Array<Int64>): Unit {
                var index: Int64
                values[index] = 7 // expected-init-error
            }
            """)
    }

    @TestCase
    public func SubscriptIndexPrecedesRightHandInitialization(): Unit {
        ExpectInitializationDiagnostic("""
            func write(values: Array<Int64>, gate: Bool): Unit {
                var index: Int64
                values[index] = if (gate) { index = 0; 7 } else { index = 0; 8 } // expected-init-error
            }
            """)
    }

    @TestCase
    public func SubscriptIndexWriteReachesRightHandRead(): Unit {
        ExpectInitializationAccepted("""
            func write(values: Array<Int64>, gate: Bool): Unit {
                var x: Int64
                values[if (gate) { x = 7; 0 } else { x = 8; 0 }] = x
            }
            """)
    }

    @TestCase
    public func CompoundAndDoesNotGuaranteeRightHandAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool, gate: Bool): Int64 {
                var condition = flag
                var x: Int64
                condition &&= if (gate) { x = 1; true } else { x = 2; false }
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func InitializedSubscriptStoreAccepted(): Unit {
        ExpectInitializationAccepted("""
            func write(values: Array<Int64>): Unit {
                var index = 0
                values[index] = 7
            }
            """)
    }

    @TestCase
    public func LetPatternAndDoesNotInitializeFalseExit(): Unit {
        ExpectInitializationDiagnostic("""
            func read(value: ?Int64, gate: Bool): Int64 {
                var x: Int64
                if (let Some(n) <- value && (if (gate) { x = n; true } else { x = 2; true })) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func LetPatternAndInitializesTrueExit(): Unit {
        ExpectInitializationAccepted("""
            func read(value: ?Int64, gate: Bool): Int64 {
                var x: Int64
                if (let Some(n) <- value && (if (gate) { x = n; true } else { x = 2; true })) {
                    return x
                }
                return 0
            }
            """)
    }

    @TestCase
    public func CatchReturnDoesNotContributePossibleWriteToNormalExit(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                try { if (flag) { throw Exception() } }
                catch (e: Exception) { x = 1; return x }
                x = 2
                return x
            }
            """)
    }

    @TestCase
    public func FinallyDoesNotMergeReturningWriteIntoNormalExit(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                let x: Int64
                try { if (flag) { x = 1; return x } } finally {}
                x = 2
                return x
            }
            """)
    }

    @TestCase
    public func FinallyWritesRemainPossibleAfterConditionalEarlyWrite(): Unit {
        ExpectInitializationDiagnostic("""
            func read(flag: Bool): Int64 {
                let x: Int64
                try { if (flag) { x = 1; return x } }
                finally { x = 2 } // expected-let-error
                return 0
            }
            """, immutable: true)
    }

    @TestCase
    public func FinallyWriteSurvivesExceptionalOnlyPriorAssignment(): Unit {
        ExpectInitializationAccepted("""
            func read(flag: Bool): Int64 {
                var x: Int64
                try {
                    if (flag) { x = 1; throw Exception() }
                } finally { x = 2 }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyCallAfterWriteReadsInitializedValue(): Unit {
        ExpectInitializationAccepted("""
            func mayThrow(): Unit { throw Exception() }
            func read(): Int64 {
                var x: Int64
                try { x = 7; mayThrow() }
                finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func FinallyCallBeforeWriteRetainsExceptionEntry(): Unit {
        ExpectInitializationDiagnostic("""
            func mayThrow(): Unit { throw Exception() }
            func read(): Int64 {
                var x: Int64
                try { mayThrow(); x = 7 }
                finally { let observed = x } // expected-init-error
                return x
            }
            """)
    }

    @TestCase
    public func ResourceCloseCanReachCatchBeforeReturn(): Unit {
        ExpectInitializationDiagnostic("""
            class Handle <: Resource {
                public func close(): Unit { throw Exception() }
                public func isClosed(): Bool { false }
            }
            func read(resource: Handle): Int64 {
                var x: Int64
                try (r = resource) { return 1 }
                catch (e: Exception) { let observed = x } // expected-init-error
                return 0
            }
            """)
    }

    @TestCase
    public func ResourceCloseCarriesAssignmentBeforeReturn(): Unit {
        ExpectInitializationAccepted("""
            class Handle <: Resource {
                public func close(): Unit { throw Exception() }
                public func isClosed(): Bool { false }
            }
            func read(resource: Handle): Int64 {
                var x: Int64
                try (r = resource) { x = 7; return x }
                catch (e: Exception) { return x }
                return 0
            }
            """)
    }

    @TestCase
    public func ConstructorBranchWritesInitializeField(): Unit {
        ExpectInitializationAccepted("""
            class Value {
                let x: Int64
                init(flag: Bool) {
                    if (flag) { this.x = 1 } else { this.x = 2 }
                }
                func read(): Int64 { x }
            }
            """)
    }

    @TestCase
    public func ConstructorFinallyInitializesBeforeReturn(): Unit {
        ExpectInitializationAccepted("""
            class Value {
                let x: Int64
                init() { try { return } finally { x = 7 } }
                func read(): Int64 { x }
            }
            """)
    }

    @TestCase
    public func ConstructorOnlyThrowingPathsNeedNoFieldValue(): Unit {
        ExpectInitializationAccepted("""
            class Value {
                let x: Int64
                init() { throw Exception() }
            }
            """)
    }

    @TestCase
    public func NestedFunctionDoesNotEndEnclosingFlow(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                func inner(): Int64 { return 1 }
                let x: Int64
                x = inner()
                return x
            }
            """)
    }

    @TestCase
    public func ConditionalMatchPreservesOrderedConditionWrites(): Unit {
        ExpectInitializationAccepted("""
            func read(gate: Bool): Int64 {
                var x: Int64
                match {
                    case (if (gate) { x = 1; false } else { x = 2; false }) => 0
                    case _ => x
                }
            }
            """)
    }

    @TestCase
    public func IteratorCallsCanThrowBeforeBodyAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            func read(xs: Iterable<Int64>): Int64 {
                var x: Int64
                try { for (i in xs) {}; x = 7 } catch (e: Exception) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func IteratorExceptionCatchInitializesNormalExit(): Unit {
        ExpectInitializationAccepted("""
            func read(xs: Iterable<Int64>): Int64 {
                var x: Int64
                try { for (i in xs) {}; x = 7 } catch (e: Exception) { x = 9 }
                return x
            }
            """)
    }

    @TestCase
    public func BarePropertyGetterCanThrowBeforeAssignment(): Unit {
        ExpectInitializationDiagnostic("""
            class Value {
                prop p: Int64 { get() { throw Exception() } }
                func read(): Int64 {
                    var x: Int64
                    try { let v = p; x = 7 } catch (e: Exception) {}
                    return x // expected-init-error
                }
            }
            """)
    }

    @TestCase
    public func QualifiedPropertyGetterHasSameExceptionEdge(): Unit {
        ExpectInitializationDiagnostic("""
            class Value {
                prop p: Int64 { get() { throw Exception() } }
                func read(): Int64 {
                    var x: Int64
                    try { let v = this.p; x = 7 } catch (e: Exception) {}
                    return x // expected-init-error
                }
            }
            """)
    }

    @TestCase
    public func NestedExhaustiveCatchesConsumeRemainingExceptionDomain(): Unit {
        ExpectInitializationAccepted("""
            func mayThrow(): Unit { throw Exception() }
            func read(): Int64 {
                var x: Int64
                try {
                    try { mayThrow(); x = 1 }
                    catch (e: Exception) { x = 2 }
                    finally {}
                } catch (e: Error) { x = 3 }
                finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func SeparateExhaustiveCatchesConsumeImplicitException(): Unit {
        ExpectInitializationAccepted("""
            func mayThrow(): Unit { throw Exception() }
            func read(): Int64 {
                var x: Int64
                try { mayThrow(); x = 1 }
                catch (e: Exception) { x = 2 }
                catch (e: Error) { x = 3 }
                finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func PartialCatchRetainsUncaughtErrorForFinally(): Unit {
        ExpectInitializationDiagnostic("""
            func mayThrow(): Unit { throw Exception() }
            func read(): Int64 {
                var x: Int64
                try { mayThrow(); x = 1 }
                catch (e: Exception) { x = 2 }
                finally { let observed = x } // expected-init-error
                return x
            }
            """)
    }

    @TestCase
    public func DefaultIntegerOverflowCanReachCatch(): Unit {
        ExpectInitializationDiagnostic("""
            func read(a: Int64): Int64 {
                var x: Int64
                try { let v = a + 1; x = 7 } catch (e: Exception) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func DefaultNarrowingCanReachCatch(): Unit {
        ExpectInitializationDiagnostic("""
            func read(a: Int64): Int64 {
                var x: Int64
                try { let v = Int8(a); x = 7 } catch (e: Exception) {}
                return x // expected-init-error
            }
            """)
    }

    @TestCase
    public func IntegerComparisonDoesNotInventOverflowException(): Unit {
        ExpectInitializationAccepted("""
            func read(a: Int64): Int64 {
                var x: Int64
                try { let v = a < 1; x = 7 } finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func WrappingAnnotationHasNoOverflowException(): Unit {
        ExpectInitializationAccepted("""
            @OverflowWrapping
            func read(a: Int64): Int64 {
                var x: Int64
                try { let v = a + 1; x = 7 } finally { let observed = x }
                return x
            }
            """)
    }

    @TestCase
    public func NestedThrowingAnnotationOverridesWrapping(): Unit {
        ExpectInitializationDiagnostic("""
            @OverflowWrapping
            func outer(): Unit {
                @OverflowThrowing
                func read(a: Int64): Int64 {
                    var x: Int64
                    try { let v = a + 1; x = 7 } catch (e: Exception) {}
                    return x // expected-init-error
                }
            }
            """)
    }

    @TestCase
    public func CatchBindingsAreInitializedForEachCatch(): Unit {
        ExpectInitializationAccepted("""
            func read(): Int64 {
                let x: Int64
                try { throw Exception() }
                catch (first: IllegalArgumentException) {
                    let seen = first
                    x = 1
                } catch (second: Exception) {
                    let seen = second
                    x = 2
                }
                return x
            }
            """)
    }
}
