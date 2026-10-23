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
