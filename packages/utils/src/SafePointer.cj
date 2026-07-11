package cjcj::utils

public class NullPointerException <: Exception {
    public let triggerPoint: Int64

    public init() {
        super("Dereferencing a null pointer")
        triggerPoint = ICE.GetTriggerPoint()
    }

    public func GetTriggerPoint(): Int64 {
        return triggerPoint
    }
}

public interface Identifiable {
    prop objectId: Int64
}

public class Ptr<T> {
    private var ptr: Option<T>

    public init() {
        ptr = None
    }

    public init(value: Option<T>) {
        ptr = value
    }

    public init(value: T) {
        ptr = value
    }

    public func get(): Option<T> {
        return ptr
    }

    public func getOrThrow(): T {
        if (let Some(value) <- ptr) {
            return value
        }
        throw NullPointerException()
    }

    public func isNull(): Bool {
        return ptr.isNone()
    }

    public func isSome(): Bool {
        return ptr.isSome()
    }

}

public class OwnedPtr<T> {
    private var origin: Option<T>

    public init() {
        origin = None
    }

    public init(value: Option<T>) {
        origin = value
    }

    public init(value: T) {
        origin = value
    }

    public func get(): Ptr<T> {
        return Ptr<T>(origin)
    }

    public func getOrThrow(): T {
        return get().getOrThrow()
    }

    public func reset(value!: Option<T> = None): Unit {
        origin = value
    }

    public func release(): Option<T> {
        let oldValue = origin
        origin = None
        return oldValue
    }

    public func isNull(): Bool {
        return origin.isNone()
    }

    public func isSome(): Bool {
        return origin.isSome()
    }
}

public func MakeOwned<T>(value: T): OwnedPtr<T> {
    return OwnedPtr<T>(Some(value))
}

public func StaticPointerCast<T>(ptr: OwnedPtr<T>): OwnedPtr<T> {
    return ptr
}

public func Swap<T>(one: OwnedPtr<T>, other: OwnedPtr<T>): Unit {
    let oneValue = one.release()
    let otherValue = other.release()
    one.reset(value: otherValue)
    other.reset(value: oneValue)
}
