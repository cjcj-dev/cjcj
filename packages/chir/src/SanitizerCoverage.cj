package cjcj::chir

import std.collection.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.{GlobalOptions, SanitizerCoverageOptions, SanitizerCoverageType}
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, OverflowStrategy}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:23-37.
private func CreateNonMemberApply(resultTy: Type, callee: Value, args: ArrayList<Value>, parent: Block,
    builder: CHIRBuilder, loc!: DebugLocation = INVALID_LOCATION): Apply {
    let result = builder.CreateApply(resultTy, callee, FuncCallContext(args: args), parent)
    result.SetDebugLocation(loc)
    return result
}

private func CreateMemberApply(resultTy: Type, callee: Value, thisType: Type, args: ArrayList<Value>, parent: Block,
    builder: CHIRBuilder, loc!: DebugLocation = INVALID_LOCATION): Apply {
    let result = builder.CreateApply(resultTy, callee, FuncCallContext(args: args, thisType: Some(thisType)), parent)
    result.SetDebugLocation(loc)
    return result
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:39-114.
private let CHAR_ARRAY_TEST_PACK: String = "CharArrayTest"
private let SanCovBoolFlagInitName: String = "__cj_sancov_bool_flag_ctor"
private let SanCovCharArrayInitName: String = "__cj_sancov_8bit_counters_ctor"
private let SanCovUInt32ArrayInitName: String = "__cj_sancov_pc_guard_ctor"
private let SAN_COV_PC_GUARD: String = "__sanitizer_cov_trace_pc_guard"
private let SanCovTraceCmp1: String = "__sanitizer_cov_trace_cmp1"
private let SanCovTraceCmp2: String = "__sanitizer_cov_trace_cmp2"
private let SanCovTraceCmp4: String = "__sanitizer_cov_trace_cmp4"
private let SanCovTraceCmp8: String = "__sanitizer_cov_trace_cmp8"
private let SanCovTraceConstCmp1: String = "__sanitizer_cov_trace_const_cmp1"
private let SanCovTraceConstCmp2: String = "__sanitizer_cov_trace_const_cmp2"
private let SanCovTraceConstCmp4: String = "__sanitizer_cov_trace_const_cmp4"
private let SanCovTraceConstCmp8: String = "__sanitizer_cov_trace_const_cmp8"
private let SAN_COV_TRACE_MEM_CMP: String = "__cj_sanitizer_weak_hook_memcmp"
private let SAN_COV_TRACE_STRN_CMP: String = "__cj_sanitizer_weak_hook_strncmp"
private let SAN_COV_TRACE_STR_CMP: String = "__cj_sanitizer_weak_hook_strcmp"
private let SAN_COV_TRACE_STR_CASE_CMP: String = "__cj_sanitizer_weak_hook_strcasecmp"
private let SanCovTraceSwitchName: String = "__sanitizer_cov_trace_switch"
private let SanCovCreatePCTable: String = "__cj_sancov_pcs_init"
private let SanCovUpdateStackDepth: String = "__cj_sancov_update_stack_depth"

private let SAN_COV_CTOR2_GLOBAL_VAR_NAME = HashMap<String, String>([
    (SanCovBoolFlagInitName, "sancov$_bool_flag"),
    (SanCovCharArrayInitName, "sancov$_8bit_counters"),
    (SanCovUInt32ArrayInitName, "sancov$_pc_guard")
])

private let STRING_FUNC_NAME2_SAN_COV_FUNC = HashMap<String, String>([
    ("==", SAN_COV_TRACE_MEM_CMP),
    ("startsWith", SAN_COV_TRACE_MEM_CMP),
    ("endsWith", SAN_COV_TRACE_MEM_CMP),
    ("indexOf", SAN_COV_TRACE_MEM_CMP),
    ("replace", SAN_COV_TRACE_MEM_CMP),
    ("contains", SAN_COV_TRACE_MEM_CMP)
])

private let CSTRING_FUNC_NAME2_SAN_COV_FUNC = HashMap<String, String>([
    ("equals", SAN_COV_TRACE_STR_CMP),
    ("startsWith", SAN_COV_TRACE_MEM_CMP),
    ("endsWith", SAN_COV_TRACE_STRN_CMP),
    ("compare", SAN_COV_TRACE_STR_CMP),
    ("equalsLower", SAN_COV_TRACE_STR_CASE_CMP)
])

private let HAS_N_PARAMETER_MEM_CMP_SET = HashSet<String>([
    SAN_COV_TRACE_MEM_CMP,
    SAN_COV_TRACE_STRN_CMP
])

private enum MemCmpType {
    | STRING_TYPE
    | CSTRING_TYPE
    | ARRAY_TYPE
    | ARRAYLIST_TYPE
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:116-131.
private func GetStringSanConvFunc(cmpType: MemCmpType, funcName: String): Option<String> {
    if ((let MemCmpType.STRING_TYPE <- cmpType) && STRING_FUNC_NAME2_SAN_COV_FUNC.contains(funcName)) {
        return STRING_FUNC_NAME2_SAN_COV_FUNC.get(funcName)
    }
    if ((let MemCmpType.CSTRING_TYPE <- cmpType) && CSTRING_FUNC_NAME2_SAN_COV_FUNC.contains(funcName)) {
        return CSTRING_FUNC_NAME2_SAN_COV_FUNC.get(funcName)
    }
    if ((let MemCmpType.ARRAY_TYPE <- cmpType) && funcName == "==") {
        return Some(SAN_COV_TRACE_MEM_CMP)
    }
    if ((let MemCmpType.ARRAYLIST_TYPE <- cmpType) && funcName == "==") {
        return Some(SAN_COV_TRACE_MEM_CMP)
    }
    return None
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:133-156.
private func GetTraceCompareType(kind: TypeKind): TypeKind {
    if (kind == TypeKind.TYPE_INT64 || kind == TypeKind.TYPE_UINT64) {
        return TypeKind.TYPE_UINT64
    }
    if (kind == TypeKind.TYPE_INT32 || kind == TypeKind.TYPE_UINT32) {
        return TypeKind.TYPE_UINT32
    }
    if (kind == TypeKind.TYPE_INT16 || kind == TypeKind.TYPE_UINT16) {
        return TypeKind.TYPE_UINT16
    }
    if (kind == TypeKind.TYPE_INT8 || kind == TypeKind.TYPE_UINT8) {
        return TypeKind.TYPE_UINT8
    }
    return TypeKind.TYPE_UNIT
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:158-183.
private func GetTraceCompareSyscallName(binaryOp: BinaryExpression): String {
    let compareMap = HashMap<TypeKind, String>([
        (TypeKind.TYPE_UINT8, SanCovTraceCmp1),
        (TypeKind.TYPE_UINT16, SanCovTraceCmp2),
        (TypeKind.TYPE_UINT32, SanCovTraceCmp4),
        (TypeKind.TYPE_UINT64, SanCovTraceCmp8)
    ])
    let compareConstMap = HashMap<TypeKind, String>([
        (TypeKind.TYPE_UINT8, SanCovTraceConstCmp1),
        (TypeKind.TYPE_UINT16, SanCovTraceConstCmp2),
        (TypeKind.TYPE_UINT32, SanCovTraceConstCmp4),
        (TypeKind.TYPE_UINT64, SanCovTraceConstCmp8)
    ])
    let lhsTy = binaryOp.GetLHSOperand().GetType().getOrThrow()
    let rhsTy = binaryOp.GetRHSOperand().GetType().getOrThrow()
    let curSize = GetTraceCompareType(lhsTy.GetTypeKind())
    let hasArgsConst = lhsTy.IsConstant() || rhsTy.IsConstant()
    return if (hasArgsConst) {
        compareConstMap.get(curSize).getOrThrow()
    } else {
        compareMap.get(curSize).getOrThrow()
    }
}

// C++: CHIR/Transformation/SanitizerCoverage.h:21-100 and SanitizerCoverage.cpp:185-188.
public class SanitizerCoverage {
    private let sanCovOption: SanitizerCoverageOptions
    private let pcArray: ArrayList<(String, DebugLocation)> = ArrayList<(String, DebugLocation)>()
    private let funcBag: HashMap<String, Function> = HashMap<String, Function>()
    private let globalVarBag: HashMap<String, GlobalVar> = HashMap<String, GlobalVar>()
    private var bbCounter: Int64 = 0
    private var packageName: String = ""
    private let builder: CHIRBuilder

    public init(option: GlobalOptions, builder: CHIRBuilder) {
        sanCovOption = option.sancovOption
        this.builder = builder
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:290-343.
    private func InjectTraceForCmp(binary: BinaryExpression, isDebug: Bool): Unit {
        let cmpToken = ArrayList<ExprKind>([
            ExprKind.LT, ExprKind.GT, ExprKind.LE, ExprKind.GE, ExprKind.NOTEQUAL, ExprKind.EQUAL
        ])
        if (!cmpToken.contains(binary.GetExprKind())) {
            return
        }

        var lhs = binary.GetLHSOperand()
        var rhs = binary.GetRHSOperand()
        let lhsTy = lhs.GetType().getOrThrow()
        let curSize = GetTraceCompareType(lhsTy.GetTypeKind())
        if (curSize == TypeKind.TYPE_UNIT) {
            return
        }

        let parent = binary.GetParentBlock().getOrThrow()
        if ((let Some(intTy) <- (lhsTy as IntType)) && intTy.IsSigned()) {
            let unsignedType = if (curSize == TypeKind.TYPE_UINT8) {
                builder.context.GetUInt8Ty()
            } else if (curSize == TypeKind.TYPE_UINT16) {
                builder.context.GetUInt16Ty()
            } else if (curSize == TypeKind.TYPE_UINT32) {
                builder.context.GetUInt32Ty()
            } else {
                builder.context.GetUInt64Ty()
            }
            let lhsCast = builder.CreateTypeCast(unsignedType, lhs, parent)
            let rhsCast = builder.CreateTypeCast(unsignedType, rhs, parent)
            lhsCast.SetDebugLocation(binary.GetDebugLocation())
            rhsCast.SetDebugLocation(binary.GetDebugLocation())
            lhs = lhsCast.GetResult().getOrThrow()
            rhs = rhsCast.GetResult().getOrThrow()
            lhsCast.MoveBefore(binary)
            rhsCast.MoveBefore(binary)
        }

        let callName = GetTraceCompareSyscallName(binary)
        let paramTypes = ArrayList<Type>([lhs.GetType().getOrThrow(), rhs.GetType().getOrThrow()])
        let funcTy = builder.context.GetFuncTy(paramTypes, builder.context.GetUnitTy(), isCFunc: true)
        let callee = GenerateForeignFunc(callName, binary.GetDebugLocation(), funcTy, packName: packageName)
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), callee,
            ArrayList<Value>([lhs, rhs]), parent, builder, loc: binary.GetDebugLocation())
        syscall.MoveBefore(binary)

        if (isDebug) {
            println("[SanitizerCoverage] Add trace compares" + ToPosInfo(binary.GetDebugLocation()) + ".")
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:345-399.
    private func InjectTraceForSwitch(mb: MultiBranch, isDebug: Bool): Unit {
        let conditionTy = mb.GetCondition().GetType().getOrThrow()
        if (!conditionTy.IsInteger() && !conditionTy.IsRune()) {
            return
        }
        let u64Ty = builder.context.GetUInt64Ty()
        let cPointTy = builder.context.GetCPointerTy(u64Ty)
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>([u64Ty, cPointTy]),
            builder.context.GetUnitTy(), isCFunc: true)
        let callee = GenerateForeignFunc(SanCovTraceSwitchName, mb.GetDebugLocation(), funcTy,
            packName: packageName)
        let parent = mb.GetParentBlock().getOrThrow()
        let caseValList = CreateArrayForSwitchCaseList(mb)
        caseValList.MoveBefore(mb)
        let rawDataAcquire = CreateRawDataAcquire(caseValList, u64Ty)
        rawDataAcquire.MoveBefore(mb)
        var switchVal = mb.GetCondition()
        if (switchVal.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_UINT64) {
            let typeCast = builder.CreateTypeCast(u64Ty, switchVal, parent)
            typeCast.SetDebugLocation(mb.GetDebugLocation())
            switchVal = typeCast.GetResult().getOrThrow()
            typeCast.MoveBefore(mb)
        }
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), callee,
            ArrayList<Value>([switchVal, rawDataAcquire.GetResult().getOrThrow()]), parent, builder,
            loc: mb.GetDebugLocation())
        syscall.MoveBefore(mb)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace switch" + ToPosInfo(mb.GetDebugLocation()) + ".")
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:794-834.
    private func CreateArrayForSwitchCaseList(multiBranch: MultiBranch): RawArrayAllocate {
        let cases = multiBranch.GetCaseVals()
        let caseVals = ArrayList<Value>()
        let loc = multiBranch.GetDebugLocation()
        let parent = multiBranch.GetParentBlock().getOrThrow()
        let caseSize = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(UInt64(cases.size)), parent)
        caseSize.SetDebugLocation(loc)
        caseVals.add(caseSize.GetResult().getOrThrow())
        caseSize.MoveBefore(multiBranch)

        let elemBitSize = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(64u64), parent)
        elemBitSize.SetDebugLocation(loc)
        caseVals.add(elemBitSize.GetResult().getOrThrow())
        elemBitSize.MoveBefore(multiBranch)

        for (caseVal in cases) {
            let valExpr = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(caseVal), parent)
            valExpr.SetDebugLocation(loc)
            caseVals.add(valExpr.GetResult().getOrThrow())
            valExpr.MoveBefore(multiBranch)
        }

        let listSize = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(UInt64(cases.size + 2)), parent)
        listSize.SetDebugLocation(loc)
        listSize.MoveBefore(multiBranch)
        let arrayTy = builder.context.GetRefTy(builder.context.GetRawArrayTy(builder.context.GetUInt64Ty()))
        return builder.CreateRawArrayAllocate(arrayTy, builder.context.GetUInt64Ty(),
            listSize.GetResult().getOrThrow(), parent)
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:836-846.
    private func CreateRawDataAcquire(dataList: Expression, elementType: Type): Intrinsic {
        let cPointerTy = builder.context.GetCPointerTy(elementType)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA,
            args: ArrayList<Value>([dataList.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([elementType]))
        let result = builder.CreateIntrinsic(cPointerTy, callContext, dataList.GetParentBlock().getOrThrow())
        result.SetDebugLocation(dataList.GetDebugLocation())
        return result
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1016-1027.
    private func GenerateForeignFunc(globalFuncName: String, loc: DebugLocation, funcType: FuncType,
        packName!: String = ""): Function {
        if (let Some(value) <- funcBag.get(globalFuncName)) {
            return value
        }
        let function = builder.CreateFunction(funcType, globalFuncName, srcCodeIdentifier: globalFuncName,
            packageName: packName)
        function.EnableAttr(Attribute.IMPORTED)
        function.EnableAttr(Attribute.FOREIGN)
        funcBag[globalFuncName] = function
        return function
    }
}
