package cjcj::mangle

import cjcj::ast.*
import std.sync.*
import std.time.*

// Test-build-only scheduler. It never changes a source/target type, a cache
// result or a declaration; it only orders two real mangling tasks and records
// which task did what. The consumer is bound to the qualified second task by a
// thread-local entry name, so "some task printed a complete declaration" can
// never satisfy the assertion.
public class MangleOwnershipRace {
    private static let mutex = Mutex()
    private static let changed = NewCondition()
    // Identity of the real mangling task currently running on this thread.
    private static let currentEntry = ThreadLocal<String>()
    private static var firstIndex: Int64 = -1
    private static var secondIndex: Int64 = -1
    private static var secondReady = false
    private static var active = false
    private static var finished = false
    private static var watched: Option<Ty> = None
    private static var firstEntry = ""
    private static var secondEntry = ""
    private static var enabled = false
    private static var published = false
    private static var released = false
    private static var firstTarget: Option<MangleType> = None
    private static var firstAdapter: Option<MangleAstAdapter> = None
    private static var firstTask = ""
    private static var secondTask = ""
    private static var secondConsumed = false
    private static var secondCachedFirst = false
    private static var secondHasDecl = true
    private static var secondName = ""
    private static var waitExpired = false

    private static func NewCondition(): Condition {
        synchronized(mutex) { return mutex.condition() }
    }

    public static func Configure(source: Ty, workers: Int64, first: String, second: String, firstTop: Int64, secondTop: Int64): Unit {
        synchronized(mutex) {
            firstIndex = firstTop
            secondIndex = secondTop
            watched = source
            firstEntry = first
            secondEntry = second
            enabled = workers > 1
            println("MANGLE_RACE configured source=${source.objectId} enabled=${enabled} first=${first} second=${second}")
        }
    }

    // Gate entire real top-level walks, including prefix conversion and cache
    // release. Run both batch prefixes without overlap, park the consumer at
    // its qualified index, then let the producer publish. Other batches cannot
    // populate or clear the shared adapter during this two-task window.
    public static func BeginTop(index: Int64): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            if (index == secondIndex) {
                secondReady = true
                changed.notifyAll()
                while (!published) { Await("consumer-ready") }
                println("MANGLE_SCHEDULE consumer index=${index}")
                return
            }
            let prefix = (index / 30 == firstIndex / 30 && index <= firstIndex) ||
                (index / 30 == secondIndex / 30 && index < secondIndex)
            while (active || (!prefix && !finished) || (index == firstIndex && !secondReady)) {
                Await("top-entry")
            }
            active = true
            println("MANGLE_SCHEDULE enter index=${index}")
        }
    }

    public static func EndTop(index: Int64): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            if (index == secondIndex) {
                released = true
                println("MANGLE_RACE second-finally-release entry=${secondEntry}")
            } else {
                active = false
                if (index == firstIndex) { finished = true }
            }
            changed.notifyAll()
        }
    }

    private static func Await(point: String): Unit {
        if (!changed.wait(timeout: Duration.minute)) {
            waitExpired = true
            println("MANGLE_RACE schedule-timeout point=${point}")
            throw IllegalStateException("MANGLE_FIXTURE_INCOMPLETE")
        }
    }

    public static func EnterTask(name: String): Unit {
        currentEntry.set(Some(name))
    }

    public static func LeaveTask(): Unit {
        currentEntry.set(None)
    }

    // Real StoreTy has just published the target copy; the Class declaration is
    // not bound yet. Hold the window open and name the publishing task.
    public static func AfterStore(adapter: MangleAstAdapter, source: Ty, target: MangleType): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            if (let Some(expected) <- watched) {
                if (!refEq(expected, source)) { return }
            } else { return }
            let task = TaskName()
            if (!published && task == firstEntry) {
                firstTarget = target
                firstAdapter = adapter
                firstTask = task
                published = true
                println("MANGLE_RACE published entry=${task} source=${source.objectId} targetDecl=${target.decl.isSome()}")
                changed.notifyAll()
                while (!released) {
                    if (!changed.wait(timeout: Duration.minute)) {
                        waitExpired = true
                        println("MANGLE_RACE first-wait-timeout entry=${task}")
                        return
                    }
                }
                println("MANGLE_RACE first-resumed entry=${task}")
            } else if (published) {
                var same = false
                if (let Some(first) <- firstAdapter) { same = refEq(first, adapter) }
                println("MANGLE_RACE second-store entry=${task} sameAdapter=${same}")
            }
        }
    }

    // Real MangleFuncParams consumer. Only the qualified second task counts.
    public static func Consume(target: MangleType): Unit {
        synchronized(mutex) {
            if (!enabled || !published || released) { return }
            let task = TaskName()
            if (task != secondEntry) {
                println("MANGLE_CONSUMER ignored entry=${task}")
                return
            }
            secondTask = task
            secondConsumed = true
            var cachedFirst = false
            if (let Some(first) <- firstTarget) { cachedFirst = refEq(first, target) }
            secondCachedFirst = cachedFirst
            secondHasDecl = target.decl.isSome()
            println("MANGLE_CONSUMER entry=${task} cachedFirst=${cachedFirst} consumerDecl=${secondHasDecl} kind=${TypeKindName(target.kind)}")
        }
    }

    public static func EntryResult(name: String, mangled: String): Unit {
        synchronized(mutex) {
            if (name == secondEntry) {
                secondName = mangled
                println("MANGLE_RESULT entry=${name} mangled=${mangled}")
            }
        }
    }

    public static func Finish(): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            println("MANGLE_ASSERT consumed=${secondConsumed} entry=${secondTask} cachedFirst=${secondCachedFirst} consumerDecl=${secondHasDecl} name=${secondName}")
            println("MANGLE_ASSERT publisher=${firstTask} qualifiedFirst=${firstEntry} waitExpired=${waitExpired}")
            if (!published || !released || !secondConsumed || secondCachedFirst || !secondHasDecl ||
                secondName.isEmpty() || waitExpired || firstTask != firstEntry || secondTask != secondEntry) {
                throw IllegalStateException("MANGLE_FIXTURE_INCOMPLETE")
            }
        }
    }

    private static func TaskName(): String {
        if (let Some(name) <- currentEntry.get()) { return name }
        return "<none>"
    }
}
