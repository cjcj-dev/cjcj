package cangjie_compiler::chir

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
            } else if (opCode == OpCode.ARRAY || opCode == OpCode.VARRAY ||
                opCode == OpCode.ALLOCATE_RAW_ARRAY_LITERAL) {
                interpStack.ArgsPush(InterpreterValue.MakeArray(interpStack.ArgsPop(code.Get(pc + 1))))
                pc += 2
            } else if (opCode == OpCode.ALLOCATE_STRUCT) {
                interpStack.ArgsPush(InterpreterValue.MakeTuple(interpStack.ArgsPop(code.Get(pc + 1))))
                pc += 2
            } else if (opCode == OpCode.ALLOCATE_CLASS) {
                let classId = code.Get(pc + 1)
                let fieldCount = code.Get(pc + 2)
                interpStack.ArgsPush(InterpreterValue.MakeObject(classId, interpStack.ArgsPop(fieldCount)))
                pc += 3
            } else if (opCode == OpCode.ALLOCATE) {
                interpStack.ArgsPush(arena.Allocate(interpStack.ArgsPopIVal()))
                pc += 1
            } else if (opCode == OpCode.FRAME) {
                env.StartStackFrame()
                env.AllocateLocalVarsForFrame(code.Get(pc + 1))
                pc += 2
            } else if (opCode == OpCode.LVAR) {
                interpStack.ArgsPush(env.GetLocal(code.Get(pc + 1)))
                pc += 2
            } else if (opCode == OpCode.GVAR) {
                interpStack.ArgsPush(env.GetGlobal(code.Get(pc + 1)))
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
            } else if (opCode == OpCode.DROP || opCode == OpCode.STORE) {
                interpStack.ArgsPopBack()
                pc += 1
            } else if (opCode == OpCode.JUMP) {
                pc = code.Get(pc + 1)
            } else if (opCode == OpCode.BRANCH) {
                let condition = interpStack.ArgsPopIVal()
                pc = if (IValUtils.IsTruthy(condition)) { code.Get(pc + 1) } else { code.Get(pc + 2) }
            } else if (opCode == OpCode.APPLY) {
                let argCount = code.Get(pc + 1)
                if (argCount <= 0 || interpStack.ArgsSize() < argCount) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "invalid APPLY argument count"))
                }
                let functionValue = interpStack.ArgsGet(argCount, 0)
                if (functionValue.kind != InterpreterValueKind.IFUNC) {
                    return Finish(BCHIRResult(BCHIRResultKind.TRAP, message: "APPLY target is not a function"))
                }
                interpStack.CtrlPush(ControlState(opCode, interpStack.ArgsSize() - argCount, pc + 2, env.GetBP()))
                pc = functionValue.GetFunctionIndex()
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
        if (operand.IsFloatLike() && opCode == OpCode.UN_NEG) {
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
            case OpCode.BIN_SUB => InterpreterValue.MakeInt(left.kind, lhs - rhs)
            case OpCode.BIN_MUL => InterpreterValue.MakeInt(left.kind, lhs * rhs)
            case OpCode.BIN_DIV => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs / rhs) }
            case OpCode.BIN_MOD => if (rhs == 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs % rhs) }
            case OpCode.BIN_EXP => IntPowValue(left.kind, lhs, rhs)
            case OpCode.BIN_BITAND => InterpreterValue.MakeInt(left.kind, lhs & rhs)
            case OpCode.BIN_BITOR => InterpreterValue.MakeInt(left.kind, lhs | rhs)
            case OpCode.BIN_BITXOR => InterpreterValue.MakeInt(left.kind, lhs ^ rhs)
            case OpCode.BIN_LSHIFT => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs << rhs) }
            case OpCode.BIN_RSHIFT => if (rhs < 0) { InterpreterValue.MakeInvalid() } else { InterpreterValue.MakeInt(left.kind, lhs >> rhs) }
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
    return opCode == OpCode.UN_NEG || opCode == OpCode.UN_NOT || opCode == OpCode.UN_BITNOT ||
        opCode == OpCode.UN_INC || opCode == OpCode.UN_DEC
}

private func IsBinaryOp(opCode: OpCode): Bool {
    return opCode == OpCode.BIN_ADD || opCode == OpCode.BIN_SUB || opCode == OpCode.BIN_MUL ||
        opCode == OpCode.BIN_DIV || opCode == OpCode.BIN_MOD || opCode == OpCode.BIN_EXP ||
        opCode == OpCode.BIN_LT || opCode == OpCode.BIN_GT || opCode == OpCode.BIN_LE ||
        opCode == OpCode.BIN_GE || opCode == OpCode.BIN_NOTEQ || opCode == OpCode.BIN_EQUAL ||
        opCode == OpCode.BIN_BITAND || opCode == OpCode.BIN_BITOR || opCode == OpCode.BIN_BITXOR ||
        opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT
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
