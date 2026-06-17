package cangjie_compiler::chir

import std.collection.*

public class InterpreterEnv {
    private let globalValues: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()
    private let localValues: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()
    private var basePointer: Int64 = 0

    public init(numberOfGlobals: Int64) {
        var idx: Int64 = 0
        while (idx < numberOfGlobals) {
            globalValues.add(InterpreterValue.MakeInvalid())
            idx++
        }
    }

    public func SetLocal(index: Int64, value: InterpreterValue): Bool {
        let realIndex = basePointer + index
        if (realIndex < 0) {
            return false
        }
        EnsureLocalSize(realIndex + 1)
        localValues[realIndex] = value.Clone()
        return true
    }

    public func AllocateLocalVarsForFrame(number: Int64): Unit {
        var idx: Int64 = 0
        while (idx < number) {
            localValues.add(InterpreterValue.MakeInvalid())
            idx++
        }
    }

    public func SetGlobal(index: Int64, value: InterpreterValue): Bool {
        if (index < 0) {
            return false
        }
        EnsureGlobalSize(index + 1)
        globalValues[index] = value.Clone()
        return true
    }

    public func GetLocal(index: Int64): InterpreterValue {
        let realIndex = basePointer + index
        if (realIndex < 0 || realIndex >= localValues.size) {
            return InterpreterValue.MakeInvalid()
        }
        return localValues[realIndex]
    }

    public func GetGlobal(index: Int64): InterpreterValue {
        if (index < 0 || index >= globalValues.size) {
            return InterpreterValue.MakeInvalid()
        }
        return globalValues[index]
    }

    public func IsGlobalIndexValid(index: Int64): Bool {
        return index >= 0 && index < globalValues.size
    }

    public func StartStackFrame(): Unit {
        basePointer = localValues.size
    }

    public func RestoreStackFrameTo(newBasePointer: Int64): Unit {
        if (newBasePointer < 0 || newBasePointer > localValues.size) {
            return
        }
        while (localValues.size > basePointer) {
            localValues.remove(at: localValues.size - 1)
        }
        basePointer = newBasePointer
    }

    public func GetBP(): Int64 {
        return basePointer
    }

    public func GetNumGlobals(): Int64 {
        return globalValues.size
    }

    private func EnsureLocalSize(size: Int64): Unit {
        while (localValues.size < size) {
            localValues.add(InterpreterValue.MakeInvalid())
        }
    }

    private func EnsureGlobalSize(size: Int64): Unit {
        while (globalValues.size < size) {
            globalValues.add(InterpreterValue.MakeInvalid())
        }
    }
}
