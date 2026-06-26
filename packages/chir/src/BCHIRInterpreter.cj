package cangjie_compiler::chir

import cangjie_compiler::utils.OverflowStrategy
import std.collection.*

public class BCHIRInterpreter {
    public static let INTERNAL_PLAYGROUND_SIZE: Int64 = 20
    public static let EXTERNAL_PLAYGROUND_SIZE: Int64 = 20

    private let bchir: BCHIR
    private let interpStack: InterpreterStack = InterpreterStack()
    private let arena: InterpreterArena = InterpreterArena()
    private let env: InterpreterEnv
    private var lastResult: BCHIRResult = BCHIRResult(BCHIRResultKind.UNSUPPORTED, message: "not run")
    private var currentException: Option<InterpreterValue> = None

    public init(bchir: BCHIR) {
        this.bchir = bchir
        this.env = InterpreterEnv(bchir.GetNumGlobalVars())
    }

    public func Run(baseIndex!: Int64 = 0, expectsReturn!: Bool = true): BCHIRResult {
        interpStack.ArgsClear()
        currentException = None
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
            } else if (opCode == OpCode.RUNE) {
                interpStack.ArgsPush(InterpreterValue.MakeRune(Rune(code.Get(pc + 1))))
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
            } else if (opCode == OpCode.VARRAY_GET) {
                if (let Some(value) <- InterpretVArrayGet(pc)) {
                    interpStack.ArgsPush(value)
                    pc += 1 + GetOpCodeArgSize(opCode)
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid VARRAY_GET path"))
                }
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
            } else if (opCode == OpCode.RAW_ARRAY_INIT_BY_VALUE) {
                if (!RawArrayInitByValue()) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid raw array init by value"))
                }
                pc += 1
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
            } else if (opCode == OpCode.INVOKE || opCode == OpCode.INVOKE_EXC) {
                let argCount = code.Get(pc + 1)
                if (argCount <= 0 || interpStack.ArgsSize() < argCount) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid INVOKE argument count"))
                }
                let receiver = interpStack.ArgsGet(argCount, 0)
                if (let Some(receiverObject) <- DereferencePointer(receiver)) {
                    if (receiverObject.kind != InterpreterValueKind.IOBJECT) {
                        return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "INVOKE receiver is not an object"))
                    }
                    if (let Some(functionIndex) <- FindMethod(receiverObject.GetClassId(), code.Get(pc + 2))) {
                        interpStack.CtrlPush(ControlState(opCode, interpStack.ArgsSize() - argCount,
                            pc + 1 + GetOpCodeArgSize(opCode), env.GetBP()))
                        pc = functionIndex
                    } else {
                        return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "method not found in vtable"))
                    }
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid INVOKE receiver"))
                }
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
            } else if (opCode == OpCode.TYPECAST || opCode == OpCode.TYPECAST_EXC) {
                if (let Some(sourceKind) <- TypeKindFromCell(code.Get(pc + 1))) {
                    if (let Some(targetKind) <- TypeKindFromCell(code.Get(pc + 2))) {
                        if (let Some(strategy) <- OverflowStrategyFromCell(code.Get(pc + 3))) {
                            if (let Some(casted) <- CastValueToTypeKind(interpStack.ArgsPopIVal(), sourceKind,
                                targetKind, strategy)) {
                                interpStack.ArgsPush(casted)
                                pc += 1 + GetOpCodeArgSize(opCode)
                            } else {
                                return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid TYPECAST operand"))
                            }
                        } else {
                            return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid TYPECAST overflow strategy"))
                        }
                    } else {
                        return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid TYPECAST target type"))
                    }
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid TYPECAST source type"))
                }
            } else if (opCode == OpCode.SWITCH) {
                if (let Some(target) <- InterpretSwitch(pc)) {
                    pc = target
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid SWITCH selector or table"))
                }
            } else if (opCode == OpCode.RAISE) {
                currentException = interpStack.ArgsPopIVal()
                return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "uncaught exception"))
            } else if (opCode == OpCode.RAISE_EXC) {
                currentException = interpStack.ArgsPopIVal()
                pc = code.Get(pc + 1)
            } else if (opCode == OpCode.GET_EXCEPTION) {
                if (let Some(exceptionValue) <- currentException) {
                    interpStack.ArgsPush(exceptionValue)
                    currentException = None
                    pc += 1
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "GET_EXCEPTION without exception"))
                }
            } else if (opCode == OpCode.INTRINSIC0 || opCode == OpCode.INTRINSIC0_EXC) {
                let intrinsicKind = code.Get(pc + 1)
                if (BCHIRIntrinsic.IsReferenceEquality(intrinsicKind)) {
                    let right = interpStack.ArgsPopIVal()
                    let left = interpStack.ArgsPopIVal()
                    interpStack.ArgsPush(InterpreterValue.MakeBool(BCHIRIntrinsic.ReferenceEquals(left, right)))
                    pc += 1 + GetOpCodeArgSize(opCode)
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED,
                        message: "unsupported INTRINSIC0 kind ${intrinsicKind}"))
                }
            } else if (opCode == OpCode.INTRINSIC1 || opCode == OpCode.INTRINSIC1_EXC) {
                let intrinsicKind = code.Get(pc + 1)
                if (BCHIRIntrinsic.IsArrayGetUnchecked(intrinsicKind)) {
                    if (let Some(value) <- InterpretArrayGetUnchecked()) {
                        interpStack.ArgsPush(value)
                        pc += 1 + GetOpCodeArgSize(opCode)
                    } else {
                        return Finish(BCHIRResult(BCHIRResultKind.TRAP,
                            message: "invalid ARRAY_GET_UNCHECKED intrinsic operands"))
                    }
                } else {
                    return Finish(BCHIRResult(BCHIRResultKind.UNSUPPORTED,
                        message: "unsupported INTRINSIC1 kind ${intrinsicKind}"))
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

    public func DereferenceValue(value: InterpreterValue): Option<InterpreterValue> {
        return DereferencePointer(value)
    }

    public func SetGlobalVar(index: Int64, value: InterpreterValue): Bool {
        return env.SetGlobal(index, value)
    }

    public func SetGlobalVars(values: HashMap<Int64, InterpreterValue>): Unit {
        for (index in values.keys()) {
            if (let Some(value) <- values.get(index)) {
                let _ = env.SetGlobal(index, value)
            }
        }
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

    private func RawArrayInitByValue(): Bool {
        let initValue = interpStack.ArgsPopIVal()
        let sizeValue = interpStack.ArgsPopIVal()
        let pointer = interpStack.ArgsPopIVal()
        if (!sizeValue.IsIntLike()) {
            return false
        }
        let size = sizeValue.GetInt()
        if (size < 0) {
            return false
        }
        if (let Some(arrayValue) <- DereferencePointer(pointer)) {
            if (arrayValue.kind != InterpreterValueKind.IARRAY || arrayValue.GetElementsRef().size < size + 1) {
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
                pointer.GetPointerIndex(), path), initValue)) {
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

    private func FindMethod(classId: Int64, methodId: Int64): Option<Int64> {
        if (let Some(classInfo) <- bchir.GetClass(classId)) {
            return classInfo.vtable.get(methodId)
        }
        return None
    }

    private func InterpretVArrayGet(varrayGetPc: Int64): Option<InterpreterValue> {
        let code = bchir.GetLinkedByteCode()
        let pathSize = code.Get(varrayGetPc + 1)
        if (pathSize <= 0) {
            return None
        }
        let path = interpStack.ArgsPop(pathSize)
        let arrayValue = interpStack.ArgsPopIVal()
        if (arrayValue.kind != InterpreterValueKind.IARRAY) {
            return None
        }
        var current = arrayValue
        var pathIdx: Int64 = 0
        while (pathIdx < pathSize) {
            if (current.kind != InterpreterValueKind.IARRAY || !path[pathIdx].IsIntLike()) {
                return None
            }
            let index = path[pathIdx].GetInt()
            let elements = current.GetElementsRef()
            if (index < 0 || index >= elements.size) {
                return None
            }
            current = elements[index]
            pathIdx++
        }
        return current.Clone()
    }

    private func InterpretArrayGetUnchecked(): Option<InterpreterValue> {
        let indexValue = interpStack.ArgsPopIVal()
        let arrayPointer = interpStack.ArgsPopIVal()
        if (!indexValue.IsIntLike()) {
            return None
        }
        if (let Some(arrayValue) <- DereferencePointer(arrayPointer)) {
            if (arrayValue.kind != InterpreterValueKind.IARRAY) {
                return None
            }
            let index = indexValue.GetInt() + 1
            let elements = arrayValue.GetElementsRef()
            if (index < 0 || index >= elements.size) {
                return None
            }
            return elements[index].Clone()
        }
        return None
    }

    private func InterpretSwitch(switchPc: Int64): Option<Int64> {
        let selector = interpStack.ArgsPopIVal()
        if (let Some(selectorValue) <- SwitchSelectorToInt(selector)) {
            let code = bchir.GetLinkedByteCode()
            let caseCount = code.Get(switchPc + 2)
            if (caseCount < 0) {
                return None
            }
            let caseStart = switchPc + 3
            let defaultTargetIndex = caseStart + caseCount * 2
            let targetStart = defaultTargetIndex + 1
            var left: Int64 = 0
            var right = caseCount
            while (left < right) {
                let mid = (left + right) / 2
                let caseValue = code.Get8Bytes(caseStart + mid * 2)
                if (caseValue < selectorValue) {
                    left = mid + 1
                } else {
                    right = mid
                }
            }
            if (left < caseCount && code.Get8Bytes(caseStart + left * 2) == selectorValue) {
                return code.Get(targetStart + left)
            }
            return code.Get(defaultTargetIndex)
        }
        return None
    }

    private func SwitchSelectorToInt(value: InterpreterValue): Option<Int64> {
        if (value.IsIntLike() || value.kind == InterpreterValueKind.IRUNE) {
            return value.GetInt()
        }
        if (value.kind == InterpreterValueKind.IBOOL) {
            return if (value.GetBool()) { 1 } else { 0 }
        }
        return None
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
        if (left.kind == InterpreterValueKind.IRUNE && right.kind == InterpreterValueKind.IRUNE) {
            return EvaluateRuneBinary(opCode, left.GetInt(), right.GetInt())
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

    private func EvaluateRuneBinary(opCode: OpCode, left: Int64, right: Int64): Bool {
        let result = match (opCode) {
            case OpCode.BIN_LT => InterpreterValue.MakeBool(left < right)
            case OpCode.BIN_GT => InterpreterValue.MakeBool(left > right)
            case OpCode.BIN_LE => InterpreterValue.MakeBool(left <= right)
            case OpCode.BIN_GE => InterpreterValue.MakeBool(left >= right)
            case OpCode.BIN_EQUAL => InterpreterValue.MakeBool(left == right)
            case OpCode.BIN_NOTEQ => InterpreterValue.MakeBool(left != right)
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

private func TypeKindFromCell(cell: Int64): Option<TypeKind> {
    return match (cell) {
        case 1 => TypeKind.TYPE_INT8
        case 2 => TypeKind.TYPE_INT16
        case 3 => TypeKind.TYPE_INT32
        case 4 => TypeKind.TYPE_INT64
        case 5 => TypeKind.TYPE_INT_NATIVE
        case 6 => TypeKind.TYPE_UINT8
        case 7 => TypeKind.TYPE_UINT16
        case 8 => TypeKind.TYPE_UINT32
        case 9 => TypeKind.TYPE_UINT64
        case 10 => TypeKind.TYPE_UINT_NATIVE
        case 11 => TypeKind.TYPE_FLOAT16
        case 12 => TypeKind.TYPE_FLOAT32
        case 13 => TypeKind.TYPE_FLOAT64
        case 14 => TypeKind.TYPE_RUNE
        case 15 => TypeKind.TYPE_BOOLEAN
        case 16 => TypeKind.TYPE_UNIT
        case _ => None
    }
}

private func OverflowStrategyFromCell(cell: Int64): Option<OverflowStrategy> {
    return match (cell) {
        case 0 => OverflowStrategy.NA
        case 1 => OverflowStrategy.CHECKED
        case 2 => OverflowStrategy.WRAPPING
        case 3 => OverflowStrategy.THROWING
        case 4 => OverflowStrategy.SATURATING
        case _ => None
    }
}

private func CastValueToTypeKind(value: InterpreterValue, sourceKind: TypeKind,
    targetKind: TypeKind, strategy: OverflowStrategy): Option<InterpreterValue> {
    if (sourceKind == TypeKind.TYPE_RUNE) {
        if (value.kind != InterpreterValueKind.IRUNE) {
            return None
        }
        if (targetKind == TypeKind.TYPE_UINT32) {
            return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT32, TruncateUnsigned(value.GetInt(), 32))
        }
        if (targetKind == TypeKind.TYPE_UINT64) {
            return InterpreterValue.MakeUInt(InterpreterValueKind.IUINT64, value.GetInt())
        }
        return None
    }
    if (IsIntegerTypeKind(sourceKind) || sourceKind == TypeKind.TYPE_BOOLEAN) {
        if (let Some(raw) <- ValueAsInt(value)) {
            return CastIntegerToTypeKind(raw, sourceKind, targetKind, strategy)
        }
        return None
    }
    if (IsFloatTypeKind(sourceKind)) {
        if (value.IsFloatLike()) {
            return CastFloatToTypeKind(value.GetFloat(), targetKind)
        }
        return None
    }
    return None
}

private func ValueAsInt(value: InterpreterValue): Option<Int64> {
    if (value.IsIntLike() || value.kind == InterpreterValueKind.IRUNE) {
        return value.GetInt()
    }
    if (value.kind == InterpreterValueKind.IBOOL) {
        return if (value.GetBool()) { 1 } else { 0 }
    }
    return None
}

private func CastIntegerToTypeKind(raw: Int64, sourceKind: TypeKind, targetKind: TypeKind,
    strategy: OverflowStrategy): Option<InterpreterValue> {
    if (targetKind == TypeKind.TYPE_RUNE) {
        if (let Some(converted) <- CastIntegerToUnsigned(raw, sourceKind, TypeKind.TYPE_UINT32, strategy)) {
            return InterpreterValue.MakeRune(Rune(converted))
        }
        return None
    }
    if (IsIntegerTypeKind(targetKind)) {
        if (IsSignedIntegerTypeKind(targetKind)) {
            if (let Some(converted) <- CastIntegerToSigned(raw, sourceKind, targetKind, strategy)) {
                return IntegerValueForTypeKind(targetKind, converted)
            }
            return None
        }
        if (let Some(converted) <- CastIntegerToUnsigned(raw, sourceKind, targetKind, strategy)) {
            return IntegerValueForTypeKind(targetKind, converted)
        }
        return None
    }
    if (IsFloatTypeKind(targetKind)) {
        return FloatValueForTypeKind(targetKind, Float64(raw))
    }
    return None
}

private func CastIntegerToSigned(raw: Int64, sourceKind: TypeKind, targetKind: TypeKind,
    strategy: OverflowStrategy): Option<Int64> {
    let result = if (IsUnsignedIntegerTypeKind(sourceKind)) {
        if (raw < 0) {
            return None
        }
        OverflowChecker.IsUnsignedToSignedTypecastOverflow(UInt64(raw), targetKind, strategy)
    } else {
        OverflowChecker.IsSignedToSignedTypecastOverflow(raw, targetKind, strategy)
    }
    if (result.isOverflow && strategy == OverflowStrategy.THROWING) {
        return None
    }
    return result.value
}

private func CastIntegerToUnsigned(raw: Int64, sourceKind: TypeKind, targetKind: TypeKind,
    strategy: OverflowStrategy): Option<Int64> {
    let result = if (IsUnsignedIntegerTypeKind(sourceKind)) {
        if (raw < 0) {
            return None
        }
        OverflowChecker.IsUnsignedToUnsignedTypecastOverflow(UInt64(raw), targetKind, strategy)
    } else {
        OverflowChecker.IsSignedToUnsignedTypecastOverflow(raw, targetKind, strategy)
    }
    if (result.isOverflow && strategy == OverflowStrategy.THROWING) {
        return None
    }
    if (result.value > UInt64(Int64.Max)) {
        return None
    }
    return Int64(result.value)
}

private func CastFloatToTypeKind(raw: Float64, targetKind: TypeKind): Option<InterpreterValue> {
    if (IsIntegerTypeKind(targetKind)) {
        return IntegerValueForTypeKind(targetKind, Int64(raw))
    }
    if (IsFloatTypeKind(targetKind)) {
        return FloatValueForTypeKind(targetKind, raw)
    }
    return None
}

private func IntegerValueForTypeKind(targetKind: TypeKind, raw: Int64): Option<InterpreterValue> {
    return match (targetKind) {
        case TypeKind.TYPE_INT8 => InterpreterValue.MakeInt(InterpreterValueKind.IINT8, TruncateSigned(raw, 8))
        case TypeKind.TYPE_INT16 => InterpreterValue.MakeInt(InterpreterValueKind.IINT16, TruncateSigned(raw, 16))
        case TypeKind.TYPE_INT32 => InterpreterValue.MakeInt(InterpreterValueKind.IINT32, TruncateSigned(raw, 32))
        case TypeKind.TYPE_INT64 => InterpreterValue.MakeInt(InterpreterValueKind.IINT64, raw)
        case TypeKind.TYPE_INT_NATIVE => InterpreterValue.MakeInt(InterpreterValueKind.IINTNAT, raw)
        case TypeKind.TYPE_UINT8 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT8, TruncateUnsigned(raw, 8))
        case TypeKind.TYPE_UINT16 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT16, TruncateUnsigned(raw, 16))
        case TypeKind.TYPE_UINT32 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT32, TruncateUnsigned(raw, 32))
        case TypeKind.TYPE_UINT64 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT64, raw)
        case TypeKind.TYPE_UINT_NATIVE => InterpreterValue.MakeUInt(InterpreterValueKind.IUINTNAT, raw)
        case _ => None
    }
}

private func FloatValueForTypeKind(targetKind: TypeKind, raw: Float64): Option<InterpreterValue> {
    return match (targetKind) {
        case TypeKind.TYPE_FLOAT16 => InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT16, raw)
        case TypeKind.TYPE_FLOAT32 => InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT32, raw)
        case TypeKind.TYPE_FLOAT64 => InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT64, raw)
        case _ => None
    }
}

private func IsIntegerTypeKind(kind: TypeKind): Bool {
    let idx = TypeKindIndex(kind)
    return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)
}

private func IsSignedIntegerTypeKind(kind: TypeKind): Bool {
    let idx = TypeKindIndex(kind)
    return idx >= TypeKindIndex(TypeKind.TYPE_INT8) && idx <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)
}

private func IsUnsignedIntegerTypeKind(kind: TypeKind): Bool {
    let idx = TypeKindIndex(kind)
    return idx >= TypeKindIndex(TypeKind.TYPE_UINT8) && idx <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)
}

private func IsFloatTypeKind(kind: TypeKind): Bool {
    let idx = TypeKindIndex(kind)
    return idx >= TypeKindIndex(TypeKind.TYPE_FLOAT16) && idx <= TypeKindIndex(TypeKind.TYPE_FLOAT64)
}

private func TruncateUnsigned(raw: Int64, width: Int64): Int64 {
    if (width >= 64) {
        return raw
    }
    return raw & ((1 << width) - 1)
}

private func TruncateSigned(raw: Int64, width: Int64): Int64 {
    if (width >= 64) {
        return raw
    }
    let masked = TruncateUnsigned(raw, width)
    let signBit = 1 << (width - 1)
    if ((masked & signBit) != 0) {
        return masked - (1 << width)
    }
    return masked
}
