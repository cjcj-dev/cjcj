package cjcj::chir

import std.collection.*

public class InterpreterArena {
    // Mirrors C++ InterpreterArena.h:22-23.
    public let finalizingObjects: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()
    private let values: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()

    public init() {}

    public func Allocate(value: InterpreterValue): InterpreterValue {
        values.add(value.Clone())
        return InterpreterValue.MakePointer(values.size - 1)
    }

    public func Get(index: Int64): Option<InterpreterValue> {
        if (index < 0 || index >= values.size) {
            return None
        }
        return values[index]
    }

    public func Set(index: Int64, value: InterpreterValue): Bool {
        if (index < 0 || index >= values.size) {
            return false
        }
        values[index] = value.Clone()
        return true
    }

    public func Size(): Int64 {
        return values.size
    }

    public func Clear(): Unit {
        values.clear()
    }
}
