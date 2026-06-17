package cangjie_compiler::chir

import std.collection.*

public class BCHIRInterpreter {
    private let bchir: BCHIR
    private let interpStack: InterpreterStack = InterpreterStack()
    private let arena: InterpreterArena = InterpreterArena()
    private let env: InterpreterEnv
    private var lastResult: BCHIRResult = BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "not run")

    public init(bchir: BCHIR) {
        this.bchir = bchir
        this.env = InterpreterEnv(bchir.GetNumGlobalVars())
    }

    public func Run(baseIndex!: Int64 = 0, expectsReturn!: Bool = true): BCHIRResult {
        interpStack.ArgsClear()
        var pc = baseIndex
        let code = bchir.GetLinkedByteCode()
        while (pc >= 0 && pc < code.Size()) {
            let opCode = OpCodeFromIndex(code.Get(pc))
            if (IsSmallIntOp(opCode)) {
                interpStack.ArgsPush(InterpreterValue.MakeInt(IntOpKind(opCode), code.Get(pc + 1)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.INT64 || opCode == OpCode.INTNAT) {
                interpStack.ArgsPush(InterpreterValue.MakeInt(IntOpKind(opCode), code.Get8Bytes(pc + 1)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (IsSmallUIntOp(opCode)) {
                interpStack.ArgsPush(InterpreterValue.MakeUInt(UIntOpKind(opCode), code.Get(pc + 1)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.UINT64 || opCode == OpCode.UINTNAT) {
                interpStack.ArgsPush(InterpreterValue.MakeUInt(UIntOpKind(opCode), code.Get8Bytes(pc + 1)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.FLOAT16 || opCode == OpCode.FLOAT32) {
                interpStack.ArgsPush(InterpreterValue.MakeFloat(FloatOpKind(opCode), Float64(code.Get(pc + 1))))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.FLOAT64) {
                interpStack.ArgsPush(InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT64, Float64(code.Get8Bytes(pc + 1))))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.BOOL) {
                interpStack.ArgsPush(InterpreterValue.MakeBool(code.Get(pc + 1) != 0))
                pc += 2
            } else if (opCode == OpCode.UNIT) {
                interpStack.ArgsPush(InterpreterValue.MakeUnit())
                pc += 1
            } else if (opCode == OpCode.NULLPTR) {
                interpStack.ArgsPush(InterpreterValue.MakeNull())
                pc += 1
            } else if (opCode == OpCode.STRING) {
                interpStack.ArgsPush(InterpreterValue.MakeString(bchir.GetString(code.Get(pc + 1))))
                pc += 2
            } else if (opCode == OpCode.FUNC) {
                interpStack.ArgsPush(InterpreterValue.MakeFunction(code.Get(pc + 1)))
                pc += 2
            } else if (opCode == OpCode.TUPLE) {
                interpStack.ArgsPush(InterpreterValue.MakeTuple(interpStack.ArgsPop(code.Get(pc + 1))))
                pc += 2
            } else if (opCode == OpCode.ARRAY || opCode == OpCode.VARRAY) {
                interpStack.ArgsPush(InterpreterValue.MakeArray(interpStack.ArgsPop(code.Get(pc + 1))))
                pc += 2
            } else if (opCode == OpCode.ALLOCATE_RAW_ARRAY || opCode == OpCode.ALLOCATE_RAW_ARRAY_EXC) {
                let sizeValue = interpStack.ArgsPopIVal()
                if (!sizeValue.IsIntLike()) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "raw array size is not an integer"))
                }
                let size = sizeValue.GetInt()
                if (size < 0) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "negative raw array size"))
                }
                let items = ArrayList<InterpreterValue>()
                items.add(InterpreterValue.MakeInt(InterpreterValueKind.IINT64, size))
                var itemIdx: Int64 = 0
                while (itemIdx < size) {
                    items.add(InterpreterValue.MakeNull())
                    itemIdx++
                }
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeArray(items)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.ALLOCATE_RAW_ARRAY_LITERAL ||
                opCode == OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC) {
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeArray(interpStack.ArgsPop(code.Get(pc + 1)))))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.RAW_ARRAY_LITERAL_INIT) {
                if (!RawArrayLiteralInit(code.Get(pc + 1))) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid raw array literal init"))
                }
                pc += 2
            } else if (opCode == OpCode.ALLOCATE_STRUCT || opCode == OpCode.ALLOCATE_STRUCT_EXC) {
                let fields = ArrayList<InterpreterValue>()
                var fieldIdx: Int64 = 0
                while (fieldIdx < code.Get(pc + 1)) {
                    fields.add(InterpreterValue.MakeNull())
                    fieldIdx++
                }
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeTuple(fields)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.ALLOCATE_CLASS || opCode == OpCode.ALLOCATE_CLASS_EXC) {
                let classId = code.Get(pc + 1)
                let fieldCount = code.Get(pc + 2)
                let fields = ArrayList<InterpreterValue>()
                var fieldIdx: Int64 = 0
                while (fieldIdx < fieldCount) {
                    fields.add(InterpreterValue.MakeNull())
                    fieldIdx++
                }
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeObject(classId, fields)))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.ALLOCATE || opCode == OpCode.ALLOCATE_EXC) {
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeNull()))
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.FRAME) {
                env.StartStackFrame()
                env.AllocateLocalVarsForFrame(code.Get(pc + 1))
                pc += 2
            } else if (opCode == OpCode.LVAR) {
                interpStack.ArgsPush(env.GetLocal(code.Get(pc + 1)))
                pc += 2
            } else if (opCode == OpCode.GVAR) {
                interpStack.ArgsPush(InterpreterValue.MakeGlobalPointer(code.Get(pc + 1)))
                pc += 2
            } else if (opCode == OpCode.LVAR_SET) {
                let ok = env.SetLocal(code.Get(pc + 1), interpStack.ArgsPopIVal())
                if (!ok) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid local variable index"))
                }
                pc += 2
            } else if (opCode == OpCode.GVAR_SET) {
                let ok = env.SetGlobal(code.Get(pc + 1), interpStack.ArgsPopIVal())
                if (!ok) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid global variable index"))
                }
                pc += 2
            } else if (opCode == OpCode.DROP) {
                interpStack.ArgsPopBack()
                pc += 1
            } else if (opCode == OpCode.STORE) {
                let pointer = interpStack.ArgsPopIVal()
                let value = interpStack.ArgsPopIVal()
                if (!StoreThroughPointer(pointer, value)) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid STORE target"))
                }
                pc += 1
            } else if (opCode == OpCode.JUMP) {
                pc = code.Get(pc + 1)
            } else if (opCode == OpCode.BRANCH) {
                let condition = interpStack.ArgsPopIVal()
                pc = if (IValUtils.IsTruthy(condition)) { code.Get(pc + 1) } else { code.Get(pc + 2) }
            } else if (opCode == OpCode.APPLY || opCode == OpCode.APPLY_EXC) {
                let argCount = code.Get(pc + 1)
                if (argCount <= 0 || interpStack.ArgsSize() < argCount) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid APPLY argument count"))
                }
                let functionValue = interpStack.ArgsGet(argCount, 0)
                if (functionValue.kind != InterpreterValueKind.IFUNC) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "APPLY target is not a function"))
                }
                interpStack.CtrlPush(ControlState(opCode, interpStack.ArgsSize() - argCount,
                    pc + 1 + GetOpCodeArgSize(opCode), env.GetBP()))
                pc = functionValue.GetFunctionIndex()
            } else if (opCode == OpCode.ASG) {
                let pointer = interpStack.ArgsPopIVal()
                let value = interpStack.ArgsPopIVal()
                if (!StoreThroughPointer(pointer, value)) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid ASG target"))
                }
                interpStack.ArgsPush(InterpreterValue.MakeUnit())
                pc += 1
            } else if (opCode == OpCode.DEREF) {
                if (let Some(value) <- DereferencePointer(interpStack.ArgsPopIVal())) {
                    interpStack.ArgsPush(value)
                    pc += 1
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid DEREF target"))
                }
            } else if (opCode == OpCode.GETREF) {
                let target = interpStack.ArgsPopIVal()
                if (target.kind != InterpreterValueKind.IPOINTER) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "GETREF target is not a pointer"))
                }
                interpStack.ArgsPush(PointerWithCodePath(target, pc + 2, code.Get(pc + 1)))
                pc += 2 + code.Get(pc + 1)
            } else if (opCode == OpCode.STOREINREF) {
                let target = interpStack.ArgsPopIVal()
                let value = interpStack.ArgsPopIVal()
                if (target.kind != InterpreterValueKind.IPOINTER) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "STOREINREF target is not a pointer"))
                }
                if (!StoreThroughPointer(PointerWithCodePath(target, pc + 2, code.Get(pc + 1)), value)) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid STOREINREF path"))
                }
                interpStack.ArgsPush(InterpreterValue.MakeUnit())
                pc += 2 + code.Get(pc + 1)
            } else if (opCode == OpCode.FIELD) {
                if (let Some(fieldValue) <- FieldValue(interpStack.ArgsPopIVal(), code.Get(pc + 1))) {
                    interpStack.ArgsPush(fieldValue)
                    pc += 2
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid FIELD path"))
                }
            } else if (opCode == OpCode.FIELD_TPL) {
                if (let Some(fieldValue) <- TuplePathValue(interpStack.ArgsPopIVal(), pc + 2, code.Get(pc + 1))) {
                    interpStack.ArgsPush(fieldValue)
                    pc += 2 + code.Get(pc + 1)
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid FIELD_TPL path"))
                }
            } else if (opCode == OpCode.BOX) {
                let fields = ArrayList<InterpreterValue>()
                fields.add(interpStack.ArgsPopIVal())
                interpStack.ArgsPush(arena.Allocate(InterpreterValue.MakeObject(code.Get(pc + 1), fields)))
                pc += 2
            } else if (opCode == OpCode.UNBOX) {
                if (let Some(value) <- UnboxValue(interpStack.ArgsPopIVal())) {
                    interpStack.ArgsPush(value)
                    pc += 1
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid UNBOX target"))
                }
            } else if (opCode == OpCode.UNBOX_REF) {
                let boxed = interpStack.ArgsPopIVal()
                if (boxed.kind != InterpreterValueKind.IPOINTER) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "UNBOX_REF target is not a pointer"))
                }
                let path = boxed.GetPointerPath()
                path.add(0)
                interpStack.ArgsPush(InterpreterValue.MakePointerWithPath(boxed.GetPointerRootKind(),
                    boxed.GetPointerIndex(), path))
                pc += 1
            } else if (opCode == OpCode.INSTANCEOF) {
                if (let Some(value) <- DereferencePointer(interpStack.ArgsPopIVal())) {
                    if (value.kind == InterpreterValueKind.IOBJECT) {
                        interpStack.ArgsPush(InterpreterValue.MakeBool(IsSubclass(value.GetClassId(), code.Get(pc + 1))))
                        pc += 2
                    } else {
                        return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "INSTANCEOF target is not an object"))
                    }
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid INSTANCEOF target"))
                }
            } else if (IsUnaryOp(opCode)) {
                if (!EvaluateUnary(opCode)) {
                    return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "unsupported unary op " +
                        GetOpCodeLabel(opCode)))
                }
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (IsBinaryOp(opCode)) {
                if (!EvaluateBinary(opCode)) {
                    return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "unsupported binary op " +
                        GetOpCodeLabel(opCode)))
                }
                pc += 1 + GetOpCodeArgSize(opCode)
            } else if (opCode == OpCode.RETURN) {
                let returnValue = if (interpStack.ArgsSize() == 0) { InterpreterValue.MakeUnit() } else { interpStack.ArgsPopIVal() }
                if (let Some(state) <- interpStack.CtrlPop()) {
                    env.RestoreStackFrameTo(state.envBP)
                    interpStack.ArgsRemoveAfter(state.argStackPtr)
                    interpStack.ArgsPush(returnValue)
                    pc = state.byteCodePtr
                } else {
                    if (!expectsReturn) {
                        return Finish(BCHIRResult(BCHIRResultKind.OK, value: UnitLiteral()))
                    }
                    return Finish(ValueToResult(returnValue))
                }
            } else if (opCode == OpCode.EXIT) {
                if (!expectsReturn || interpStack.ArgsSize() == 0) {
                    return Finish(BCHIRResult(BCHIRResultKind.OK, value: UnitLiteral()))
                }
                return Finish(ValueToResult(interpStack.ArgsPopIVal()))
            } else if (opCode == OpCode.NOT_SUPPORTED) {
                return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "bytecode marked not supported"))
            } else if (opCode == OpCode.ABORT || opCode == OpCode.INVALID) {
                return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid bytecode operation"))
            } else {
                return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "unsupported bytecode op " +
                    GetOpCodeLabel(opCode)))
            }
        }
        let result = if (expectsReturn && interpStack.ArgsSize() > 0) {
            ValueToResult(interpStack.ArgsPopIVal())
        } else {
            BCHIRResult(BCHIRResultKind.OK, value: UnitLiteral())
        }
        return Finish(result)
    }

    public func GetBCHIR(): BCHIR { return bchir }

    public func ToArena(value: InterpreterValue): InterpreterValue {
        return arena.Allocate(value)
    }

    public func PeekValueOfGlobal(index: Int64): InterpreterValue {
        return env.GetGlobal(index)
    }

    public func SetGlobalVar(index: Int64, value: InterpreterValue): Bool {
        return env.SetGlobal(index, value)
    }

    public func GetLastResult(): BCHIRResult {
        return lastResult
    }

    private func Finish(result: BCHIRResult): BCHIRResult {
        lastResult = result
        return result
    }

    private func DereferencePointer(pointer: InterpreterValue): Option<InterpreterValue> {
        if (pointer.kind != InterpreterValueKind.IPOINTER) {
            return None
        }
        if (let Some(root) <- PointerRootValue(pointer)) {
            return ReadValuePath(root, pointer.GetPointerPathRef())
        }
        return None
    }

    private func StoreThroughPointer(pointer: InterpreterValue, value: InterpreterValue): Bool {
        if (pointer.kind != InterpreterValueKind.IPOINTER) {
            return false
        }
        if (pointer.GetPointerPathRef().isEmpty()) {
            return StorePointerRootValue(pointer, value)
        }
        if (let Some(root) <- PointerRootValue(pointer)) {
            return WriteValuePath(root, pointer.GetPointerPathRef(), value)
        }
        return false
    }

    private func PointerRootValue(pointer: InterpreterValue): Option<InterpreterValue> {
        return match (pointer.GetPointerRootKind()) {
            case InterpreterPointerRootKind.PARENA => arena.Get(pointer.GetPointerIndex())
            case InterpreterPointerRootKind.PGLOBAL =>
                if (env.IsGlobalIndexValid(pointer.GetPointerIndex())) {
                    env.GetGlobal(pointer.GetPointerIndex())
                } else {
                    None
                }
            case InterpreterPointerRootKind.PINVALID => None
        }
    }

    private func StorePointerRootValue(pointer: InterpreterValue, value: InterpreterValue): Bool {
        return match (pointer.GetPointerRootKind()) {
            case InterpreterPointerRootKind.PARENA => arena.Set(pointer.GetPointerIndex(), value)
            case InterpreterPointerRootKind.PGLOBAL => env.SetGlobal(pointer.GetPointerIndex(), value)
            case InterpreterPointerRootKind.PINVALID => false
        }
    }

    private func ReadValuePath(root: InterpreterValue, path: ArrayList<Int64>): Option<InterpreterValue> {
        var current = root
        var pathIdx: Int64 = 0
        while (pathIdx < path.size) {
            let index = PathElementIndex(current, path[pathIdx])
            let elements = current.GetElementsRef()
            if (index < 0 || index >= elements.size) {
                return None
            }
            current = elements[index]
            pathIdx++
        }
        return current.Clone()
    }

    private func WriteValuePath(root: InterpreterValue, path: ArrayList<Int64>, value: InterpreterValue): Bool {
        if (path.isEmpty()) {
            return false
        }
        var current = root
        var pathIdx: Int64 = 0
        while (pathIdx + 1 < path.size) {
            let index = PathElementIndex(current, path[pathIdx])
            let elements = current.GetElementsRef()
            if (index < 0 || index >= elements.size) {
                return false
            }
            current = elements[index]
            pathIdx++
        }
        let finalIndex = PathElementIndex(current, path[path.size - 1])
        let finalElements = current.GetElementsRef()
        if (finalIndex < 0 || finalIndex >= finalElements.size) {
            return false
        }
        finalElements[finalIndex] = value.Clone()
        return true
    }

    private func PathElementIndex(container: InterpreterValue, rawIndex: Int64): Int64 {
        if (container.kind == InterpreterValueKind.IARRAY) {
            return rawIndex + 1
        }
        return rawIndex
    }

    private func PointerWithCodePath(pointer: InterpreterValue, firstPathCell: Int64, pathSize: Int64): InterpreterValue {
        let path = pointer.GetPointerPath()
        let code = bchir.GetLinkedByteCode()
        var pathIdx: Int64 = 0
        while (pathIdx < pathSize) {
            path.add(code.Get(firstPathCell + pathIdx))
            pathIdx++
        }
        return InterpreterValue.MakePointerWithPath(pointer.GetPointerRootKind(), pointer.GetPointerIndex(), path)
    }

    private func FieldValue(value: InterpreterValue, field: Int64): Option<InterpreterValue> {
        if (value.kind == InterpreterValueKind.ITUPLE) {
            let elements = value.GetElementsRef()
            if (field >= 0 && field < elements.size) {
                return elements[field].Clone()
            }
            return None
        }
        if (value.kind == InterpreterValueKind.IOBJECT) {
            let elements = value.GetElementsRef()
            let realField = field - 1
            if (realField >= 0 && realField < elements.size) {
                return elements[realField].Clone()
            }
            return None
        }
        return None
    }

    private func TuplePathValue(value: InterpreterValue, firstPathCell: Int64, pathSize: Int64): Option<InterpreterValue> {
        if (pathSize <= 0) {
            return None
        }
        var current = value
        let code = bchir.GetLinkedByteCode()
        var pathIdx: Int64 = 0
        while (pathIdx < pathSize) {
            if (current.kind != InterpreterValueKind.ITUPLE) {
                return None
            }
            let index = code.Get(firstPathCell + pathIdx)
            let elements = current.GetElementsRef()
            if (index < 0 || index >= elements.size) {
                return None
            }
            current = elements[index]
            pathIdx++
        }
        return current.Clone()
    }

    private func UnboxValue(pointer: InterpreterValue): Option<InterpreterValue> {
        if (let Some(boxed) <- DereferencePointer(pointer)) {
            if (boxed.kind == InterpreterValueKind.IOBJECT && boxed.GetElementsRef().size > 0) {
                return boxed.GetElementsRef()[0].Clone()
            }
        }
        return None
    }

    private func RawArrayLiteralInit(size: Int64): Bool {
        let values = interpStack.ArgsPop(size)
        let pointer = interpStack.ArgsPopIVal()
        if (let Some(arrayValue) <- DereferencePointer(pointer)) {
            if (arrayValue.kind != InterpreterValueKind.IARRAY) {
                return false
            }
        } else {
            return false
        }
        var idx: Int64 = 0
        while (idx < size) {
            let path = pointer.GetPointerPath()
            path.add(idx)
            if (!StoreThroughPointer(InterpreterValue.MakePointerWithPath(pointer.GetPointerRootKind(),
                pointer.GetPointerIndex(), path), values[idx])) {
                return false
            }
            idx++
        }
        interpStack.ArgsPush(InterpreterValue.MakeUnit())
        return true
    }

    private func IsSubclass(lhs: Int64, rhs: Int64): Bool {
        if (lhs == rhs) {
            return true
        }
        if (let Some(info) <- bchir.GetClass(lhs)) {
            for (superClass in info.superClasses) {
                if (superClass == rhs || IsSubclass(superClass, rhs)) {
                    return true
                }
            }
        }
        return false
    }

    private func ValueToResult(value: InterpreterValue): BCHIRResult {
        if (let Some(literal) <- IValUtils.ToLiteral(value)) {
            return BCHIRResult(BCHIRResultKind.OK, value: literal)
        }
        return BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "result is not a literal: " + IValUtils.ToString(value))
    }

    private func EvaluateUnary(opCode: OpCode): Bool {
        let operand = interpStack.ArgsPopIVal()
        if (operand.IsIntLike()) {
            let value = operand.GetInt()
            let result = match (opCode) {
                case OpCode.UN_NEG => InterpreterValue.MakeInt(operand.kind, -value)
                case OpCode.UN_NEG_EXC => InterpreterValue.MakeInt(operand.kind, -value)
                case OpCode.UN_BITNOT => InterpreterValue.MakeInt(operand.kind, -value - 1)
                case OpCode.UN_INC => InterpreterValue.MakeInt(operand.kind, value + 1)
                case OpCode.UN_DEC => InterpreterValue.MakeInt(operand.kind, value - 1)
                case _ => InterpreterValue.MakeInvalid()
            }
            if (!result.IsInvalid()) {
                interpStack.ArgsPush(result)
                return true
            }
        }
        if (operand.IsFloatLike() && (opCode == OpCode.UN_NEG || opCode == OpCode.UN_NEG_EXC)) {
            interpStack.ArgsPush(InterpreterValue.MakeFloat(operand.kind, -operand.GetFloat()))
            return true
        }
        if (operand.kind == InterpreterValueKind.IBOOL && opCode == OpCode.UN_NOT) {
            interpStack.ArgsPush(InterpreterValue.MakeBool(!operand.GetBool()))
            return true
        }
        return false
    }

    private func EvaluateBinary(opCode: OpCode): Bool {
        let right = interpStack.ArgsPopIVal()
        let left = interpStack.ArgsPopIVal()
        if (left.IsIntLike() && right.IsIntLike()) {
            return EvaluateIntBinary(opCode, left, right)
        }
        if (left.IsFloatLike() && right.IsFloatLike()) {
            return EvaluateFloatBinary(opCode, left, right)
        }
        if (left.kind == InterpreterValueKind.IBOOL && right.kind == InterpreterValueKind.IBOOL) {
            return EvaluateBoolBinary(opCode, left.GetBool(), right.GetBool())
        }
        if (left.kind == InterpreterValueKind.ISTRING && right.kind == InterpreterValueKind.ISTRING) {
            if (opCode == OpCode.BIN_EQUAL || opCode == OpCode.BIN_NOTEQ) {
                let equal = left.GetText() == right.GetText()
                interpStack.ArgsPush(InterpreterValue.MakeBool(if (opCode == OpCode.BIN_EQUAL) { equal } else { !equal }))
                return true
            }
        }
        if (opCode == OpCode.BIN_EQUAL || opCode == OpCode.BIN_NOTEQ) {
            let equal = IValUtils.Equals(left, right)
            interpStack.ArgsPush(InterpreterValue.MakeBool(if (opCode == OpCode.BIN_EQUAL) { equal } else { !equal }))
            return true
        }
        return false
    }

    private func EvaluateIntBinary(opCode: OpCode, left: InterpreterValue, right: InterpreterValue): Bool {
        let lhs = left.GetInt()
        let rhs = right.GetInt()
        let result = match (opCode) {
            case OpCode.BIN_ADD => InterpreterValue.MakeInt(left.kind, lhs + rhs)
            case OpCode.BIN_ADD_EXC => InterpreterValue.MakeInt(left.kind, lhs + rhs)
            case OpCode.BIN_SUB => InterpreterValue.MakeInt(left.kind, lhs - rhs)
            case OpCode.BIN_SUB_EXC => InterpreterValue.MakeInt(left.kind, lhs - rhs)
            case OpCode.BIN_MUL => InterpreterValue.MakeInt(left.kind, lhs * rhs)
            case OpCode.BIN_MUL_EXC => InterpreterValue.MakeInt(left.kind, lhs * rhs)
            case OpCode.BIN_DIV => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs / rhs) }
            case OpCode.BIN_DIV_EXC => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs / rhs) }
            case OpCode.BIN_MOD => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs % rhs) }
            case OpCode.BIN_MOD_EXC => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs % rhs) }
            case OpCode.BIN_EXP => IntPowValue(left.kind, lhs, rhs)
            case OpCode.BIN_EXP_EXC => IntPowValue(left.kind, lhs, rhs)
            case OpCode.BIN_BITAND => InterpreterValue.MakeInt(left.kind, lhs & rhs)
            case OpCode.BIN_BITOR => InterpreterValue.MakeInt(left.kind, lhs | rhs)
            case OpCode.BIN_BITXOR => InterpreterValue.MakeInt(left.kind, lhs ^ rhs)
            case OpCode.BIN_LSHIFT => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs << rhs) }
            case OpCode.BIN_LSHIFT_EXC => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs << rhs) }
            case OpCode.BIN_RSHIFT => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs >> rhs) }
            case OpCode.BIN_RSHIFT_EXC => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs >> rhs) }
            case OpCode.BIN_LT => InterpreterValue.MakeBool(lhs < rhs)
            case OpCode.BIN_GT => InterpreterValue.MakeBool(lhs > rhs)
            case OpCode.BIN_LE => InterpreterValue.MakeBool(lhs <= rhs)
            case OpCode.BIN_GE => InterpreterValue.MakeBool(lhs >= rhs)
            case OpCode.BIN_EQUAL => InterpreterValue.MakeBool(lhs == rhs)
            case OpCode.BIN_NOTEQ => InterpreterValue.MakeBool(lhs != rhs)
            case _ => InterpreterValue.MakeInvalid()
        }
        if (result.IsInvalid()) {
            return false
        }
        interpStack.ArgsPush(result)
        return true
    }

    private func EvaluateFloatBinary(opCode: OpCode, left: InterpreterValue, right: InterpreterValue): Bool {
        let lhs = left.GetFloat()
        let rhs = right.GetFloat()
        let result = match (opCode) {
            case OpCode.BIN_ADD => InterpreterValue.MakeFloat(left.kind, lhs + rhs)
            case OpCode.BIN_SUB => InterpreterValue.MakeFloat(left.kind, lhs - rhs)
            case OpCode.BIN_MUL => InterpreterValue.MakeFloat(left.kind, lhs * rhs)
            case OpCode.BIN_DIV => InterpreterValue.MakeFloat(left.kind, lhs / rhs)
            case OpCode.BIN_LT => InterpreterValue.MakeBool(lhs < rhs)
            case OpCode.BIN_GT => InterpreterValue.MakeBool(lhs > rhs)
            case OpCode.BIN_LE => InterpreterValue.MakeBool(lhs <= rhs)
            case OpCode.BIN_GE => InterpreterValue.MakeBool(lhs >= rhs)
            case OpCode.BIN_EQUAL => InterpreterValue.MakeBool(lhs == rhs)
            case OpCode.BIN_NOTEQ => InterpreterValue.MakeBool(lhs != rhs)
            case _ => InterpreterValue.MakeInvalid()
        }
        if (result.IsInvalid()) {
            return false
        }
        interpStack.ArgsPush(result)
        return true
    }

    private func EvaluateBoolBinary(opCode: OpCode, left: Bool, right: Bool): Bool {
        let result = match (opCode) {
            case OpCode.BIN_EQUAL => InterpreterValue.MakeBool(left == right)
            case OpCode.BIN_NOTEQ => InterpreterValue.MakeBool(left != right)
            case OpCode.BIN_BITAND => InterpreterValue.MakeBool(left && right)
            case OpCode.BIN_BITOR => InterpreterValue.MakeBool(left || right)
            case _ => InterpreterValue.MakeInvalid()
        }
        if (result.IsInvalid()) {
            return false
        }
        interpStack.ArgsPush(result)
        return true
    }
}

private func IntOpKind(opCode: OpCode): InterpreterValueKind {
    return match (opCode) {
        case OpCode.INT8 => InterpreterValueKind.IINT8
        case OpCode.INT16 => InterpreterValueKind.IINT16
        case OpCode.INT32 => InterpreterValueKind.IINT32
        case OpCode.INTNAT => InterpreterValueKind.IINTNAT
        case _ => InterpreterValueKind.IINT64
    }
}

private func UIntOpKind(opCode: OpCode): InterpreterValueKind {
    return match (opCode) {
        case OpCode.UINT8 => InterpreterValueKind.IUINT8
        case OpCode.UINT16 => InterpreterValueKind.IUINT16
        case OpCode.UINT32 => InterpreterValueKind.IUINT32
        case OpCode.UINTNAT => InterpreterValueKind.IUINTNAT
        case _ => InterpreterValueKind.IUINT64
    }
}

private func FloatOpKind(opCode: OpCode): InterpreterValueKind {
    return match (opCode) {
        case OpCode.FLOAT16 => InterpreterValueKind.IFLOAT16
        case OpCode.FLOAT32 => InterpreterValueKind.IFLOAT32
        case _ => InterpreterValueKind.IFLOAT64
    }
}

private func IsSmallIntOp(opCode: OpCode): Bool {
    return opCode == OpCode.INT8 || opCode == OpCode.INT16 || opCode == OpCode.INT32
}

private func IsSmallUIntOp(opCode: OpCode): Bool {
    return opCode == OpCode.UINT8 || opCode == OpCode.UINT16 || opCode == OpCode.UINT32
}

private func IsUnaryOp(opCode: OpCode): Bool {
    return opCode == OpCode.UN_NEG || opCode == OpCode.UN_NEG_EXC || opCode == OpCode.UN_NOT || opCode == OpCode.UN_BITNOT ||
        opCode == OpCode.UN_INC || opCode == OpCode.UN_DEC
}

private func IsBinaryOp(opCode: OpCode): Bool {
    return opCode == OpCode.BIN_ADD || opCode == OpCode.BIN_SUB || opCode == OpCode.BIN_MUL ||
        opCode == OpCode.BIN_DIV || opCode == OpCode.BIN_MOD || opCode == OpCode.BIN_EXP ||
        opCode == OpCode.BIN_ADD_EXC || opCode == OpCode.BIN_SUB_EXC || opCode == OpCode.BIN_MUL_EXC ||
        opCode == OpCode.BIN_DIV_EXC || opCode == OpCode.BIN_MOD_EXC || opCode == OpCode.BIN_EXP_EXC ||
        opCode == OpCode.BIN_LT || opCode == OpCode.BIN_GT || opCode == OpCode.BIN_LE ||
        opCode == OpCode.BIN_GE || opCode == OpCode.BIN_NOTEQ || opCode == OpCode.BIN_EQUAL ||
        opCode == OpCode.BIN_BITAND || opCode == OpCode.BIN_BITOR || opCode == OpCode.BIN_BITXOR ||
        opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT ||
        opCode == OpCode.BIN_LSHIFT_EXC || opCode == OpCode.BIN_RSHIFT_EXC
}

private func IntPowValue(kind: InterpreterValueKind, lhs: Int64, rhs: Int64): InterpreterValue {
    if (rhs < 0) {
        return InterpreterValue.MakeInvalid()
    }
    var out: Int64 = 1
    var idx: Int64 = 0
    while (idx < rhs) {
        out *= lhs
        idx++
    }
    return InterpreterValue.MakeInt(kind, out)
}
