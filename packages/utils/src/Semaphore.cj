package cangjie_compiler::utils

import std.sync.*

public class Semaphore {
    private static let singleton: Semaphore = Semaphore(1)
    private let mutex = Mutex()
    private let condition: Condition
    private var count: Int64

    private init(initial: Int64) {
        count = initial
        synchronized(mutex) {
            condition = mutex.condition()
        }
    }

    public static func Get(): Semaphore {
        return singleton
    }

    public func Release(): Unit {
        synchronized(mutex) {
            count++
            condition.notify()
        }
    }

    public func Acquire(): Unit {
        synchronized(mutex) {
            while (count <= 0) {
                condition.wait()
            }
            count--
        }
    }

    public func SetCount(newCount: Int64): Unit {
        synchronized(mutex) {
            count = newCount
            condition.notifyAll()
        }
    }

    public func GetCount(): Int64 {
        synchronized(mutex) {
            return count
        }
    }
}

