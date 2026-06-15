package cangjie_compiler::chir

import std.collection.*

public class ControlState {
    public let opCode: OpCode
    public let argStackPtr: Int64
    public let byteCodePtr: Int64
    public let envBP: Int64

    public init(opCode: OpCode, argStackPtr: Int64, byteCodePtr: Int64, envBP: Int64) {
        this.opCode = opCode
        this.argStackPtr = argStackPtr
        this.byteCodePtr = byteCodePtr
        this.envBP = envBP
    }
}

public class InterpreterStack {
    private let argStack: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()
    private let controlStack: ArrayList<ControlState> = ArrayList<ControlState>()

    public init() {}

    public func ArgsPush(value: InterpreterValue): Unit {
        argStack.add(value.Clone())
    }

    public func ArgsPopIVal(): InterpreterValue {
        if (argStack.isEmpty()) {
            return InterpreterValue.MakeInvalid()
        }
        let lastIndex = argStack.size - 1
        let value = argStack[lastIndex]
        argStack.remove(at: lastIndex)
        return value
    }

    public func ArgsTopIVal(): InterpreterValue {
        if (argStack.isEmpty()) {
            return InterpreterValue.MakeInvalid()
        }
        return argStack[argStack.size - 1]
    }

    public func ArgsPopBack(): Unit {
        if (!argStack.isEmpty()) {
            argStack.remove(at: argStack.size - 1)
        }
    }

    public func ArgsPop(count: Int64): ArrayList<InterpreterValue> {
        let out = ArrayList<InterpreterValue>()
        var remaining = count
        while (remaining > 0 && !argStack.isEmpty()) {
            out.add(ArgsPopIVal())
            remaining--
        }
        ReverseValues(out)
        return out
    }

    public func ArgsRemove(count: Int64): Unit {
        var remaining = count
        while (remaining > 0 && !argStack.isEmpty()) {
            ArgsPopBack()
            remaining--
        }
    }

    public func ArgsRemoveAfter(count: Int64): Unit {
        while (argStack.size > count) {
            ArgsPopBack()
        }
    }

    public func ArgsGet(index: Int64): InterpreterValue {
        if (index < 0 || index >= argStack.size) {
            return InterpreterValue.MakeInvalid()
        }
        return argStack[index]
    }

    public func ArgsGet(offsetFromEnd: Int64, index: Int64): InterpreterValue {
        let realIndex = (argStack.size - offsetFromEnd) + index
        return ArgsGet(realIndex)
    }

    public func ArgsSwapFromEnd(left: Int64, right: Int64, offsetFromEnd: Int64): Bool {
        let leftIndex = (argStack.size - offsetFromEnd) + left
        let rightIndex = (argStack.size - offsetFromEnd) + right
        if (leftIndex < 0 || rightIndex < 0 || leftIndex >= argStack.size || rightIndex >= argStack.size) {
            return false
        }
        let tmp = argStack[leftIndex]
        argStack[leftIndex] = argStack[rightIndex]
        argStack[rightIndex] = tmp
        return true
    }

    public func ArgsSize(): Int64 {
        return argStack.size
    }

    public func ArgsClear(): Unit {
        argStack.clear()
    }

    public func CtrlPush(state: ControlState): Unit {
        controlStack.add(state)
    }

    public func CtrlPop(): Option<ControlState> {
        if (controlStack.isEmpty()) {
            return None
        }
        let lastIndex = controlStack.size - 1
        let state = controlStack[lastIndex]
        controlStack.remove(at: lastIndex)
        return state
    }

    public func CtrlTop(): Option<ControlState> {
        if (controlStack.isEmpty()) {
            return None
        }
        return controlStack[controlStack.size - 1]
    }

    public func CtrlDrop(): Unit {
        if (!controlStack.isEmpty()) {
            controlStack.remove(at: controlStack.size - 1)
        }
    }

    public func CtrlIsEmpty(): Bool {
        return controlStack.isEmpty()
    }

    public func CtrlSize(): Int64 {
        return controlStack.size
    }

    public func GetCtrlStack(): ArrayList<ControlState> {
        let out = ArrayList<ControlState>()
        for (state in controlStack) {
            out.add(state)
        }
        return out
    }
}

private func ReverseValues(values: ArrayList<InterpreterValue>): Unit {
    var left: Int64 = 0
    var right: Int64 = values.size - 1
    while (left < right) {
        let tmp = values[left]
        values[left] = values[right]
        values[right] = tmp
        left++
        right--
    }
}
