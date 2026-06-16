package cangjie_compiler::utils

import std.sync.*

@When[os == "Linux"]
private let SC_NPROCESSORS_ONLN: Int32 = 84

@When[os == "macOS"]
private let SC_NPROCESSORS_ONLN: Int32 = 58

@When[os == "Linux" || os == "macOS"]
foreign {
    func sysconf(name: Int32): IntNative
}

@When[os == "Linux" || os == "macOS"]
private func hardwareConcurrency(): Int64 {
    let value = unsafe { sysconf(SC_NPROCESSORS_ONLN) }
    return if (value > 0) { Int64(value) } else { 0 }
}

@When[os != "Linux" && os != "macOS"]
private func hardwareConcurrency(): Int64 {
    return 1
}

private func defaultSemaphoreCount(): Int64 {
    let numCores = hardwareConcurrency()
    return if (numCores > 2) { numCores - 2 } else { 1 }
}

public class Semaphore {
    private static let singleton: Semaphore = Semaphore(defaultSemaphoreCount())
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
