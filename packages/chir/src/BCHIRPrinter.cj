package cjcj::chir

import std.collection.*
import cjcj::utils.CJC_ASSERT

public class BCHIRPrinter {
    private let bchir: BCHIR

    public init(bchir: BCHIR) {
        this.bchir = bchir
    }

    public func Print(header!: String = ""): String {
        var out = ""
        out += "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
        out += "+++ " + header + "\n"
        let linked = bchir.GetLinkedByteCode()
        if (linked.Size() > 0) {
            out += "====== Linked bytecode ======\n"
            out += DefinitionToString(linked, "  ")
        } else {
            out += "====== Global vars before linkage ======\n"
            for (entry in bchir.GetGlobalVars()) {
                out += "---- " + entry.name + "\n"
                out += DefinitionToString(entry.definition, "  ")
            }
            out += "====== Functions before linkage ======\n"
            for (entry in bchir.GetFunctions()) {
                out += "---- " + entry.name + "\n"
                out += DefinitionToString(entry.definition, "  ")
            }
        }
        out += "====== Default functions mangled names ======\n"
        out += "main mangled name: " + bchir.GetMainMangledName() + "\n"
        out += "main expected arguments: ${bchir.GetMainExpectedArgs()}\n"
        out += "Global init function: " + bchir.GetGlobalInitFunc() + "\n"
        if (linked.Size() > 0) {
            let defaultPtrs = bchir.GetDefaultFuncPtrs()
            var idx: Int64 = 0
            while (idx < defaultPtrs.size) {
                out += DefaultFunctionKindCellName(idx) + ": ${defaultPtrs[idx]}\n"
                idx++
            }
        }
        return out
    }

    public func PrintAll(header!: String = ""): String {
        var out = Print(header: header)
        let strings = bchir.GetStrings()
        if (!strings.isEmpty()) {
            out += "strings:\n"
            var idx: Int64 = 0
            while (idx < strings.size) {
                out += "  #${idx}: \"" + strings[idx] + "\"\n"
                idx++
            }
        }
        let files = bchir.GetFileNames()
        if (!files.isEmpty()) {
            out += "files:\n"
            var idx: Int64 = 0
            while (idx < files.size) {
                out += "  #${idx}: " + files[idx] + "\n"
                idx++
            }
        }
        let types = bchir.GetTypes()
        if (!types.isEmpty()) {
            out += "types:\n"
            var idx: Int64 = 0
            while (idx < types.size) {
                out += "  #${idx}: " + types[idx].ToString() + "\n"
                idx++
            }
        }
        let classTable = bchir.GetSClassTable()
        if (!classTable.isEmpty()) {
            out += "====== Class table ======\n"
            for (name in classTable.keys()) {
                out += name + ":\n"
                if (let Some(info) <- classTable.get(name)) {
                    for (superClass in info.superClasses) {
                        out += "\t" + superClass + "\n"
                    }
                    for (method in info.vtable.keys()) {
                        out += "\t" + method + ": " + (info.vtable.get(method) ?? "") + "\n"
                    }
                    out += "\tfinalizer: " + info.finalizer + "\n"
                }
            }
        }
        return out
    }

    private func DefinitionToString(definition: BCHIRDefinition, indent: String): String {
        let code = definition.GetByteCodeRef()
        var out = indent + "byte code\n"
        var index: Int64 = 0
        while (index < code.size) {
            let opCode = OpCodeFromIndex(code[index])
            out += indent + "${index}, " + GetOpCodeLabel(opCode)
            out += ArgumentsToString(definition, index, opCode)
            let mangled = definition.GetMangledNameAnnotation(index)
            let position = definition.GetCodePositionAnnotation(index)
            if (!mangled.isEmpty() || position.isSome()) {
                out += " { "
                if (!mangled.isEmpty()) {
                    out += "mangledName: " + mangled
                    if (position.isSome()) {
                        out += ", "
                    }
                }
                if (let Some(codePosition) <- position) {
                    out += bchir.GetFileName(codePosition.fileID) + ":${codePosition.line}:${codePosition.column}"
                }
                out += "}"
            }
            out += "\n"
            index = NextInstructionIndex(definition, index, opCode)
        }
        return out
    }

    private func ArgumentsToString(definition: BCHIRDefinition, index: Int64, opCode: OpCode): String {
        let args = ArrayList<String>()
        if (opCode == OpCode.STRING) {
            let strIdx = definition.Get(index + 1)
            args.add("(str: ${strIdx}) -> " + bchir.GetString(strIdx))
        } else if (opCode == OpCode.INT64 || opCode == OpCode.INTNAT ||
            opCode == OpCode.UINT64 || opCode == OpCode.UINTNAT ||
            opCode == OpCode.FLOAT64) {
            args.add("${definition.Get8Bytes(index + 1)}")
        } else if (opCode == OpCode.FLOAT16 || opCode == OpCode.FLOAT32) {
            args.add("bits:${definition.Get(index + 1)}")
        } else if (opCode == OpCode.RUNE) {
            args.add("rune:${definition.Get(index + 1)}")
        } else if (opCode == OpCode.SWITCH) {
            AppendSwitchArgs(definition, index, args)
        } else if (opCode == OpCode.FIELD_TPL || opCode == OpCode.GETREF || opCode == OpCode.STOREINREF) {
            AppendPathArgs(definition, index, args)
        } else if (IsArithmeticTypedOp(opCode)) {
            AppendArithmeticArgs(definition, index, opCode, args)
        } else if (opCode == OpCode.TYPECAST || opCode == OpCode.TYPECAST_EXC) {
            args.add(TypeKindCellName(definition.Get(index + 1)))
            args.add(TypeKindCellName(definition.Get(index + 2)))
            args.add(OverflowStrategyCellName(definition.Get(index + 3)))
            if (opCode == OpCode.TYPECAST_EXC) {
                args.add("${definition.Get(index + 4)}")
            }
        } else if (opCode == OpCode.INTRINSIC0 || opCode == OpCode.INTRINSIC0_EXC ||
            opCode == OpCode.INTRINSIC1 || opCode == OpCode.INTRINSIC1_EXC ||
            opCode == OpCode.INTRINSIC2 || opCode == OpCode.INTRINSIC2_EXC) {
            AppendIntrinsicArgs(definition, index, opCode, args)
        } else if (opCode == OpCode.SYSCALL) {
            AppendSyscallArgs(definition, index, args)
        } else if (opCode == OpCode.CAPPLY) {
            AppendCApplyArgs(definition, index, args)
        } else {
            AppendRawArgs(definition, index, GetOpCodeArgSize(opCode), args)
        }
        if (args.isEmpty()) {
            return ""
        }
        return ", " + JoinStrings(args, "\n")
    }

    private func AppendRawArgs(definition: BCHIRDefinition, index: Int64, count: Int64,
        args: ArrayList<String>): Unit {
        var argIdx: Int64 = 0
        while (argIdx < count && index + 1 + argIdx < definition.Size()) {
            args.add("${index + 1 + argIdx}, ${definition.Get(index + 1 + argIdx)}")
            argIdx++
        }
    }

    private func AppendPathArgs(definition: BCHIRDefinition, index: Int64, args: ArrayList<String>): Unit {
        let pathSize = definition.Get(index + 1)
        args.add("${index + 1}, ${pathSize}")
        var pathIdx: Int64 = 0
        while (pathIdx < pathSize) {
            args.add("${index + 2 + pathIdx}, ${definition.Get(index + 2 + pathIdx)}")
            pathIdx++
        }
    }

    private func AppendSwitchArgs(definition: BCHIRDefinition, index: Int64, args: ArrayList<String>): Unit {
        let caseCount = definition.Get(index + 2)
        args.add("${index + 1}, " + TypeKindCellName(definition.Get(index + 1)))
        args.add("${index + 2}, ${caseCount}")
        var caseIdx: Int64 = 0
        while (caseIdx < caseCount) {
            args.add("${index + 3 + caseIdx * 2}, case ${definition.Get8Bytes(index + 3 + caseIdx * 2)}")
            caseIdx++
        }
        let defaultTarget = index + 3 + caseCount * 2
        args.add("${defaultTarget}, default ${definition.Get(defaultTarget)}")
        var targetIdx: Int64 = 0
        while (targetIdx < caseCount) {
            let targetCell = defaultTarget + 1 + targetIdx
            args.add("${targetCell}, target ${definition.Get(targetCell)}")
            targetIdx++
        }
    }

    private func AppendArithmeticArgs(definition: BCHIRDefinition, index: Int64, opCode: OpCode,
        args: ArrayList<String>): Unit {
        args.add("${index + 1}, " + TypeKindCellName(definition.Get(index + 1)))
        args.add("${index + 2}, " + OverflowStrategyCellName(definition.Get(index + 2)))
        var cursor = index + 3
        if (opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT ||
            opCode == OpCode.BIN_LSHIFT_EXC || opCode == OpCode.BIN_RSHIFT_EXC) {
            args.add("${cursor}, " + TypeKindCellName(definition.Get(cursor)))
            cursor++
        }
        if (OpHasExceptionHandler(opCode)) {
            args.add("${cursor}, ${definition.Get(cursor)}")
        }
    }

    private func AppendIntrinsicArgs(definition: BCHIRDefinition, index: Int64, opCode: OpCode,
        args: ArrayList<String>): Unit {
        args.add("${index + 1}, " + IntrinsicKindCellName(definition.Get(index + 1)))
        var cursor = index + 2
        if (opCode == OpCode.INTRINSIC1 || opCode == OpCode.INTRINSIC1_EXC ||
            opCode == OpCode.INTRINSIC2 || opCode == OpCode.INTRINSIC2_EXC) {
            let tyIdx = definition.Get(cursor)
            if (tyIdx == 0xffffffff) {
                args.add("${cursor}, (no type)")
            } else if (let Some(ty) <- bchir.GetTypeAt(tyIdx)) {
                args.add("${cursor}, Ty (idx: ${tyIdx}):" + ty.ToString())
            } else {
                args.add("${cursor}, Ty (idx: ${tyIdx})")
            }
            cursor++
        }
        if (opCode == OpCode.INTRINSIC2 || opCode == OpCode.INTRINSIC2_EXC) {
            args.add("${cursor}, " + OverflowStrategyCellName(definition.Get(cursor)))
            cursor++
        }
        if (OpHasExceptionHandler(opCode)) {
            args.add("${cursor}, ${definition.Get(cursor)}")
        }
    }

    private func AppendSyscallArgs(definition: BCHIRDefinition, index: Int64, args: ArrayList<String>): Unit {
        let stringIdx = definition.Get(index + 1)
        let numberOfArgs = definition.Get(index + 2)
        args.add("${index + 1}, syscall (str: ${stringIdx}) -> " + bchir.GetString(stringIdx))
        args.add("${index + 2}, args ${numberOfArgs}")
        args.add("${index + 3}, result type ${definition.Get(index + 3)}")
        var argIdx: Int64 = 0
        while (argIdx < numberOfArgs) {
            args.add("${index + 4 + argIdx}, arg type ${definition.Get(index + 4 + argIdx)}")
            argIdx++
        }
    }

    private func AppendCApplyArgs(definition: BCHIRDefinition, index: Int64, args: ArrayList<String>): Unit {
        let numberOfArgs = definition.Get(index + 1)
        args.add("${index + 1}, args ${numberOfArgs}")
        var typeIdx: Int64 = 0
        while (typeIdx <= numberOfArgs) {
            args.add("${index + 2 + typeIdx}, type ${definition.Get(index + 2 + typeIdx)}")
            typeIdx++
        }
    }

    private func NextInstructionIndex(definition: BCHIRDefinition, index: Int64, opCode: OpCode): Int64 {
        if (opCode == OpCode.SWITCH) {
            let caseCount = definition.Get(index + 2)
            return index + 1 + 2 + caseCount * 2 + 1 + caseCount
        }
        if (opCode == OpCode.SYSCALL) {
            return index + 4 + definition.Get(index + 2)
        }
        if (opCode == OpCode.CAPPLY) {
            return index + 3 + definition.Get(index + 1)
        }
        if (opCode == OpCode.GETREF || opCode == OpCode.STOREINREF || opCode == OpCode.FIELD_TPL) {
            return index + 2 + definition.Get(index + 1)
        }
        return index + 1 + GetOpCodeArgSize(opCode)
    }
}

private func IsArithmeticTypedOp(opCode: OpCode): Bool {
    return opCode == OpCode.UN_NEG || opCode == OpCode.UN_NEG_EXC || opCode == OpCode.UN_NOT ||
        opCode == OpCode.UN_BITNOT || opCode == OpCode.UN_INC || opCode == OpCode.UN_DEC ||
        opCode == OpCode.BIN_ADD || opCode == OpCode.BIN_SUB || opCode == OpCode.BIN_MUL ||
        opCode == OpCode.BIN_DIV || opCode == OpCode.BIN_MOD || opCode == OpCode.BIN_EXP ||
        opCode == OpCode.BIN_ADD_EXC || opCode == OpCode.BIN_SUB_EXC || opCode == OpCode.BIN_MUL_EXC ||
        opCode == OpCode.BIN_DIV_EXC || opCode == OpCode.BIN_MOD_EXC || opCode == OpCode.BIN_EXP_EXC ||
        opCode == OpCode.BIN_LT || opCode == OpCode.BIN_GT || opCode == OpCode.BIN_LE ||
        opCode == OpCode.BIN_GE || opCode == OpCode.BIN_NOTEQ || opCode == OpCode.BIN_EQUAL ||
        opCode == OpCode.BIN_BITAND || opCode == OpCode.BIN_BITOR || opCode == OpCode.BIN_BITXOR ||
        opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT ||
        opCode == OpCode.BIN_LSHIFT_EXC || opCode == OpCode.BIN_RSHIFT_EXC
}

private func TypeKindCellName(cell: Int64): String {
    return match (cell) {
        case 1 => "Int8"
        case 2 => "Int16"
        case 3 => "Int32"
        case 4 => "Int64"
        case 5 => "IntNative"
        case 6 => "UInt8"
        case 7 => "UInt16"
        case 8 => "UInt32"
        case 9 => "UInt64"
        case 10 => "UIntNative"
        case 11 => "Float16"
        case 12 => "Float32"
        case 13 => "Float64"
        case 14 => "Rune"
        case 15 => "Bool"
        case 16 => "Unit"
        case _ => "type:${cell}"
    }
}

private func OverflowStrategyCellName(cell: Int64): String {
    return match (cell) {
        case 0 => "NA"
        case 1 => "CHECKED"
        case 2 => "WRAPPING"
        case 3 => "THROWING"
        case 4 => "SATURATING"
        case _ => "overflow:${cell}"
    }
}

private func IntrinsicKindCellName(cell: Int64): String {
    return match (cell) {
        case 10 => "INTRINSIC_KIND: ARRAY_GET_UNCHECKED(10)"
        case 40 => "INTRINSIC_KIND: OBJECT_REFEQ(40)"
        case 41 => "INTRINSIC_KIND: RAW_ARRAY_REFEQ(41)"
        case 42 => "INTRINSIC_KIND: FUNC_REFEQ(42)"
        case 60 => "INTRINSIC_KIND: VARRAY_GET(60)"
        case 106 => "INTRINSIC_KIND: CJ_CORE_CAN_USE_SIMD(106)"
        case _ => "INTRINSIC_KIND: ${cell}"
    }
}

private func DefaultFunctionKindCellName(cell: Int64): String {
    return match (cell) {
        case 0 => "THROW_ARITHMETIC_EXCEPTION"
        case 1 => "THROW_OVERFLOW_EXCEPTION"
        case 2 => "THROW_INDEX_OUT_OF_BOUNDS_EXCEPTION"
        case 3 => "THROW_NEGATIVA_ARRAY_SIZE_EXCEPTION"
        case 4 => "CALL_TO_STRING"
        case 5 => "THROW_ARITHMETIC_EXCEPTION_MSG"
        case 6 => "THROW_OUT_OF_MEMORY_ERROR"
        case 7 => "CHECK_IS_ERROR"
        case 8 => "THROW_ERROR"
        case 9 => "CALL_PRINT_STACK_TRACE"
        case 10 => "CALL_PRINT_STACK_TRACE_ERROR"
        case 11 => "MAIN"
        case _ =>
            CJC_ASSERT(false)
            ""
    }
}
