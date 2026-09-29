package cjcj::mangle

import cjcj::ast.*
import std.sync.*

// Test-build-only scheduler. It never changes a source/target type or cache.
public class MangleOwnershipRace {
    private static let mutex = Mutex()
    private static let changed = NewCondition()
    private static var watched: Option<Ty> = None
    private static var firstTarget: Option<MangleType> = None
    private static var secondTarget: Option<MangleType> = None
    private static var firstAdapter: Option<MangleAstAdapter> = None
    private static var enabled = false
    private static var published = false
    private static var released = false
    private static var secondConsumed = false
    private static var secondName = ""

    private static func NewCondition(): Condition {
        synchronized(mutex) { return mutex.condition() }
    }

    public static func Configure(source: Ty, workers: Int64): Unit {
        synchronized(mutex) {
            watched = source
            enabled = workers > 1
            println("MANGLE_RACE configured source=${source.objectId} enabled=${enabled}")
        }
    }

    public static func BeforeMacro(name: String): Unit {
        synchronized(mutex) {
            if (!enabled || name != "RaceB") { return }
            while (!published) { changed.wait() }
            println("MANGLE_RACE second-after-publication")
        }
    }

    public static func AfterStore(adapter: MangleAstAdapter, source: Ty, target: MangleType): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            if (let Some(expected) <- watched) {
                if (!refEq(expected, source)) { return }
            } else { return }
            if (!published) {
                firstTarget = target
                firstAdapter = adapter
                published = true
                println("MANGLE_RACE published source=${source.objectId} targetDecl=${target.decl.isSome()}")
                changed.notifyAll()
                while (!released) { changed.wait() }
                println("MANGLE_RACE first-resumed")
            } else {
                secondTarget = target
                if (let Some(first) <- firstAdapter) {
                    println("MANGLE_RACE second-store sameAdapter=${refEq(first, adapter)}")
                }
            }
        }
    }

    public static func Consume(target: MangleType): Unit {
        synchronized(mutex) {
            if (!enabled || !published || released) { return }
            var selected = false
            if (let Some(first) <- firstTarget) { selected = refEq(first, target) }
            let cachedFirst = selected
            if (let Some(second) <- secondTarget) { selected = selected || refEq(second, target) }
            if (!selected) { return }
            secondConsumed = true
            println("MANGLE_CONSUMER cachedFirst=${cachedFirst}")
            // The caller consumes this exact value with MangleSemaType next.
            // Keep its original missing-declaration exception as the red result.
            println("MANGLE_INVARIANT sourceDecl=true consumerDecl=${target.decl.isSome()} kind=${TypeKindName(target.kind)}")
        }
    }

    public static func MacroResult(name: String, mangled: String): Unit {
        synchronized(mutex) {
            println("MANGLE_RESULT macro=${name} mangled=${mangled}")
            if (name == "RaceB") { secondName = mangled }
        }
    }

    public static func Release(name: String): Unit {
        synchronized(mutex) {
            if (!enabled || name != "RaceB") { return }
            released = true
            changed.notifyAll()
            println("MANGLE_RACE second-finally-release")
        }
    }

    public static func Finish(): Unit {
        synchronized(mutex) {
            if (!enabled) { return }
            println("MANGLE_ASSERT consumed=${secondConsumed} name=${secondName}")
            if (!published || !released || !secondConsumed || secondName.isEmpty()) {
                throw IllegalStateException("MANGLE_FIXTURE_INCOMPLETE")
            }
        }
    }
}
